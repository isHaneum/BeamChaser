import Foundation
import Combine
import AVFoundation
import CoreLocation

enum RunSessionFinishError: LocalizedError {
    case noActiveRecord
    case insufficientData

    var errorDescription: String? {
        switch self {
        case .noActiveRecord:
            return "러닝 기록을 저장할 데이터가 없습니다."
        case .insufficientData:
            return "러닝 기록을 저장하지 못했어요. 다시 시도해주세요."
        }
    }
}

/// 러닝 세션 매니저 — 전체 러닝 라이프사이클 관리
@MainActor
final class RunSessionManager: ObservableObject {

    // MARK: - Published State

    @Published var runState: RunState = .idle
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var currentRecord: RunRecord?
    @Published var savedRecords: [RunRecord] = []
    @Published var goalReached = false
    @Published var coachingAlert: String?

    // MARK: - Sub-Engines

    let paceMaker = PaceMakerEngine()
    let healthKit = HealthKitService()
    lazy var coaching = PaceCoachingService(healthKit: healthKit)
    var bleService: BLEService?  // App 진입점에서 주입
    weak var locationService: LocationService?  // App 진입점에서 주입

    // MARK: - Private

    private var timer: Timer?
    private var phoneTelemetryTimer: Timer?
    private var runStartTime: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauseStartTime: Date?
    private var cancellables = Set<AnyCancellable>()

