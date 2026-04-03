import WatchKit

/// Watch 햅틱 패턴 정의
/// - 스펙: 뒤처짐 = 짧게 2회(탁!탁!), 앞섬 = 길게 1회(우웅-), 페이스 달성 = 두근-두근-
enum HapticPattern {
    case behind      // 탁!탁!  - 뒤처짐 경고
    case ahead       // 우웅-   - 앞서감
    case milestone   // 두근-두근- - 페이스 달성

    func play() {
        let device = WKInterfaceDevice.current()
        switch self {
        case .behind:
            device.play(.click)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                device.play(.click)
            }
        case .ahead:
            device.play(.success)
        case .milestone:
            device.play(.notification)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                device.play(.notification)
            }
        }
    }
}

/// Haptic 중복 발생 방지용 레이트 리미터
final class HapticEngine {
    static let shared = HapticEngine()
    private var lastFired: [String: Date] = [:]
    private let minInterval: TimeInterval = 2.0

    private init() {}

    func trigger(_ pattern: HapticPattern) {
        let key = "\(pattern)"
        let now = Date()
        if let last = lastFired[key], now.timeIntervalSince(last) < minInterval { return }
        lastFired[key] = now
        pattern.play()
    }
}
