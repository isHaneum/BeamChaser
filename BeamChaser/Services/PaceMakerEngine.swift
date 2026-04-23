import Foundation
import Combine

/// 페이스메이커 엔진 — 목표 페이스 대비 현재 상태 계산 (적응형 로직 포함)
@MainActor
final class PaceMakerEngine: ObservableObject {

    // MARK: - Published State

    /// 목표 대비 갭 (미터). 양수 = 앞서감, 음수 = 뒤처짐
    @Published var gapMeters: Double = 0
    /// 목표 대비 갭 (초). 양수 = 앞서감, 음수 = 뒤처짐
    @Published var gapSeconds: Double = 0
    /// 가상 주자(레이저)가 현재까지 달린 총 거리
    @Published var laserDistanceMeters: Double = 0
    /// 페이스 상태
    @Published var paceStatus: PaceStatus = .onPace
    
    /// 지능형 적응 모드 활성화 여부
    @Published var isAdaptiveMode: Bool = true
    /// 현재 적용 중인 유효 목표 페이스 (초/km)
    @Published var effectivePaceSecondsPerKm: Double = 0
    /// 현재 적응 상태
    @Published var adaptiveState: AdaptiveState = .steady

    // MARK: - Properties

    private(set) var target: PaceTarget?
    private var lastUpdateTime: Date?

    enum PaceStatus {
        case ahead, onPace, behind
        var label: String {
            switch self {
            case .ahead: return AppLanguage.current.text("앞서는 중", "Ahead")
            case .onPace: return AppLanguage.current.text("페이스 유지", "On Pace")
            case .behind: return AppLanguage.current.text("뒤처지는 중", "Behind")
            }
        }
        var color: String {
            switch self {
            case .ahead: return "blue"
            case .onPace: return "green"
            case .behind: return "red"
            }
        }
        var icon: String {
            switch self {
            case .ahead: return "hare.fill"
            case .onPace: return "checkmark.circle.fill"
            case .behind: return "tortoise.fill"
            }
        }
    }
    
    enum AdaptiveState: String {
        case steady = "정속"
        case waiting = "기다림"
        case recovering = "복구중"
    }

    /// 레이저 속도 조절 상수
    private let catchUpDistanceThreshold: Double = -20.0 // 20m 이상 뒤처지면 대기
    private let resumeDistanceThreshold: Double = -5.0   // 5m 이내로 오면 복구 시작
    private let slowDownRatio: Double = 0.8              // 대기 시 속도 80%로 하향

    // MARK: - Public API

    func start(target: PaceTarget) {
        self.target = target
        self.effectivePaceSecondsPerKm = target.totalSecondsPerKm
        self.adaptiveState = .steady
        self.lastUpdateTime = Date()
        reset()
    }

    func stop() {
        lastUpdateTime = nil
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
        let now = Date()
        guard let lastTime = lastUpdateTime else {
            lastUpdateTime = now
            return
        }
        
        let dt = now.timeIntervalSince(lastTime)
        lastUpdateTime = now

        // 1. 지능형 페이스 조절 (Adaptive Logic)
        if isAdaptiveMode {
            updateAdaptiveState(currentGap: gapMeters)
        } else {
            effectivePaceSecondsPerKm = target.totalSecondsPerKm
            adaptiveState = .steady
        }

        // 2. 레이저 이동 거리 계산 (누적 방식)
        let effectiveSpeed = 1000.0 / max(1.0, effectivePaceSecondsPerKm) // m/s
        laserDistanceMeters += effectiveSpeed * dt

        // 3. 갭 계산 (실제 거리 vs 레이저 거리)
        gapMeters = actualDistanceMeters - laserDistanceMeters

        // 4. 시간 갭 (현재 거리를 목표 페이스로 달리는데 필요한 시간과 실제 시간 차이)
        let targetSpeed = 1000.0 / target.totalSecondsPerKm
        gapSeconds = gapMeters / targetSpeed

        // 5. 상태 판정
        let threshold: Double = 10 // 10m 이내면 onPace
        if gapMeters > threshold {
            paceStatus = .ahead
        } else if gapMeters < -threshold {
            paceStatus = .behind
        } else {
            paceStatus = .onPace
        }
    }
    
    private func updateAdaptiveState(currentGap: Double) {
        guard let target = target else { return }
        
        switch adaptiveState {
        case .steady:
            if currentGap < catchUpDistanceThreshold {
                // 너무 멀어짐 -> 기다림 모드 (속도 늦춤)
                adaptiveState = .waiting
                effectivePaceSecondsPerKm = target.totalSecondsPerKm / slowDownRatio
            }
            
        case .waiting:
            if currentGap > resumeDistanceThreshold {
                // 다시 가까워짐 -> 복구 모드
                adaptiveState = .recovering
            }
            
        case .recovering:
            // 원래 목표 페이스로 서서히 복구 (초당 1초씩 조정)
            let diff = target.totalSecondsPerKm - effectivePaceSecondsPerKm
            if abs(diff) < 1.0 {
                effectivePaceSecondsPerKm = target.totalSecondsPerKm
                adaptiveState = .steady
            } else {
                effectivePaceSecondsPerKm += (diff > 0 ? 1.0 : -1.0) * 1.0
            }
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
            return AppLanguage.current.isEnglish
                ? String(format: "%@%.0fs", direction, absGap)
                : String(format: "%@%.0f초", direction, absGap)
        }
        let min = Int(absGap) / 60
        let sec = Int(absGap) % 60
        return AppLanguage.current.isEnglish
            ? String(format: "%@%dm %02ds", direction, min, sec)
            : String(format: "%@%d분 %02d초", direction, min, sec)
    }
}