    private var savePath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("run_records.json")
    }

    // MARK: - Init

    init() {
        loadRecords()
        setupObservations()
    }

    private func setupObservations() {
        // 1. 페이스 상태(ahead, onPace, behind) 변화를 관찰하여 BLE Zone 명령 전송
        paceMaker.$paceStatus
            .sink { [weak self] status in
                guard let self = self, self.runState == .running else { return }
                self.syncBLEZone(status)
            }
            .store(in: &cancellables)
            
        // 2. 심박수 관찰 -> 지능형 감속 (Safety Valve)
        healthKit.$currentHeartRate
            .sink { [weak self] bpm in
                guard let self = self, self.runState == .running, bpm > 0 else { return }
                self.checkSafetyAndCoaching(bpm: bpm)
            }
            .store(in: &cancellables)
            
        // 3. 엔진의 적응 상태 관찰 -> 사용자 알림
        paceMaker.$adaptiveState
            .sink { [weak self] state in
                guard let self = self, self.runState == .running else { return }
                if state == .waiting {
                    self.coachingAlert = "러너가 뒤처졌습니다. 레이저가 속도를 늦춰 기다립니다."
                } else if state == .recovering {
                    self.coachingAlert = "러너가 복귀했습니다. 다시 페이스를 올립니다."
                }
            }
            .store(in: &cancellables)
    }

    private func checkSafetyAndCoaching(bpm: Double) {
        if bpm > 180 { // 심각한 과부하
            if paceMaker.adaptiveState != .waiting {
                // 심박수 초과 시 즉각 알림 (속도 제어는 PaceMakerEngine 확장 시 추가)
                self.coachingAlert = "심박수가 매우 높습니다! 안전을 위해 속도를 늦추세요."
            }
        }
    }

    private func syncBLEZone(_ status: PaceMakerEngine.PaceStatus) {
        guard let ble = bleService, ble.isConnected else { return }
        guard locationService?.isPaceReliable ?? true else { return }
        ble.setZone(deviceZone(for: status))
    }

    // MARK: - 러닝 제어

    @Published var runGoal: RunGoal?
    @Published var intervalProgram: IntervalProgram?
    @Published var currentIntervalIndex: Int = 0

    func startRun(target: PaceTarget?, goal: RunGoal? = nil, intervalProgram: IntervalProgram? = nil) {
        let record = RunRecord(
            id: UUID(),
            startDate: Date(),
            routePoints: [],
            totalDistanceMeters: 0,
            elapsedSeconds: 0,
            targetPace: target,
            runGoal: goal,
            intervalProgram: intervalProgram
        )
        currentRecord = record
        self.runGoal = goal
        self.intervalProgram = intervalProgram
        self.currentIntervalIndex = 0
        goalReached = false
        runStartTime = Date()
        pausedDuration = 0
        elapsedSeconds = 0

        if let target = target {
            paceMaker.start(target: target)
            // BLE: 목표 페이스 전송
            bleService?.sendTargetPace(secondsPerKm: Int(target.totalSecondsPerKm))
        }

        // HealthKit 운동 세션 시작
        Task {
            await healthKit.startWorkout()
        }

        // BLE: 러닝 시작
        bleService?.startRun()
        startPhoneTelemetry()

        runState = .running
        startTimer()
    }

    func pauseRun() {
        guard runState == .running else { return }
        runState = .paused
        pauseStartTime = Date()
        stopTimer()
        // BLE: 레이저 일시정지 (OFF)
        bleService?.turnLaserOff()
    }

    func resumeRun() {
        guard runState == .paused, let pauseStart = pauseStartTime else { return }
        pausedDuration += Date().timeIntervalSince(pauseStart)
        pauseStartTime = nil
        runState = .running
        startTimer()
        // BLE: 레이저 재개 (ON)
        bleService?.turnLaserOn()
    }

    @discardableResult
    func finishRun(
        routePoints: [RoutePoint],
        totalDistance: Double,
        averageCadenceSpm: Int? = nil,
        averageHeartRateBpm: Int? = nil
    ) throws -> RunRecord {
        guard runState == .running || runState == .paused || runState == .finished else {
            throw RunSessionFinishError.noActiveRecord
        }

        if runState == .running || runState == .paused {
            stopTimer()
            paceMaker.stop()
            bleService?.stopRun()
            runState = .finished

            guard var record = currentRecord else {
                Task { [weak self] in await self?.healthKit.discardWorkout() }
                throw RunSessionFinishError.noActiveRecord
            }

            record.endDate = Date()
            record.routePoints = sanitizedRoutePoints(routePoints)
            record.totalDistanceMeters = totalDistance
            record.elapsedSeconds = elapsedSeconds
            record.averageCadenceSpm = averageCadenceSpm
            record.averageHeartRateBpm = averageHeartRateBpm
            applyDerivedMetrics(to: &record)
            currentRecord = record
        }

        guard let record = currentRecord else {
            Task { [weak self] in await self?.healthKit.discardWorkout() }
            throw RunSessionFinishError.noActiveRecord
        }

        #if targetEnvironment(simulator)
        let minDistance: Double = 10
        #else
        let minDistance: Double = 10
        #endif
        guard record.totalDistanceMeters >= minDistance else {
            Task { [weak self] in await self?.healthKit.discardWorkout() }
            throw RunSessionFinishError.insufficientData
        }

        if !savedRecords.contains(where: { $0.id == record.id }) {
            savedRecords.insert(record, at: 0)
            do {
                try saveRecordsOrThrow()
            } catch {
                savedRecords.removeAll { $0.id == record.id }
                throw error
            }

            Task { [weak self] in
                await self?.healthKit.endWorkout(
                    totalDistance: record.totalDistanceMeters,
                    totalDuration: self?.elapsedSeconds ?? 0
                )
            }
        }

        return record
    }

    func updateTargetPace(_ target: PaceTarget) {
        guard runState == .running || runState == .paused else { return }

        if var record = currentRecord {
            record.targetPace = target
            currentRecord = record
        }

        paceMaker.start(target: target)
        bleService?.sendTargetPace(secondsPerKm: Int(target.totalSecondsPerKm))
    }

    func resetSession() {
        stopTimer()
        paceMaker.stop()
        paceMaker.reset()
        // finished/idle 상태는 이미 endWorkout/discardWorkout 처리됨 — 중복 호출 방지
        if runState != .finished && runState != .idle {
            Task { [weak self] in await self?.healthKit.discardWorkout() }
        }
        currentRecord = nil
        elapsedSeconds = 0
        runState = .idle
        goalReached = false
        runGoal = nil
        intervalProgram = nil
        currentIntervalIndex = 0
    }

    // MARK: - 페이스메이커 업데이트 (LocationService에서 호출)

    func updatePace(distance: Double) {
        if locationService?.isPaceReliable ?? true {
            paceMaker.update(actualDistanceMeters: distance, elapsedSeconds: elapsedSeconds)
        }

        // 인터벌 모드: 구간 전환 체크
        if let interval = intervalProgram, !interval.segments.isEmpty {
            var accum: Double = 0
            var matchedIndex: Int?
            for (index, segment) in interval.segments.enumerated() {
                accum += segment.distanceKm * 1000
                if distance < accum {
                    matchedIndex = index
                    break
                }
            }
            // 전체 거리 초과 시 마지막 구간 유지
            let targetIndex = matchedIndex ?? (interval.segments.count - 1)
            if targetIndex != currentIntervalIndex {
                currentIntervalIndex = targetIndex
                let segment = interval.segments[targetIndex]
                let newTarget = PaceTarget(
                    minutesPerKm: segment.paceMinutes,
                    secondsPerKm: segment.paceSeconds
                )
                paceMaker.start(target: newTarget)
            }
        }

        // 목표 달성 체크
        if let goal = runGoal {
            switch goal.type {
            case .distance:
                if let targetKm = goal.targetDistanceKm, distance / 1000.0 >= targetKm {
                    // 목표 거리 달성 — UI에서 알림 처리
                    goalReached = true
                }
            case .time:
                if let targetMin = goal.targetTimeMinutes, elapsedSeconds >= Double(targetMin * 60) {
                    goalReached = true
                }
            case .combined:
                let reachedDistance = goal.targetDistanceKm.map { distance / 1000.0 >= $0 } ?? false
                let reachedTime = goal.targetTimeMinutes.map { elapsedSeconds >= Double($0 * 60) } ?? false
                if reachedDistance || reachedTime {
                    goalReached = true
                }
            case .none:
                break
            }
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let startTime = runStartTime, runState == .running else { return }
        elapsedSeconds = Date().timeIntervalSince(startTime) - pausedDuration
    }

    func startPhoneTelemetry() {
        syncPhoneTelemetry()
        guard phoneTelemetryTimer == nil else { return }

        phoneTelemetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncPhoneTelemetry()
            }
        }
    }

    func stopPhoneTelemetry() {
        phoneTelemetryTimer?.invalidate()
        phoneTelemetryTimer = nil
    }

    private func syncPhoneTelemetry() {
        guard let ble = bleService, ble.isConnected, let locationService else { return }

        let location = locationService.currentLocation
        let latitude = location?.coordinate.latitude ?? 0
        let longitude = location?.coordinate.longitude ?? 0
        let accuracy = location?.horizontalAccuracy ?? -1
        let course = location?.course ?? -1
        let speed = locationService.currentSpeed
        let isPaceReliable = locationService.isPaceReliable
        let isCoordinateValid = latitude.isFinite && longitude.isFinite && accuracy > 0
        let isSpeedValid = isPaceReliable && speed.isFinite && speed > 0
        let isCourseValid = course.isFinite && course >= 0
        let isStaleFix = location.map { Date().timeIntervalSince($0.timestamp) > 5 } ?? false

        var flags: UInt8 = 0
        if isCoordinateValid { flags |= 1 << 0 }
        if isSpeedValid { flags |= 1 << 1 }
        if isCourseValid { flags |= 1 << 2 }
        if isStaleFix { flags |= 1 << 3 }

        let distanceMeters = clampedUInt16(locationService.totalDistanceMeters)
        let elapsedSecondsValue = clampedUInt16(elapsedSeconds)
        let speedCentimetersPerSecond = isSpeedValid ? clampedUInt16(speed * 100) : 0

        let gpsPayload = PhoneGPSPayload(
            latitudeE7: scaledCoordinate(latitude),
            longitudeE7: scaledCoordinate(longitude),
            speedCentimetersPerSecond: speedCentimetersPerSecond,
            courseCentidegrees: isCourseValid ? clampedUInt16(normalizedCourse(course) * 100) : UInt16.max,
            horizontalAccuracyCentimeters: clampedUInt16(max(0, accuracy) * 100),
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSecondsValue,
            flags: flags
        )

        let isRunActive = runState == .running
        let servoAngle = appCalculatedServoAngle(ble: ble)
        if isRunActive, isPaceReliable, abs(ble.servoAngle - Int(servoAngle)) >= 1 {
            ble.setServoAngle(Int(servoAngle))
        }

        var controlFlags: UInt8 = 0
        if isRunActive { controlFlags |= 1 << 0 }
        if ble.isDayModeEnabled { controlFlags |= 1 << 1 }
        if isCoordinateValid { controlFlags |= 1 << 2 }
        if isStaleFix { controlFlags |= 1 << 3 }
        if isSpeedValid { controlFlags |= 1 << 4 }

        let controlPayload = PhoneControlPayload(
            speedCentimetersPerSecond: speedCentimetersPerSecond,
            paceSecondsPerKm: isPaceReliable ? clampedUInt16(locationService.controlPaceSecondsPerKm) : 0,
            targetPaceSecondsPerKm: clampedUInt16(paceMaker.target?.totalSecondsPerKm ?? 0),
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSecondsValue,
            gapCentimeters: clampedInt16(paceMaker.gapMeters * 100),
            servoAngleDegrees: servoAngle,
            zone: isRunActive && isPaceReliable ? deviceZone(for: paceMaker.paceStatus) : .none,
            flags: controlFlags
        )

        ble.sendPhoneGPS(gpsPayload)
        ble.sendPhoneControl(controlPayload)
    }

    private func deviceZone(for status: PaceMakerEngine.PaceStatus) -> DeviceZone {
        switch status {
        case .ahead:  return .blue
        case .onPace: return .green
        case .behind: return .red
        }
    }

    private func appCalculatedServoAngle(ble: BLEService) -> UInt8 {
        let sensitivityRatio = Double(ble.sensitivity) / 128.0
        let targetAngle = 85.0 - (Double(ble.currentPitch) * sensitivityRatio) + Double(ble.calibrationOffset)
        return clampedUInt8(targetAngle, lowerBound: 0, upperBound: 180)
    }

    private func scaledCoordinate(_ coordinate: CLLocationDegrees) -> Int32 {
        let scaled = (coordinate * 10_000_000).rounded()
        guard scaled.isFinite else { return 0 }
        if scaled > Double(Int32.max) { return Int32.max }
        if scaled < Double(Int32.min) { return Int32.min }
        return Int32(scaled)
    }

    private func clampedUInt16(_ value: Double) -> UInt16 {
        guard value.isFinite else { return 0 }
        let clamped = min(max(value.rounded(), 0), Double(UInt16.max))
        return UInt16(clamped)
    }

    private func clampedUInt8(_ value: Double, lowerBound: UInt8, upperBound: UInt8) -> UInt8 {
        guard value.isFinite else { return lowerBound }
        let clamped = min(max(value.rounded(), Double(lowerBound)), Double(upperBound))
        return UInt8(clamped)
    }

    private func clampedInt16(_ value: Double) -> Int16 {
        guard value.isFinite else { return 0 }
        let clamped = min(max(value.rounded(), Double(Int16.min)), Double(Int16.max))
        return Int16(clamped)
    }

    private func normalizedCourse(_ course: CLLocationDirection) -> Double {
        let normalized = course.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }

    // MARK: - 기록 저장/로드

    private func saveRecords() {
        do {
            try saveRecordsOrThrow()
        } catch {
            print("기록 저장 실패: \(error)")
        }
    }

    private func saveRecordsOrThrow() throws {
        let data = try JSONEncoder().encode(savedRecords)
        try data.write(to: savePath, options: .atomic)
    }

    private func loadRecords() {
        guard FileManager.default.fileExists(atPath: savePath.path) else { return }
        do {
            let data = try Data(contentsOf: savePath)
            var records = try JSONDecoder().decode([RunRecord].self, from: data)
            // 기존 기록의 비정상 RoutePoint와 누락된 품질 메타데이터 정리
            var needsSave = false
            for i in records.indices {
                let cleaned = sanitizedRoutePoints(records[i].routePoints)
                if cleaned.count != records[i].routePoints.count {
                    records[i].routePoints = cleaned
                    needsSave = true
                }

                if applyDerivedMetrics(to: &records[i]) {
                    needsSave = true
                }
            }
            savedRecords = records
            if needsSave { saveRecords() }
        } catch {
            print("기록 로드 실패: \(error)")
        }
    }

    func deleteRecord(_ record: RunRecord) {
        savedRecords.removeAll { $0.id == record.id }
        saveRecords()
    }

    func mergeRemoteRecords(_ remoteRecords: [RunRecord]) {
        guard !remoteRecords.isEmpty else { return }

        var mergedById = Dictionary(uniqueKeysWithValues: savedRecords.map { ($0.id, $0) })
        var didChange = false

        for record in remoteRecords {
            guard mergedById[record.id] == nil else { continue }
            mergedById[record.id] = record
            didChange = true
        }

        guard didChange else { return }

        savedRecords = mergedById.values.sorted { $0.startDate > $1.startDate }
        saveRecords()
    }

    func clearAllSavedRecords() {
        resetSession()
        savedRecords.removeAll()
        do {
            if FileManager.default.fileExists(atPath: savePath.path) {
                try FileManager.default.removeItem(at: savePath)
            }
        } catch {
            print("기록 파일 삭제 실패: \(error)")
        }
    }
}

    private func sanitizedRoutePoints(_ routePoints: [RoutePoint]) -> [RoutePoint] {
        routePoints.filter {
            $0.speed == 0 || ($0.speed >= 0.834 && $0.speed <= RunMetricsAnalyzer.maxReliableSpeedMps)
        }
    }

    @discardableResult
    private func applyDerivedMetrics(to record: inout RunRecord) -> Bool {
        let analysis = RunMetricsAnalyzer.analyze(record: record)
        let caloriesChanged = record.caloriesEstimatedKcal == nil
            || abs((record.caloriesEstimatedKcal ?? 0) - analysis.caloriesEstimatedKcal) > 0.5
        let qualityChanged = record.dataQuality != analysis.dataQuality

        record.caloriesEstimatedKcal = analysis.caloriesEstimatedKcal
        record.dataQuality = analysis.dataQuality
        return caloriesChanged || qualityChanged
    }

