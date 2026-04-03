import Foundation

// MARK: - Watch <-> iPhone WatchConnectivity 메시지 프로토콜

/// iPhone → Watch 방향 메시지 키
enum WCMessageKey {
    // iPhone → Watch (러닝 상태 동기화)
    static let runState          = "runState"         // String: "idle" | "running" | "paused" | "finished"
    static let gapMeters         = "gapMeters"        // Double: 레이저 갭 (m)
    static let paceStatus        = "paceStatus"       // String: "ahead" | "onPace" | "behind"
    static let currentPace       = "currentPace"      // Double: 현재 페이스 (초/km)
    static let targetPace        = "targetPace"       // Double: 목표 페이스 (초/km)
    static let elapsedSeconds    = "elapsedSeconds"   // Double: 경과 시간
    static let distanceMeters    = "distanceMeters"   // Double: 달린 거리 (m)
    static let heartRate         = "heartRate"        // Int: 심박수 (bpm)
    static let gpsAccuracy       = "gpsAccuracy"      // Double: GPS 수평 정확도 (m)
    static let deviceBattery     = "deviceBattery"    // Int: 레이저 장치 배터리 (%)
    static let deviceConnected   = "deviceConnected"  // Bool: BLE 연결 여부
    static let servoAngle         = "servoAngle"        // Int: 현재 서보 각도 (60~110)

    // Watch → iPhone 방향 (제어 명령)
    static let command           = "command"          // String: WCCommand rawValue
    static let commandValue      = "commandValue"     // Int: 명령 파라미터
}

/// Watch → iPhone 제어 명령
enum WCCommand: String {
    case pauseRun        // 러닝 일시정지
    case resumeRun       // 러닝 재개
    case finishRun       // 러닝 종료
    case startRun        // 워치에서 러닝 시작 (commandValue = targetPaceSeconds)
    case adjustServo     // 서보 각도 조절 (+1 or -1, commandValue에 delta 포함)
    case setDayMode      // 낮 점멸 모드 (commandValue: 0 or 1)
    case requestSync     // 전체 상태 즉시 동기화 요청
}

// MARK: - Watch용 러닝 상태 스냅샷 (UserDefaults 공유 없이 WC로만 전달)

struct WatchRunSnapshot {
    var runState: String = "idle"
    var gapMeters: Double = 0
    var paceStatus: String = "onPace"
    var currentPaceSecondsPerKm: Double = 0
    var targetPaceSecondsPerKm: Double = 0
    var elapsedSeconds: Double = 0
    var distanceMeters: Double = 0
    var heartRate: Int = 0
    var gpsAccuracy: Double = -1
    var deviceBattery: Int = 0
    var deviceConnected: Bool = false
    var servoAngle: Int = 85

    /// WatchConnectivity 딕셔너리로 변환
    var asDictionary: [String: Any] {
        [
            WCMessageKey.runState:       runState,
            WCMessageKey.gapMeters:      gapMeters,
            WCMessageKey.paceStatus:     paceStatus,
            WCMessageKey.currentPace:    currentPaceSecondsPerKm,
            WCMessageKey.targetPace:     targetPaceSecondsPerKm,
            WCMessageKey.elapsedSeconds: elapsedSeconds,
            WCMessageKey.distanceMeters: distanceMeters,
            WCMessageKey.heartRate:      heartRate,
            WCMessageKey.gpsAccuracy:    gpsAccuracy,
            WCMessageKey.deviceBattery:  deviceBattery,
            WCMessageKey.deviceConnected: deviceConnected,
            WCMessageKey.servoAngle:      servoAngle,
        ]
    }

    /// WatchConnectivity 딕셔너리에서 복원
    init(from dict: [String: Any]) {
        runState                  = dict[WCMessageKey.runState]       as? String ?? "idle"
        gapMeters                 = dict[WCMessageKey.gapMeters]      as? Double ?? 0
        paceStatus                = dict[WCMessageKey.paceStatus]     as? String ?? "onPace"
        currentPaceSecondsPerKm   = dict[WCMessageKey.currentPace]    as? Double ?? 0
        targetPaceSecondsPerKm    = dict[WCMessageKey.targetPace]     as? Double ?? 0
        elapsedSeconds            = dict[WCMessageKey.elapsedSeconds] as? Double ?? 0
        distanceMeters            = dict[WCMessageKey.distanceMeters] as? Double ?? 0
        heartRate                 = dict[WCMessageKey.heartRate]       as? Int    ?? 0
        gpsAccuracy               = dict[WCMessageKey.gpsAccuracy]    as? Double ?? -1
        deviceBattery             = dict[WCMessageKey.deviceBattery]  as? Int    ?? 0
        deviceConnected           = dict[WCMessageKey.deviceConnected] as? Bool  ?? false
        servoAngle                = dict[WCMessageKey.servoAngle]      as? Int   ?? 85
    }

    init() {}
}

// MARK: - 페이스 포맷 유틸 (Watch/iPhone 공용)

enum PaceFormatter {
    static func format(_ secondsPerKm: Double) -> String {
        guard secondsPerKm > 0, secondsPerKm.isFinite, secondsPerKm < 3600 else { return "--'--\"" }
        let minutes = Int(secondsPerKm) / 60
        let seconds = Int(secondsPerKm) % 60
        return String(format: "%d'%02d\"", minutes, seconds)
    }

    static func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
