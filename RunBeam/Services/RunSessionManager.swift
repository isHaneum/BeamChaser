import Foundation
import Combine

/// 러닝 세션 매니저 — 전체 러닝 라이프사이클 관리
@MainActor
final class RunSessionManager: ObservableObject {

    // MARK: - Published State

    @Published var runState: RunState = .idle
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var currentRecord: RunRecord?
    @Published var savedRecords: [RunRecord] = []

    // MARK: - Sub-Engines

    let paceMaker = PaceMakerEngine()
    let healthKit = HealthKitService()

    // MARK: - Private

    private var timer: Timer?
    private var runStartTime: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauseStartTime: Date?

    // 저장 경로
    private var savePath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("run_records.json")
    }

    // MARK: - Init

    init() {
        loadRecords()
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
        runStartTime = Date()
        pausedDuration = 0
        elapsedSeconds = 0

        if let target = target {
            paceMaker.start(target: target)
        }

        // HealthKit 운동 세션 시작
        Task {
            await healthKit.startWorkout()
        }

        runState = .running
        startTimer()
    }

    func pauseRun() {
        guard runState == .running else { return }
        runState = .paused
        pauseStartTime = Date()
        stopTimer()
    }

    func resumeRun() {
        guard runState == .paused, let pauseStart = pauseStartTime else { return }
        pausedDuration += Date().timeIntervalSince(pauseStart)
        pauseStartTime = nil
        runState = .running
        startTimer()
    }

    func finishRun(routePoints: [RoutePoint], totalDistance: Double) {
        // 중복 호출 방지
        guard runState == .running || runState == .paused else { return }

        stopTimer()
        paceMaker.stop()

        // runState를 먼저 .finished로 설정하여 onChange 핸들러의 재진입 방지
        runState = .finished

        if var record = currentRecord {
            record.endDate = Date()
            record.routePoints = routePoints
            record.totalDistanceMeters = totalDistance
            record.elapsedSeconds = elapsedSeconds
            currentRecord = record

            // 최소 거리 이상 달렸을 때만 저장
            #if targetEnvironment(simulator)
            let minDistance: Double = 10  // 시뮬레이터에서는 10m
            #else
            let minDistance: Double = 100
            #endif
            if totalDistance >= minDistance {
                savedRecords.insert(record, at: 0)
                saveRecords()

                // HealthKit에 운동 저장
                Task { [weak self] in
                    await self?.healthKit.endWorkout(
                        totalDistance: totalDistance,
                        totalDuration: self?.elapsedSeconds ?? 0
                    )
                }
            } else {
                Task { [weak self] in await self?.healthKit.discardWorkout() }
            }
        } else {
            // currentRecord가 없으면 HealthKit 운동도 폐기
            Task { [weak self] in await self?.healthKit.discardWorkout() }
        }
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
        paceMaker.update(actualDistanceMeters: distance, elapsedSeconds: elapsedSeconds)

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
            case .none:
                break
            }
        }
    }

    @Published var goalReached = false

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

    // MARK: - 기록 저장/로드

    private func saveRecords() {
        do {
            let data = try JSONEncoder().encode(savedRecords)
            try data.write(to: savePath, options: .atomic)
        } catch {
            print("기록 저장 실패: \(error)")
        }
    }

    private func loadRecords() {
        guard FileManager.default.fileExists(atPath: savePath.path) else { return }
        do {
            let data = try Data(contentsOf: savePath)
            savedRecords = try JSONDecoder().decode([RunRecord].self, from: data)
        } catch {
            print("기록 로드 실패: \(error)")
        }
    }

    func deleteRecord(_ record: RunRecord) {
        savedRecords.removeAll { $0.id == record.id }
        saveRecords()
    }
}
