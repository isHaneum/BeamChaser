import Foundation
import WatchConnectivity
import SwiftUI

/// Watch 측 WatchConnectivity 관리자
/// - iPhone에서 오는 러닝 스냅샷을 수신하여 Published 상태로 변환
/// - Watch UI의 각 뷰가 이 객체를 공유해서 읽음
@MainActor
final class WatchSessionManager: NSObject, ObservableObject {

    // MARK: - Published 러닝 상태

    @Published var snapshot = WatchRunSnapshot()

    // iPhone 연결 여부
    @Published var isPhoneReachable = false

    // MARK: - Init

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Watch → iPhone 명령 전송

    func send(_ command: WCCommand, value: Int = 0) {
        guard WCSession.default.isReachable else { return }
        let msg: [String: Any] = [
            WCMessageKey.command:      command.rawValue,
            WCMessageKey.commandValue: value
        ]
        WCSession.default.sendMessage(msg, replyHandler: nil, errorHandler: nil)
    }

    // MARK: - 편의 API

    func pauseRun()            { send(.pauseRun) }
    func resumeRun()           { send(.resumeRun) }
    func finishRun()           { send(.finishRun) }
    func adjustServo(_ delta: Int) { send(.adjustServo, value: delta) }
    func setDayMode(_ on: Bool) { send(.setDayMode, value: on ? 1 : 0) }
    func requestSync()         { send(.requestSync) }

    // MARK: - 상태 계산 프로퍼티

    var isRunning: Bool  { snapshot.runState == "running" }
    var isPaused: Bool   { snapshot.runState == "paused" }
    var isIdle: Bool     { snapshot.runState == "idle" }
    var isFinished: Bool { snapshot.runState == "finished" }

    var paceStatusColor: Color {
        switch snapshot.paceStatus {
        case "ahead":  return Color(red: 0.2, green: 0.85, blue: 0.4)  // 초록
        case "behind": return Color(red: 1.0, green: 0.2,  blue: 0.2)  // 빨강
        default:       return Color(red: 1.0, green: 0.55, blue: 0.0)  // 오렌지
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            isPhoneReachable = session.isReachable
            // 활성화 즉시 최신 상태 요청
            if state == .activated {
                send(.requestSync)
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isPhoneReachable = session.isReachable
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            snapshot = WatchRunSnapshot(from: message)
        }
    }
}
