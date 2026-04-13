import Foundation
import Combine

/// AI 코칭 서비스 — 사용자 데이터를 분석하여 최적의 페이스 추천
@MainActor
final class PaceCoachingService: ObservableObject {
    
    @Published var recommendedTarget: PaceTarget?
    @Published var coachingMessage: String = "데이터를 분석 중입니다..."
    
    private let healthKit: HealthKitService
    
    init(healthKit: HealthKitService) {
        self.healthKit = healthKit
    }
    
    /// 최근 러닝 기록을 분석하여 오늘의 페이스 추천
    func generateRecommendation(pastRecords: [RunRecord]) {
        guard !pastRecords.isEmpty else {
            recommendedTarget = PaceTarget(minutesPerKm: 6, secondsPerKm: 0)
            coachingMessage = "첫 러닝이군요! 가벼운 조깅 페이스로 시작해볼까요?"
            return
        }
        
        // 최근 3개 기록의 평균 페이스 계산
        let recent3 = pastRecords.suffix(3)
        let avgSeconds = recent3.compactMap { $0.targetPace?.totalSecondsPerKm }.reduce(0, +) / Double(recent3.count)
        
        let avgMinutes = Int(avgSeconds) / 60
        let avgSecs = Int(avgSeconds) % 60
        
        recommendedTarget = PaceTarget(minutesPerKm: avgMinutes, secondsPerKm: avgSecs)
        coachingMessage = "최근 평균 페이스는 \(avgMinutes)분 \(avgSecs)초입니다. 오늘도 이 페이스를 유지해보세요!"
    }
    
    /// 실시간 상태(심박수) 분석 및 피드백
    func checkRealtimeStatus(heartRate: Double, currentGap: Double) -> CoachingAction {
        if heartRate > 175 {
            return .slowDown(reason: "심박수가 너무 높습니다! 레이저가 속도를 늦춥니다.")
        }
        
        if currentGap < -30 {
            return .wait(reason: "많이 뒤처지셨네요. 레이저가 앞에서 기다릴게요.")
        }
        
        return .keepGoing
    }
    
    enum CoachingAction {
        case keepGoing
        case slowDown(reason: String)
        case wait(reason: String)
    }
}
