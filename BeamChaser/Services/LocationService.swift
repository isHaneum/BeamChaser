import Foundation
import CoreLocation
import CoreMotion
import Combine
#if targetEnvironment(simulator)
import GameController
#endif

/// 위치 서비스 — GPS + 보수계 센서 퓨전으로 정확한 거리/페이스 계산
@MainActor
final class LocationService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var currentLocation: CLLocation?
    @Published var currentSpeed: Double = 0           // m/s
    @Published var currentPaceSecondsPerKm: Double = 0
    @Published var currentCadenceSpm: Double = 0
    @Published var totalDistanceMeters: Double = 0
    @Published var routePoints: [RoutePoint] = []
    @Published var isTracking = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationError: String?
    @Published private(set) var sessionStepCount: Int = 0

    /// 현재 속도 데이터 소스 (디버그/UI 표시용)
    @Published var paceSource: PaceSource = .gps

    enum PaceSource: String {
        case gps = "GPS"
        case pedometer = "모션센서"
        case fused = "퓨전"
    }

    // MARK: - Private — GPS

    private let locationManager = CLLocationManager()
    private var previousLocation: CLLocation?

    // 페이스 평활화용 (최근 5개 속도 평균)
    private var recentSpeeds: [Double] = []
    private let smoothingWindow = 5

    // MARK: - Private — CMPedometer (보수계 + 모션 코프로세서)

    private let pedometer = CMPedometer()
    private var pedometerDistance: Double = 0        // 보수계 누적 거리
    private var pedometerSpeed: Double = 0           // 보수계 기반 속도 (m/s)
    private var lastPedometerUpdate: Date?

    /// 보행 보폭 보정 계수 (러닝 시 보수계 거리를 GPS로 보정)
    private var strideCalibration: Double = 1.0
    private var calibrationSamples: [(gps: Double, pedometer: Double)] = []
    private var shouldStartTrackingAfterAuthorization = false

    // MARK: - 시뮬레이터 테스트 모드 (가속도 방식)

    @Published var isSimulatorMode = false
    @Published var simulatorSpeed: Double = 0  // 현재 속도 m/s (UI 표시용)
    @Published var simulatedCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(
        latitude: 37.5665, longitude: 126.9780  // 서울시청 기본 좌표
    )
    private var simulatorVelocityX: Double = 0  // 동서 속도 (m/s, 양수=동쪽)
    private var simulatorVelocityY: Double = 0  // 남북 속도 (m/s, 양수=북쪽)
    private let accelerationStep: Double = 0.5  // 탭당 가속 (m/s)
    private let maxSimulatorSpeed: Double = 12.0  // 최대 속도 (m/s)
    private var simulatorMoveTimer: Timer?
    /// 현재 이동 방향 (라디안, 0=북쪽, 시계방향)
    @Published var simulatorHeading: Double = 0

    #if targetEnvironment(simulator)
    private var keyboardObserver: Any?
    private var keyRepeatTimer: Timer?
    private var currentKeyDirection: SimulatorDirection?
    #endif

    enum SimulatorDirection {
        case up, down, left, right
    }

    // MARK: - Init

    override init() {
        super.init()
        locationManager.delegate = self
        authorizationStatus = locationManager.authorizationStatus
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5  // 5m마다 업데이트
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
    }

    // MARK: - Public API

    func requestPermission() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    /// 홈 화면에서 현위치 1회 갱신 (트래킹 없이)
    func requestCurrentLocation() {
        guard authorizationStatus == .authorizedWhenInUse ||
              authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }
        locationManager.requestLocation()
    }

    func startTracking() {
        guard authorizationStatus == .authorizedWhenInUse ||
              authorizationStatus == .authorizedAlways else {
            shouldStartTrackingAfterAuthorization = true
            requestPermission()
            return
        }

        reset()
        isTracking = true

        // 백그라운드 위치 추적은 Always 권한이 있을 때만 활성화
        if authorizationStatus == .authorizedAlways {
            locationManager.allowsBackgroundLocationUpdates = true
        }

        locationManager.startUpdatingLocation()
        startPedometer()
    }

    /// BLE 연결 테스트 중에도 위치/속도 텔레메트리가 흐르도록 필요할 때만 트래킹을 켭니다.
    func startTrackingForBLETelemetryIfNeeded() {
        guard !isTracking else { return }

        let currentStatus = locationManager.authorizationStatus
        authorizationStatus = currentStatus

        guard currentStatus == .authorizedWhenInUse ||
              currentStatus == .authorizedAlways else {
            shouldStartTrackingAfterAuthorization = true
            requestPermission()
            return
        }

        startTracking()
    }

    func stopTracking() {
        isTracking = false
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.stopUpdatingLocation()
        stopPedometer()
        simulatorStop()
    }

    func reset() {
        totalDistanceMeters = 0
        routePoints.removeAll()
        recentSpeeds.removeAll()
        previousLocation = nil
        currentSpeed = 0
        currentPaceSecondsPerKm = 0
        currentCadenceSpm = 0
        pedometerDistance = 0
        pedometerSpeed = 0
        sessionStepCount = 0
        lastPedometerUpdate = nil
        strideCalibration = 1.0
        calibrationSamples.removeAll()
        paceSource = .gps
    }

    // MARK: - 유효 속도 범위 (페이스 1분/km ~ 20분/km)
    // 1분/km = 16.67 m/s, 20분/km = 0.833 m/s
    private static let minValidSpeedMs: Double = 0.834  // 20분/km 이하 → 걷기/정지로 간주
    private static let maxValidSpeedMs: Double = 15.0   // 1분/km 미만 → 비현실적 GPS 오류

    // MARK: - Private Helpers

    private func processLocation(_ location: CLLocation) {
        if !currentSpeed.isFinite { currentSpeed = 0 }
        if !currentPaceSecondsPerKm.isFinite { currentPaceSecondsPerKm = 0 }
        if !pedometerSpeed.isFinite { pedometerSpeed = 0 }

        // 정확도 필터 — 20m 초과 오차 무시
        let gpsIsGood = location.horizontalAccuracy > 0 && location.horizontalAccuracy < 20

        if gpsIsGood {
            let routePoint = RoutePoint(from: location)
            routePoints.append(routePoint)
            currentLocation = location

            // GPS 거리 계산
            if let prev = previousLocation {
                let delta = location.distance(from: prev)
                let timeDelta = location.timestamp.timeIntervalSince(prev.timestamp)
                let instantSpeed = timeDelta > 0 ? delta / timeDelta : 0
                // 비정상 속도 구간 거리 제외 (페이스 1분~20분/km 범위 외)
                if timeDelta > 0,
                   instantSpeed <= LocationService.maxValidSpeedMs,
                   instantSpeed >= LocationService.minValidSpeedMs {
                    totalDistanceMeters += delta

                    // 보수계 보정 계수 업데이트 (GPS가 정확할 때)
                    if pedometerDistance > 50 {
                        calibrationSamples.append((gps: totalDistanceMeters, pedometer: pedometerDistance))
                        if calibrationSamples.count > 10 { calibrationSamples.removeFirst() }
                        updateStrideCalibration()
                    }
                }
            }
            previousLocation = location

            // GPS 속도 (평활화)
            let gpsSpeed = sanitizedNonNegativeSpeed(location.speed)
            recentSpeeds.append(gpsSpeed)
            if recentSpeeds.count > smoothingWindow { recentSpeeds.removeFirst() }

            let avgGpsSpeed = averageFiniteSpeed(recentSpeeds)

            // 센서 퓨전: GPS + 보수계 가중 평균
            let fusedSpeed = sanitizedNonNegativeSpeed(
                fuseSpeeds(gpsSpeed: avgGpsSpeed, gpsAccuracy: location.horizontalAccuracy)
            )
            currentSpeed = fusedSpeed

            // 유효 페이스 범위(1분~20분/km)에서만 페이스 업데이트
            if fusedSpeed >= LocationService.minValidSpeedMs && fusedSpeed <= LocationService.maxValidSpeedMs {
                currentPaceSecondsPerKm = 1000.0 / fusedSpeed
            } else if !currentPaceSecondsPerKm.isFinite {
                currentPaceSecondsPerKm = 0
            }
            // fusedSpeed가 범위 밖이면 마지막 유효 페이스값 유지
        } else {
            // GPS 불량 — 보수계 단독 모드 (터널, 실내 등)
            if pedometerSpeed >= LocationService.minValidSpeedMs && pedometerSpeed <= LocationService.maxValidSpeedMs {
                paceSource = .pedometer
                currentSpeed = pedometerSpeed
                currentPaceSecondsPerKm = 1000.0 / pedometerSpeed

                // 보수계로 거리 보정 (GPS 못 받는 구간)
                if let lastUpdate = lastPedometerUpdate {
                    let elapsed = Date().timeIntervalSince(lastUpdate)
                    if elapsed > 0, elapsed < 5 {
                        totalDistanceMeters += pedometerSpeed * elapsed
                    }
                }
            }
        }
    }

    // MARK: - 센서 퓨전

    /// GPS와 보수계 속도를 GPS 정확도 기반 가중 평균으로 합침
    private func fuseSpeeds(gpsSpeed: Double, gpsAccuracy: Double) -> Double {
        let safeGPSSpeed = sanitizedNonNegativeSpeed(gpsSpeed)
        let safePedometerSpeed = sanitizedNonNegativeSpeed(pedometerSpeed)
        let safeGPSAccuracy = gpsAccuracy.isFinite ? max(0, gpsAccuracy) : 50

        guard safePedometerSpeed > 0.3 else {
            paceSource = .gps
            return safeGPSSpeed
        }

        // GPS 정확도에 따른 가중치 (정확도 높을수록 GPS 비중 높음)
        // accuracy 5m → GPS 90%, accuracy 15m → GPS 50%, accuracy 20m → GPS 30%
        let gpsWeight = max(0.3, min(0.95, 1.0 - (safeGPSAccuracy / 25.0)))
        let pedWeight = 1.0 - gpsWeight

        let safeStrideCalibration = strideCalibration.isFinite ? strideCalibration : 1.0
        let calibratedPedSpeed = safePedometerSpeed * safeStrideCalibration
        let fused = safeGPSSpeed * gpsWeight + calibratedPedSpeed * pedWeight

        paceSource = .fused
        return sanitizedNonNegativeSpeed(fused)
    }

    /// 보수계 보폭 보정 계수 업데이트
    private func updateStrideCalibration() {
        guard calibrationSamples.count >= 3 else { return }

        // 최근 GPS 거리 vs 보수계 거리 비율의 중앙값
        let ratios = calibrationSamples
            .map { $0.gps / max(1, $0.pedometer) }
            .filter { $0.isFinite }
            .sorted()

        guard !ratios.isEmpty else { return }

        let mid = ratios.count / 2
        let median = ratios.count % 2 == 0
            ? (ratios[mid - 1] + ratios[mid]) / 2.0
            : ratios[mid]

        // 보정 범위 제한 (0.7 ~ 1.4 — 비현실적 보정 방지)
        strideCalibration = max(0.7, min(1.4, median))
    }

    // MARK: - CMPedometer (보수계)

    private func startPedometer() {
        guard CMPedometer.isDistanceAvailable() || CMPedometer.isStepCountingAvailable() else { return }

        let status = CMPedometer.authorizationStatus()
        guard status == .authorized || status == .notDetermined else { return }

        // .notDetermined일 때 startUpdates가 권한 요청을 트리거함
        // 하지만 TCC 위반 방지를 위해 안전하게 래핑
        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            guard let data = data, error == nil else { return }

            Task { @MainActor [weak self] in
                guard let self = self else { return }

                // 보수계 누적 거리
                if let distance = data.distance {
                    self.pedometerDistance = distance.doubleValue
                }

                self.sessionStepCount = data.numberOfSteps.intValue

                // 보수계 기반 속도 계산
                if let currentPace = data.currentPace {
                    // currentPace = seconds per meter
                    let secPerMeter = currentPace.doubleValue
                    if secPerMeter > 0, secPerMeter.isFinite {
                        let speed = 1.0 / secPerMeter
                        // 비정상 속도 무시 (페이스 1분~20분/km 범위)
                        if speed.isFinite,
                           speed >= LocationService.minValidSpeedMs,
                           speed <= LocationService.maxValidSpeedMs {
                            self.pedometerSpeed = speed
                        }
                    }
                } else if let distance = data.distance {
                    // currentPace가 없으면 거리/시간으로 추정
                    let elapsed = data.endDate.timeIntervalSince(data.startDate)
                    if elapsed > 0 {
                        let speed = distance.doubleValue / elapsed
                        if speed.isFinite,
                           speed >= LocationService.minValidSpeedMs,
                           speed <= LocationService.maxValidSpeedMs {
                            self.pedometerSpeed = speed
                        }
                    }
                }

                if let currentCadence = data.currentCadence {
                    self.currentCadenceSpm = max(0, min(260, currentCadence.doubleValue * 60.0))
                } else {
                    let elapsed = data.endDate.timeIntervalSince(data.startDate)
                    self.currentCadenceSpm = elapsed > 0
                        ? max(0, min(260, data.numberOfSteps.doubleValue / elapsed * 60.0))
                        : 0
                }

                self.lastPedometerUpdate = Date()
            }
        }
    }

    private func stopPedometer() {
        pedometer.stopUpdates()
    }

    private func sanitizedNonNegativeSpeed(_ value: Double) -> Double {
        guard value.isFinite, value >= 0 else { return 0 }
        return min(value, LocationService.maxValidSpeedMs)
    }

    private func averageFiniteSpeed(_ speeds: [Double]) -> Double {
        let finiteSpeeds = speeds.filter { $0.isFinite && $0 >= 0 }
        guard !finiteSpeeds.isEmpty else { return 0 }
        return finiteSpeeds.reduce(0, +) / Double(finiteSpeeds.count)
    }

    // MARK: - 시뮬레이터 (가속도 방식)

    func enableSimulatorMode() {
        isSimulatorMode = true
    }

    func startTracking_simulator() {
        reset()
        isTracking = true
        isSimulatorMode = true
        paceSource = .gps

        // 초기 위치 설정
        let initLocation = CLLocation(
            coordinate: simulatedCoordinate,
            altitude: 20,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: Date()
        )
        currentLocation = initLocation
        processLocation(initLocation)

        #if targetEnvironment(simulator)
        startKeyboardMonitoring()
        #endif
    }

    /// 시뮬레이터 속도 직접 설정 (km/h)
    func setSimulatorSpeedKmh(_ kmh: Double) {
        let ms = kmh / 3.6
        simulatorSpeed = ms
        // 속도 성분 업데이트 (북쪽 방향 고정으로 시뮬레이션)
        simulatorVelocityX = 0
        simulatorVelocityY = ms
        
        if ms > 0.05 {
            ensureSimulatorTimer()
        } else {
            simulatorStop()
        }
    }

    /// 방향 버튼 → 해당 방향으로 가속 (accelerator 방식)
    func simulatorAccelerate(_ direction: SimulatorDirection) {
        guard isSimulatorMode, isTracking else { return }

        switch direction {
        case .up:    simulatorVelocityY += accelerationStep
        case .down:  simulatorVelocityY -= accelerationStep
        case .left:  simulatorVelocityX -= accelerationStep
        case .right: simulatorVelocityX += accelerationStep
        }

        // 속도 제한
        simulatorVelocityX = max(-maxSimulatorSpeed, min(maxSimulatorSpeed, simulatorVelocityX))
        simulatorVelocityY = max(-maxSimulatorSpeed, min(maxSimulatorSpeed, simulatorVelocityY))

        simulatorSpeed = sqrt(simulatorVelocityX * simulatorVelocityX + simulatorVelocityY * simulatorVelocityY)
        if simulatorSpeed > 0.1 {
            simulatorHeading = atan2(simulatorVelocityX, simulatorVelocityY)  // 라디안
        }
        ensureSimulatorTimer()
    }

    /// 속도 리셋 (정지)
    func simulatorStop() {
        simulatorVelocityX = 0
        simulatorVelocityY = 0
        simulatorSpeed = 0
        simulatorMoveTimer?.invalidate()
        simulatorMoveTimer = nil
        #if targetEnvironment(simulator)
        stopKeyboardMonitoring()
        #endif
    }

    #if targetEnvironment(simulator)
    /// GCController 키보드 입력 모니터링
    private func startKeyboardMonitoring() {
        stopKeyboardMonitoring()

        // 이미 연결된 키보드 확인
        if let keyboard = GCKeyboard.coalesced {
            setupKeyboardHandlers(keyboard)
        }

        // 키보드 연결 감지
        keyboardObserver = NotificationCenter.default.addObserver(
            forName: .GCKeyboardDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let keyboard = notification.object as? GCKeyboard {
                Task { @MainActor [weak self] in
                    self?.setupKeyboardHandlers(keyboard)
                }
            }
        }
    }

    private func setupKeyboardHandlers(_ keyboard: GCKeyboard) {
        guard let input = keyboard.keyboardInput else { return }

        // keyChangedHandler: (GCKeyboardInput, GCControllerButtonInput, GCKeyCode, Bool)
        input.keyChangedHandler = { [weak self] _, _, keyCode, pressed in
            Task { @MainActor [weak self] in
                guard let self = self, self.isTracking, self.isSimulatorMode else { return }

                let direction: SimulatorDirection? = switch keyCode {
                case .upArrow: .up
                case .downArrow: .down
                case .leftArrow: .left
                case .rightArrow: .right
                default: nil
                }

                if keyCode == .spacebar && pressed {
                    self.simulatorVelocityX = 0
                    self.simulatorVelocityY = 0
                    self.simulatorSpeed = 0
                    self.simulatorMoveTimer?.invalidate()
                    self.simulatorMoveTimer = nil
                    return
                }

                guard let dir = direction else { return }

                if pressed {
                    // 즉시 1회 가속
                    self.simulatorAccelerate(dir)
                    self.currentKeyDirection = dir
                    // 꾹 누르고 있으면 0.08초마다 반복 가속
                    self.keyRepeatTimer?.invalidate()
                    self.keyRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            self.simulatorAccelerate(dir)
                        }
                    }
                } else {
                    // 키 떼면 반복 가속 중단 (속도는 유지)
                    if self.currentKeyDirection == dir {
                        self.keyRepeatTimer?.invalidate()
                        self.keyRepeatTimer = nil
                        self.currentKeyDirection = nil
                    }
                }
            }
        }
    }

    private func stopKeyboardMonitoring() {
        if let observer = keyboardObserver {
            NotificationCenter.default.removeObserver(observer)
            keyboardObserver = nil
        }
        keyRepeatTimer?.invalidate()
        keyRepeatTimer = nil
        currentKeyDirection = nil
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil
    }
    #endif

    private func ensureSimulatorTimer() {
        guard simulatorMoveTimer == nil else { return }
        let interval: TimeInterval = 0.3
        simulatorMoveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.simulatorTick(interval)
            }
        }
    }

    private func simulatorTick(_ dt: TimeInterval) {
        guard isTracking, isSimulatorMode else {
            simulatorStop()
            return
        }

        let speed = sqrt(simulatorVelocityX * simulatorVelocityX + simulatorVelocityY * simulatorVelocityY)
        guard speed > 0.05 else {
            simulatorStop()
            return
        }

        let dy = simulatorVelocityY * dt  // 북쪽 이동량 (m)
        let dx = simulatorVelocityX * dt  // 동쪽 이동량 (m)

        let latStep = dy / 111_320.0
        let lonStep = dx / (111_320.0 * cos(simulatedCoordinate.latitude * .pi / 180))

        simulatedCoordinate.latitude += latStep
        simulatedCoordinate.longitude += lonStep

        let heading = atan2(simulatorVelocityX, simulatorVelocityY) * 180.0 / .pi
        let courseValue = heading >= 0 ? heading : heading + 360
        let simLocation = CLLocation(
            coordinate: simulatedCoordinate,
            altitude: 20,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: courseValue,
            speed: speed,
            timestamp: Date()
        )
        processLocation(simLocation)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = status
            let isAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
            if shouldStartTrackingAfterAuthorization, isAuthorized {
                shouldStartTrackingAfterAuthorization = false
                startTracking()
            } else if status == .denied || status == .restricted {
                shouldStartTrackingAfterAuthorization = false
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations {
                processLocation(location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationError = error.localizedDescription
        }
    }
}
