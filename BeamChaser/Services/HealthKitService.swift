import Foundation
import HealthKit
import CoreLocation
import Combine

/// HealthKit 서비스 — Apple 건강 앱 & 운동 앱 연동
@MainActor
final class HealthKitService: ObservableObject {

    // MARK: - Published State

    @Published var isAuthorized = false
    @Published var authorizationError: String?
    @Published var currentHeartRate: Double = 0     // bpm
    @Published var activeCalories: Double = 0       // kcal
    @Published var currentRunningPace: Double = 0   // seconds per km (워치/폰 운동 앱에서)
    @Published var isWorkoutActive = false
    @Published var userHeightCm: Int?  // 건강 앱에서 가져온 키

    // MARK: - Private

    private let healthStore = HKHealthStore()
    private var workoutBuilder: HKWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var runningSpeedQuery: HKAnchoredObjectQuery?
    private var workoutStartDate: Date?

    init() {
        refreshAuthorizationStatus()
    }

    // MARK: - HealthKit 타입

    private let typesToShare: Set<HKSampleType> = [
        HKQuantityType.workoutType(),
        HKSeriesType.workoutRoute(),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned),
    ]

    private let typesToRead: Set<HKObjectType> = [
        HKQuantityType(.heartRate),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.runningSpeed),
        HKQuantityType(.height),
        HKObjectType.workoutType(),
    ]

    // MARK: - 가용성 확인

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - 권한 요청

    func refreshAuthorizationStatus() {
        guard Self.isAvailable else {
            isAuthorized = false
            authorizationError = "이 기기에서는 건강 데이터를 사용할 수 없습니다."
            return
        }

        let workoutStatus = healthStore.authorizationStatus(for: HKQuantityType.workoutType())
        isAuthorized = workoutStatus == .sharingAuthorized

        if workoutStatus == .sharingAuthorized {
            authorizationError = nil
            Task {
                await fetchHeight()
            }
        } else if workoutStatus == .sharingDenied {
            authorizationError = "건강 데이터 권한이 꺼져 있어 운동 기록이 건강 앱과 동기화되지 않아요."
        } else {
            authorizationError = nil
        }
    }

    func requestAuthorization() async {
        guard Self.isAvailable else {
            authorizationError = "이 기기에서는 건강 데이터를 사용할 수 없습니다."
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            refreshAuthorizationStatus()
            if isAuthorized {
                authorizationError = nil
                await fetchHeight()
            } else {
                authorizationError = "건강 앱에서 RunBeam의 운동 기록 권한을 켜야 거리, 칼로리, 심박수 연동이 정상 동작합니다."
            }
        } catch {
            // HealthKit entitlement 없거나 시스템 권한이 막힌 경우
            authorizationError = "건강 권한 요청에 실패했어요. 앱의 HealthKit capability와 iPhone 건강 권한 설정을 확인해주세요."
            isAuthorized = false
            print("HealthKit 권한 요청 불가 (entitlement 미설정): \(error.localizedDescription)")
        }
    }

    // MARK: - 키 정보 가져오기

    func fetchHeight() async {
        let heightType = HKQuantityType(.height)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { [weak self] _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume()
                    return
                }
                let cm = Int(sample.quantity.doubleValue(for: .meterUnit(with: .centi)))
                Task { @MainActor [weak self] in
                    self?.userHeightCm = cm
                }
                continuation.resume()
            }
            healthStore.execute(query)
        }
    }

    // MARK: - 운동 세션 시작

    func startWorkout() async {
        guard Self.isAvailable, isAuthorized else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = .outdoor

        do {
            let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())
            try await builder.beginCollection(at: Date())

            let route = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())

            workoutBuilder = builder
            routeBuilder = route
            workoutStartDate = Date()
            isWorkoutActive = true
            activeCalories = 0
            hasRouteData = false

            startHeartRateQuery()
            startRunningSpeedQuery()
        } catch {
            print("운동 세션 시작 실패: \(error)")
        }
    }

    // MARK: - 위치 데이터 추가 (LocationService 연동)

    func addRouteData(_ locations: [CLLocation]) {
        guard isWorkoutActive, let routeBuilder = routeBuilder else { return }

        let filtered = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy < 50 }
        guard !filtered.isEmpty else { return }

        hasRouteData = true
        routeBuilder.insertRouteData(filtered) { _, error in
            if let error = error {
                print("경로 데이터 추가 실패: \(error)")
            }
        }
    }

    // MARK: - 운동 종료 & 저장

    private var hasRouteData = false

    func endWorkout(totalDistance: Double, totalDuration: TimeInterval) async {
        guard isWorkoutActive, let builder = workoutBuilder else {
            // 이미 종료되었거나 시작되지 않은 경우 — 상태만 정리
            isWorkoutActive = false
            workoutBuilder = nil
            routeBuilder = nil
            hasRouteData = false
            return
        }

        // 즉시 비활성화하여 addRouteData 재진입 차단
        isWorkoutActive = false

        // 로컬 참조 확보 후 프로퍼티 정리 (addRouteData와의 경쟁 방지)
        let localRouteBuilder = routeBuilder
        let localHasRouteData = hasRouteData
        workoutBuilder = nil
        routeBuilder = nil

        stopHeartRateQuery()
        stopRunningSpeedQuery()

        do {
            // 거리 샘플 추가
            let distanceType = HKQuantityType(.distanceWalkingRunning)
            let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: totalDistance)
            let now = Date()
            let startDate = workoutStartDate ?? now.addingTimeInterval(-totalDuration)

            let distanceSample = HKQuantitySample(
                type: distanceType,
                quantity: distanceQuantity,
                start: startDate,
                end: now
            )
            try await builder.addSamples([distanceSample])

            // 칼로리 샘플 추가 (추정)
            if activeCalories > 0 {
                let calorieType = HKQuantityType(.activeEnergyBurned)
                let calorieQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: activeCalories)
                let calorieSample = HKQuantitySample(
                    type: calorieType,
                    quantity: calorieQuantity,
                    start: startDate,
                    end: now
                )
                try await builder.addSamples([calorieSample])
            }

            // 운동 종료
            try await builder.endCollection(at: now)

            // 운동 저장
            let workout = try await builder.finishWorkout()

            // 경로 저장 (운동에 연결) — 경로 데이터가 있을 때만
            if let routeBuilder = localRouteBuilder, let workout = workout, localHasRouteData {
                try await routeBuilder.finishRoute(with: workout, metadata: nil)
            }

            workoutStartDate = nil
            hasRouteData = false
        } catch {
            print("운동 저장 실패: \(error)")
            // 실패 시에도 상태 정리
            workoutStartDate = nil
            hasRouteData = false
        }
    }

    // MARK: - 운동 취소

    func discardWorkout() async {
        stopHeartRateQuery()
        stopRunningSpeedQuery()

        if let builder = workoutBuilder {
            builder.discardWorkout()
        }

        isWorkoutActive = false
        workoutBuilder = nil
        routeBuilder = nil
        workoutStartDate = nil
        activeCalories = 0
        currentHeartRate = 0
        currentRunningPace = 0
        hasRouteData = false
    }

    // MARK: - 심박수 실시간 모니터링

    private func startHeartRateQuery() {
        let heartRateType = HKQuantityType(.heartRate)

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: HKQuery.predicateForSamples(withStart: Date(), end: nil),
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.handleHeartRateSamples(samples)
        }

        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.handleHeartRateSamples(samples)
        }

        healthStore.execute(query)
        heartRateQuery = query
    }

    private func stopHeartRateQuery() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
    }

    /// nonisolated 래퍼 — HealthKit 콜백(nonisolated)에서 MainActor로 전달
    nonisolated private func handleHeartRateSamples(_ samples: [HKSample]?) {
        guard let samples = samples as? [HKQuantitySample], let latest = samples.last else { return }
        let bpm = latest.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))

        Task { @MainActor [weak self] in
            self?.currentHeartRate = bpm
            self?.estimateCalories(heartRate: bpm)
        }
    }

    // MARK: - 러닝 속도(페이스) 실시간 모니터링
    // Apple Watch 또는 iPhone 운동 앱에서 측정되는 runningSpeed 읽기

    private func startRunningSpeedQuery() {
        let speedType = HKQuantityType(.runningSpeed)

        let query = HKAnchoredObjectQuery(
            type: speedType,
            predicate: HKQuery.predicateForSamples(withStart: Date(), end: nil),
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.handleRunningSpeedSamples(samples)
        }

        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.handleRunningSpeedSamples(samples)
        }

        healthStore.execute(query)
        runningSpeedQuery = query
    }

    private func stopRunningSpeedQuery() {
        if let query = runningSpeedQuery {
            healthStore.stop(query)
            runningSpeedQuery = nil
        }
    }

    /// nonisolated 래퍼 — HealthKit 콜백에서 MainActor로 전달
    nonisolated private func handleRunningSpeedSamples(_ samples: [HKSample]?) {
        guard let samples = samples as? [HKQuantitySample], let latest = samples.last else { return }
        // runningSpeed 단위: m/s
        let speedMPS = latest.quantity.doubleValue(for: HKUnit.meter().unitDivided(by: .second()))

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if speedMPS > 0.3 {
                // m/s → seconds per km
                self.currentRunningPace = 1000.0 / speedMPS
            }
        }
    }

    // MARK: - 칼로리 추정 (심박수 기반)

    private var lastCalorieUpdate: Date?

    private func estimateCalories(heartRate: Double) {
        let now = Date()
        defer { lastCalorieUpdate = now }

        guard let lastUpdate = lastCalorieUpdate else { return }

        let intervalMinutes = now.timeIntervalSince(lastUpdate) / 60.0
        guard intervalMinutes > 0, intervalMinutes < 5 else { return }

        // 간단한 칼로리 추정 공식 (러닝 기준)
        let calPerMinute = (0.6309 * heartRate - 55.0969) / 4.184
        if calPerMinute > 0 {
            activeCalories += calPerMinute * intervalMinutes
        }
    }
}