@MainActor
final class VoiceGuideService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    private enum PaceAlertDirection: Hashable {
        case ahead
        case behind
    }

    private enum VoiceAlertKind: Hashable {
        case tooSlow
        case tooFast
        case backOnTarget
        case split
        case gap(PaceAlertDirection)
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var lastDistanceCheckpoint = 0
    private var lastPaceAlertDate: Date?
    private var lastPaceAlertDirection: PaceAlertDirection?
    private var lastAlertDates: [VoiceAlertKind: Date] = [:]
    private var sustainedDeviationStart: Date?
    private var sustainedDeviationDirection: PaceAlertDirection?
    private var wasOutsideTargetRange = false
    private var pendingMessages: [String] = []
    private let alertCooldownSeconds: TimeInterval = 30

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func reset() {
        lastDistanceCheckpoint = 0
        lastPaceAlertDate = nil
        lastPaceAlertDirection = nil
        lastAlertDates.removeAll()
        sustainedDeviationStart = nil
        sustainedDeviationDirection = nil
        wasOutsideTargetRange = false
        pendingMessages.removeAll()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        deactivateAudioSession()
    }

    func announceRunStart() {
        guard isEnabled else {
            reset()
            return
        }
        reset()
        if countdownAlertEnabled {
            speak(localizedMessage(
                korean: "3, 2, 1. 러닝을 시작합니다.",
                english: "Three, two, one. Starting the run."
            ))
        } else {
            speak(localizedMessage(
                korean: "러닝을 시작합니다.",
                english: "Starting the run."
            ))
        }
    }

    func announceRunFinish() {
        guard isEnabled else {
            reset()
            return
        }
        speak(localizedMessage(
            korean: "러닝을 종료합니다.",
            english: "Finishing the run."
        ))
        lastDistanceCheckpoint = 0
        lastPaceAlertDate = nil
        lastPaceAlertDirection = nil
        lastAlertDates.removeAll()
    }

    func announceGoalReached() {
        guard isEnabled else { return }
        speak(localizedMessage(
            korean: "설정한 목표를 달성했습니다.",
            english: "You've reached your goal."
        ))
    }

    func previewCurrentVoice() {
        speak(localizedMessage(
            korean: "음성 안내 미리듣기입니다. 이 기기에서 사용할 수 있는 가장 자연스러운 시스템 음성을 우선 사용합니다.",
            english: "This is a voice guide preview. I'll use the most natural system voice available on this device."
        ))
    }

    func handleDistanceUpdate(totalDistanceMeters: Double, currentPaceSecondsPerKm: Double) {
        guard isEnabled else { return }

        let interval = distanceIntervalKm
        guard interval > 0 else { return }

        let totalDistanceKm = totalDistanceMeters / 1000.0
        let checkpoint = Int(floor(totalDistanceKm / interval))
        guard checkpoint > lastDistanceCheckpoint else { return }

        lastDistanceCheckpoint = checkpoint
        let announcedDistance = Double(checkpoint) * interval
        let distanceText = spokenDistanceText(for: announcedDistance)
        guard canSpeak(.split, at: Date()) else { return }
        speak(distanceAnnouncement(distanceText: distanceText, paceSecondsPerKm: currentPaceSecondsPerKm))
    }

    func handlePaceGuidanceUpdate(currentPaceSecondsPerKm: Double, targetPaceSecondsPerKm: Double) {
        guard isEnabled,
              currentPaceSecondsPerKm > 0,
              currentPaceSecondsPerKm.isFinite,
              targetPaceSecondsPerKm > 0,
              targetPaceSecondsPerKm.isFinite else { return }

        let now = Date()
        let delta = currentPaceSecondsPerKm - targetPaceSecondsPerKm

        if abs(delta) <= 5 {
            sustainedDeviationStart = nil
            sustainedDeviationDirection = nil
            if wasOutsideTargetRange, canSpeak(.backOnTarget, at: now) {
                speak(localizedMessage(
                    korean: "좋아요. 이 페이스를 유지하세요.",
                    english: "Good. Hold this pace."
                ))
            }
            wasOutsideTargetRange = false
            return
        }

        guard abs(delta) > 10 else { return }

        let direction: PaceAlertDirection = delta > 0 ? .behind : .ahead
        if sustainedDeviationDirection != direction {
            sustainedDeviationDirection = direction
            sustainedDeviationStart = now
            return
        }

        guard let sustainedDeviationStart,
              now.timeIntervalSince(sustainedDeviationStart) >= 10 else { return }

        switch direction {
        case .behind:
            guard canSpeak(.tooSlow, at: now) else { return }
            wasOutsideTargetRange = true
            speak(localizedMessage(
                korean: "조금만 페이스를 올리세요.",
                english: "Pick it up slightly."
            ))
        case .ahead:
            guard canSpeak(.tooFast, at: now) else { return }
            wasOutsideTargetRange = true
            speak(localizedMessage(
                korean: "조금만 힘을 빼세요.",
                english: "Ease off slightly."
            ))
        }
    }

    func handleGapUpdate(gapMeters: Double) {
        guard isEnabled else { return }

        let threshold = paceAlertThresholdMeters
        guard threshold > 0, abs(gapMeters) >= threshold else { return }

        let direction: PaceAlertDirection = gapMeters >= 0 ? .ahead : .behind
        let now = Date()
        let shouldSpeak: Bool

        if direction != lastPaceAlertDirection {
            shouldSpeak = true
        } else if let lastPaceAlertDate {
            shouldSpeak = now.timeIntervalSince(lastPaceAlertDate) >= alertCooldownSeconds
        } else {
            shouldSpeak = true
        }

        guard shouldSpeak, canSpeak(.gap(direction), at: now) else { return }

        lastPaceAlertDate = now
        lastPaceAlertDirection = direction

        switch direction {
        case .ahead:
            speak(localizedMessage(
                korean: "조금만 힘을 빼세요.",
                english: "Ease off slightly."
            ))
        case .behind:
            speak(localizedMessage(
                korean: "조금만 페이스를 올리세요.",
                english: "Pick it up slightly."
            ))
        }
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "voiceGuide")
    }

    private var distanceIntervalKm: Double {
        UserDefaults.standard.double(forKey: "voiceDistanceInterval")
    }

    private var paceAlertThresholdMeters: Double {
        let stored = UserDefaults.standard.double(forKey: "voicePaceAlertThreshold")
        return stored > 0 ? stored : 15.0
    }

    private var countdownAlertEnabled: Bool {
        if UserDefaults.standard.object(forKey: "voiceCountdownAlert") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "voiceCountdownAlert")
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true)
    }

    private func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func canSpeak(_ kind: VoiceAlertKind, at now: Date) -> Bool {
        if let lastDate = lastAlertDates[kind], now.timeIntervalSince(lastDate) < alertCooldownSeconds {
            return false
        }
        lastAlertDates[kind] = now
        return true
    }

    private func speak(_ message: String) {
        guard !message.isEmpty else { return }

        if synthesizer.isSpeaking {
            if pendingMessages.last != message, pendingMessages.count < 3 {
                pendingMessages.append(message)
            }
            return
        }

        speakNow(message)
    }

    private func speakNow(_ message: String) {
        configureAudioSession()

        let utterance = AVSpeechUtterance(string: message)
        let voice = preferredVoice()
        utterance.voice = voice
        utterance.rate = speechRate(for: voice?.language ?? preferredSpeechLanguageCodes.first ?? "ko-KR")
        utterance.pitchMultiplier = 0.98
        utterance.volume = 0.9
        synthesizer.speak(utterance)
    }

    private func handleSpeechFinished() {
        if pendingMessages.isEmpty {
            deactivateAudioSession()
            return
        }

        let nextMessage = pendingMessages.removeFirst()
        speakNow(nextMessage)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.handleSpeechFinished()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.handleSpeechFinished()
        }
    }

    private func distanceAnnouncement(distanceText: String, paceSecondsPerKm: Double) -> String {
        let paceText = spokenPaceText(secondsPerKm: paceSecondsPerKm)
        if usesEnglishSpeech {
            return "\(distanceText) completed. Current pace is \(paceText)."
        }
        return "\(distanceText) 지났어요. 현재 페이스는 \(paceText)입니다."
    }

    private func localizedMessage(korean: String, english: String) -> String {
        usesEnglishSpeech ? english : korean
    }

    private func spokenDistanceText(for distanceKm: Double) -> String {
        let roundedDistance = distanceKm.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(distanceKm))
            : String(format: "%.1f", distanceKm)

        if usesEnglishSpeech {
            return "\(roundedDistance) kilometer\(roundedDistance == "1" ? "" : "s")"
        }
        return "\(roundedDistance)킬로미터"
    }

    private func spokenPaceText(secondsPerKm: Double) -> String {
        guard secondsPerKm > 0, secondsPerKm.isFinite else {
            return localizedMessage(korean: "측정 중", english: "still measuring")
        }

        let minutes = Int(secondsPerKm) / 60
        let seconds = Int(secondsPerKm) % 60
        if usesEnglishSpeech {
            return "\(minutes) minute\(minutes == 1 ? "" : "s") \(seconds) second\(seconds == 1 ? "" : "s") per kilometer"
        }
        return "킬로미터당 \(minutes)분 \(seconds)초"
    }

    private var usesEnglishSpeech: Bool {
        preferredSpeechLanguageCodes.first?.hasPrefix("en") == true
    }

    private var preferredSpeechLanguageCodes: [String] {
        switch AppLanguage.current {
        case .korean:
            return ["ko-KR", "ko"]
        case .english:
            return preferredEnglishLanguageCodes
        case .system:
            return AppLanguage.current.isEnglish ? preferredEnglishLanguageCodes : ["ko-KR", "ko"]
        }
    }

    private var preferredEnglishLanguageCodes: [String] {
        let preferred = Locale.preferredLanguages
            .map(normalizedLanguageCode)
            .filter { $0.hasPrefix("en") }
        let merged = preferred + ["en-US", "en-GB", "en"]
        return Array(NSOrderedSet(array: merged)) as? [String] ?? ["en-US", "en-GB", "en"]
    }

    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        let candidates = preferredSpeechLanguageCodes
        let bestVoice = AVSpeechSynthesisVoice.speechVoices()
            .map { voice in (voice, voiceScore(for: voice, candidates: candidates)) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }
            .map { $0.0 }

        return bestVoice ?? AVSpeechSynthesisVoice(language: candidates.first ?? "ko-KR")
    }

    private func voiceScore(for voice: AVSpeechSynthesisVoice, candidates: [String]) -> Int {
        let voiceLanguage = normalizedLanguageCode(voice.language)
        var languageMatchScore = 0

        for (index, candidate) in candidates.enumerated() {
            let bonus = max(0, 24 - (index * 4))
            let normalizedCandidate = normalizedLanguageCode(candidate)
            let candidatePrefix = String(normalizedCandidate.prefix(2))

            if voiceLanguage == normalizedCandidate {
                languageMatchScore = 100 + bonus
                break
            }

            if voiceLanguage.hasPrefix(candidatePrefix) {
                languageMatchScore = 70 + bonus
                break
            }
        }

        guard languageMatchScore > 0 else { return 0 }

        var score = languageMatchScore + qualityScore(for: voice.quality)

        if voice.name.localizedCaseInsensitiveContains("Siri") {
            score += 8
        }

        return score
    }

    private func qualityScore(for quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium:
            return 30
        case .enhanced:
            return 20
        default:
            return 10
        }
    }

    private func speechRate(for languageCode: String) -> Float {
        normalizedLanguageCode(languageCode).hasPrefix("en") ? 0.47 : 0.43
    }

    private func normalizedLanguageCode(_ code: String) -> String {
        code.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}
