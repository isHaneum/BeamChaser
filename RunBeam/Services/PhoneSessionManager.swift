import Foundation
import WatchConnectivity
import Combine

/// iPhone 측 WatchConnectivity 관리자
/// - 러닝 상태를 500ms마다 Watch로 푸시
/// - Watch에서 오는 제어 명령을 RunSessionManager / BLEService로 라우팅
@MainActor
final class PhoneSessionManager: NSObject, ObservableObject {

    // MARK: - Singletons (주입된 서비스)
    weak var runSession: RunSessionManager?
    weak var bleService: BLEService?
    weak var locationService: LocationService?

    // MARK: - Published
    @Published var isWatchReachable = false

    // MARK: - Private
    private let session = WCSession.default
    private var syncTimer: Timer?
    private var lastHeartRate: Int = 0

    // MARK: - Init
    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - 러닝 시작 시 동기화 타이머 켜기

    func startSync() {
        stopSync()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pushSnapshot() }
        }
    }

    func stopSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - 스냅샷 빌드 & 전송

    private func pushSnapshot() {
        guard isWatchReachable else { return }
        guard let rs = runSession, let ls = locationService, let ble = bleService else { return }

        var snap = WatchRunSnapshot()
        snap.runState            = stateString(rs.runState)
        snap.gapMeters           = rs.paceMaker.gapMeters
        snap.paceStatus          = paceStatusString(rs.paceMaker.paceStatus)
        snap.currentPaceSecondsPerKm = ls.currentPaceSecondsPerKm
        snap.targetPaceSecondsPerKm  = rs.paceMaker.target?.totalSecondsPerKm ?? 0
        snap.elapsedSeconds      = rs.elapsedSeconds
        snap.distanceMeters      = ls.totalDistanceMeters
        snap.heartRate           = lastHeartRate
        snap.gpsAccuracy         = ls.currentLocation?.horizontalAccuracy ?? -1
        snap.deviceBattery       = ble.deviceStatus?.batteryPercent ?? 0
        snap.deviceConnected     = ble.isConnected
        snap.servoAngle          = ble.servoAngle

        session.sendMessage(snap.asDictionary, replyHandler: nil, errorHandler: nil)
    }

    // MARK: - Watch 명령 처리

    private func handleCommand(_ dict: [String: Any]) {
        guard let cmdStr = dict[WCMessageKey.command] as? String,
              let cmd = WCCommand(rawValue: cmdStr) else { return }
        let value = dict[WCMessageKey.commandValue] as? Int ?? 0

        switch cmd {
        case .pauseRun:
            runSession?.pauseRun()
        case .resumeRun:
            runSession?.resumeRun()
        case .startRun:
            // value = targetPaceSeconds (Int)
            let paceSeconds = Double(value)
            if paceSeconds > 0, let rs = runSession {
                let min = Int(paceSeconds) / 60
                let sec = Int(paceSeconds) % 60
                let target = PaceTarget(minutesPerKm: min, secondsPerKm: sec)
                rs.startRun(target: target)
            }
        case .finishRun:
            // finishRun은 route/distance를 locationService에서 가져옴
            if let ls = locationService, let rs = runSession {
                rs.finishRun(routePoints: ls.routePoints, totalDistance: ls.totalDistanceMeters)
            }
        case .adjustServo:
            // value: delta (-5 ~ +5)
            if let ble = bleService {
                let newAngle = max(60, min(110, ble.servoAngle + value))
                ble.setServoAngle(newAngle)
            }
        case .setDayMode:
            bleService?.setDayMode(value == 1)
        case .requestSync:
            pushSnapshot()
        }
    }

    // MARK: - HealthKit 심박수 수신 (RunSessionManager 콜백)
    func updateHeartRate(_ bpm: Int) {
        lastHeartRate = bpm
    }

    // MARK: - 헬퍼

    private func stateString(_ state: RunState) -> String {
        switch state {
        case .idle:           return "idle"
        case .countdown:      return "running"
        case .running:        return "running"
        case .paused:         return "paused"
        case .finished:       return "finished"
        }
    }

    private func paceStatusString(_ status: PaceMakerEngine.PaceStatus) -> String {
        switch status {
        case .ahead:    return "ahead"
        case .onPace:   return "onPace"
        case .behind:   return "behind"
        }
    }
}

// MARK: - WCSessionDelegate

extension PhoneSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            isWatchReachable = session.isReachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isWatchReachable = session.isReachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            handleCommand(message)
        }
    }
}
