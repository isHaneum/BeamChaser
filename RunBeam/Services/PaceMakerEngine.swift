import Foundation
import Combine

/// 페이스메이커 엔진 — 목표 페이스 대비 현재 상태 계산
@MainActor
final class PaceMakerEngine: ObservableObject {

    // MARK: - Published State

    /// 목표 대비 갭 (미터). 양수 = 앞서감, 음수 = 뒤처짐
    @Published var gapMeters: Double = 0

    /// 목표 대비 갭 (초). 양수 = 앞서감, 음수 = 뒤처짐
    @Published var gapSeconds: Double = 0

    /// 가상 주자(레이저)가 현재까지 달렸어야 할 거리
    @Published var laserDistanceMeters: Double = 0

    /// 페이스 상태
    @Published var paceStatus: PaceStatus = .onPace

    // MARK: - Properties

    private(set) var target: PaceTarget?
    private var startTime: Date?

    enum PaceStatus {
        case ahead      // 목표보다 빠름
        case onPace     // 목표 근접 (±10m)
        case behind     // 목표보다 느림

        var label: String {
            switch self {
            case .ahead: return "앞서는 중"
            case .onPace: return "페이스 유지"
            case .behind: return "뒤처지는 중"
            }
        }

        var color: String {
            switch self {
            case .ahead: return "green"
            case .onPace: return "orange"
            case .behind: return "red"
            }
        }

        var icon: String {
            switch self {
            case .ahead: return "arrow.up.circle.fill"
            case .onPace: return "equal.circle.fill"
            case .behind: return "arrow.down.circle.fill"
            }
        }
    }

    // MARK: - Public API

    func start(target: PaceTarget) {
        self.target = target
        self.startTime = Date()
        reset()
    }

    func stop() {
        startTime = nil
    }

    func reset() {
        gapMeters = 0
        gapSeconds = 0
        laserDistanceMeters = 0
        paceStatus = .onPace
    }

    /// 매 위치 업데이트마다 호출 — 현재 실제 거리와 비교하여 갭 계산
    func update(actualDistanceMeters: Double, elapsedSeconds: TimeInterval) {
        guard let target = target, target.totalSecondsPerKm > 0 else { return }

        // 목표 페이스 기준으로 이 시간 동안 달렸어야 할 거리
        let targetMetersPerSecond = 1000.0 / target.totalSecondsPerKm
        laserDistanceMeters = elapsedSeconds * targetMetersPerSecond

        // 갭 계산
        gapMeters = actualDistanceMeters - laserDistanceMeters

        // 시간 갭 (현재 거리를 목표 페이스로 달리는데 필요한 시간과 실제 시간 차이)
        let expectedSecondsForActualDistance = actualDistanceMeters / targetMetersPerSecond
        gapSeconds = expectedSecondsForActualDistance - elapsedSeconds

        // 상태 판정
        let threshold: Double = 10 // 10m 이내면 onPace
        if gapMeters > threshold {
            paceStatus = .ahead
        } else if gapMeters < -threshold {
            paceStatus = .behind
        } else {
            paceStatus = .onPace
        }
    }

    /// 갭을 읽기 좋은 문자열로 변환
    var formattedGap: String {
        let absGap = abs(gapMeters)
        let direction = gapMeters >= 0 ? "+" : "-"
        return String(format: "%@%.0fm", direction, absGap)
    }

    var formattedTimeGap: String {
        let absGap = abs(gapSeconds)
        let direction = gapSeconds >= 0 ? "+" : "-"
        if absGap < 60 {
            return String(format: "%@%.0f초", direction, absGap)
        }
        let min = Int(absGap) / 60
        let sec = Int(absGap) % 60
        return String(format: "%@%d분 %02d초", direction, min, sec)
    }
}
