import Foundation

// MARK: - 러너 등급 시스템

enum RunnerLevel: String, CaseIterable, Codable {
    case starter = "스타터"
    case bronze = "브론즈"
    case silver = "실버"
    case gold = "골드"
    case laser = "레이저"
    case beam = "빔 마스터"

    var icon: String {
        switch self {
        case .starter: return "figure.walk"
        case .bronze: return "medal"
        case .silver: return "medal.fill"
        case .gold: return "trophy"
        case .laser: return "laser.burst"
        case .beam: return "bolt.shield.fill"
        }
    }

    var color: String {
        switch self {
        case .starter: return "gray"
        case .bronze: return "brown"
        case .silver: return "silver"
        case .gold: return "gold"
        case .laser: return "red"
        case .beam: return "orange"
        }
    }

    /// 이 레벨 달성에 필요한 누적 거리 (km)
    var requiredDistanceKm: Double {
        switch self {
        case .starter: return 0
        case .bronze: return 10
        case .silver: return 50
        case .gold: return 100
        case .laser: return 300
        case .beam: return 1000
        }
    }

    /// 다음 레벨
    var next: RunnerLevel? {
        let all = RunnerLevel.allCases
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }
}

// MARK: - 뱃지 시스템

struct RunBadge: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let earnedDate: Date?

    var isEarned: Bool { earnedDate != nil }
}

enum BadgeType: String, CaseIterable {
    case firstRun = "first_run"
    case fiveRuns = "five_runs"
    case tenRuns = "ten_runs"
    case fiftyRuns = "fifty_runs"
    case first5k = "first_5k"
    case first10k = "first_10k"
    case halfMarathon = "half_marathon"
    case fullMarathon = "full_marathon"
    case paceMatch = "pace_match"
    case streak3 = "streak_3"
    case streak7 = "streak_7"
    case streak30 = "streak_30"
    case nightRunner = "night_runner"
    case earlyBird = "early_bird"
    case speedDemon = "speed_demon"
    case laserPerfect = "laser_perfect"

    var name: String {
        switch self {
        case .firstRun: return "첫 발걸음"
        case .fiveRuns: return "꾸준한 러너"
        case .tenRuns: return "10회 달성"
        case .fiftyRuns: return "하프 센추리"
        case .first5k: return "5K 완주"
        case .first10k: return "10K 완주"
        case .halfMarathon: return "하프마라톤"
        case .fullMarathon: return "풀마라톤"
        case .paceMatch: return "목표 달성"
        case .streak3: return "3일 연속"
        case .streak7: return "7일 연속"
        case .streak30: return "30일 연속"
        case .nightRunner: return "야간 러너"
        case .earlyBird: return "얼리버드"
        case .speedDemon: return "스피드 데몬"
        case .laserPerfect: return "레이저 동기화"
        }
    }

    var description: String {
        switch self {
        case .firstRun: return "첫 러닝 완료"
        case .fiveRuns: return "5회 러닝 완료"
        case .tenRuns: return "10회 러닝 완료"
        case .fiftyRuns: return "50회 러닝 완료"
        case .first5k: return "5km 이상 한 번에 달리기"
        case .first10k: return "10km 이상 한 번에 달리기"
        case .halfMarathon: return "21.1km 이상 한 번에 달리기"
        case .fullMarathon: return "42.195km 이상 한 번에 달리기"
        case .paceMatch: return "목표 페이스 정확히 달성"
        case .streak3: return "3일 연속 러닝"
        case .streak7: return "7일 연속 러닝"
        case .streak30: return "30일 연속 러닝"
        case .nightRunner: return "밤 9시 이후 러닝"
        case .earlyBird: return "아침 6시 전 러닝"
        case .speedDemon: return "페이스 4분/km 이하 달성"
        case .laserPerfect: return "전 구간 레이저 ±5m 이내 유지"
        }
    }

    var icon: String {
        switch self {
        case .firstRun: return "shoe.fill"
        case .fiveRuns: return "5.circle.fill"
        case .tenRuns: return "10.circle.fill"
        case .fiftyRuns: return "50.circle.fill"
        case .first5k: return "flag.fill"
        case .first10k: return "flag.checkered"
        case .halfMarathon: return "trophy"
        case .fullMarathon: return "trophy.fill"
        case .paceMatch: return "target"
        case .streak3: return "flame"
        case .streak7: return "flame.fill"
        case .streak30: return "bolt.fill"
        case .nightRunner: return "moon.fill"
        case .earlyBird: return "sunrise.fill"
        case .speedDemon: return "hare.fill"
        case .laserPerfect: return "laser.burst"
        }
    }
}

// MARK: - 월간 목표

struct MonthlyGoal: Codable {
    var targetRunCount: Int
    var targetDistanceKm: Double
    var month: Int   // 1-12
    var year: Int

    static func current() -> MonthlyGoal {
        let cal = Calendar.current
        let now = Date()
        return MonthlyGoal(
            targetRunCount: 12,
            targetDistanceKm: 50.0,
            month: cal.component(.month, from: now),
            year: cal.component(.year, from: now)
        )
    }
}

// MARK: - 프로필 서비스

@MainActor
final class ProfileService: ObservableObject {

    @Published var level: RunnerLevel = .starter
    @Published var badges: [RunBadge] = []
    @Published var monthlyGoal: MonthlyGoal = .current()
    @Published var currentStreak: Int = 0

    // 닉네임 (로컬 기본값, 카카오 로그인 시 덮어씀)
    @Published var nickname: String = "러너"
    @Published var profileImageURL: String?

    private var savePath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("runner_profile.json")
    }

    init() {
        loadProfile()
    }

    // MARK: - 뱃지 & 레벨 평가

    func evaluateAfterRun(records: [RunRecord]) {
        let validRecords = records.filter { $0.totalDistanceMeters > 100 }
        let totalDistanceKm = validRecords.reduce(0.0) { $0 + $1.totalDistanceMeters / 1000.0 }

        // 레벨 업데이트
        for lvl in RunnerLevel.allCases.reversed() {
            if totalDistanceKm >= lvl.requiredDistanceKm {
                level = lvl
                break
            }
        }

        // 뱃지 확인
        var newBadges: [RunBadge] = []

        // 횟수 기반
        if validRecords.count >= 1 { newBadges.append(makeBadge(.firstRun)) }
        if validRecords.count >= 5 { newBadges.append(makeBadge(.fiveRuns)) }
        if validRecords.count >= 10 { newBadges.append(makeBadge(.tenRuns)) }
        if validRecords.count >= 50 { newBadges.append(makeBadge(.fiftyRuns)) }

        // 거리 기반 (단일 러닝)
        if validRecords.contains(where: { $0.totalDistanceMeters >= 5000 }) {
            newBadges.append(makeBadge(.first5k))
        }
        if validRecords.contains(where: { $0.totalDistanceMeters >= 10000 }) {
            newBadges.append(makeBadge(.first10k))
        }
        if validRecords.contains(where: { $0.totalDistanceMeters >= 21100 }) {
            newBadges.append(makeBadge(.halfMarathon))
        }
        if validRecords.contains(where: { $0.totalDistanceMeters >= 42195 }) {
            newBadges.append(makeBadge(.fullMarathon))
        }

        // 속도 기반
        if validRecords.contains(where: {
            $0.averagePaceSecondsPerKm > 0 && $0.averagePaceSecondsPerKm < 240
        }) {
            newBadges.append(makeBadge(.speedDemon))
        }

        // 목표 달성
        if validRecords.contains(where: {
            guard let target = $0.targetPace else { return false }
            return $0.averagePaceSecondsPerKm <= target.totalSecondsPerKm
        }) {
            newBadges.append(makeBadge(.paceMatch))
        }

        // 시간대 기반
        let cal = Calendar.current
        if validRecords.contains(where: { cal.component(.hour, from: $0.startDate) >= 21 }) {
            newBadges.append(makeBadge(.nightRunner))
        }
        if validRecords.contains(where: { cal.component(.hour, from: $0.startDate) < 6 }) {
            newBadges.append(makeBadge(.earlyBird))
        }

        // 연속 러닝 스트릭
        currentStreak = calculateStreak(records: validRecords)
        if currentStreak >= 3 { newBadges.append(makeBadge(.streak3)) }
        if currentStreak >= 7 { newBadges.append(makeBadge(.streak7)) }
        if currentStreak >= 30 { newBadges.append(makeBadge(.streak30)) }

        badges = newBadges
        saveProfile()
    }

    private func makeBadge(_ type: BadgeType) -> RunBadge {
        RunBadge(
            id: type.rawValue,
            name: type.name,
            description: type.description,
            icon: type.icon,
            earnedDate: Date()
        )
    }

    private func calculateStreak(records: [RunRecord]) -> Int {
        let cal = Calendar.current
        let sortedDates = records.map { cal.startOfDay(for: $0.startDate) }
        let uniqueDates = Array(Set(sortedDates)).sorted(by: >)
        guard !uniqueDates.isEmpty else { return 0 }

        var streak = 1
        let today = cal.startOfDay(for: Date())

        // 오늘 또는 어제 달렸는지 확인
        guard let first = uniqueDates.first,
              cal.dateComponents([.day], from: first, to: today).day! <= 1 else {
            return 0
        }

        for i in 1..<uniqueDates.count {
            let diff = cal.dateComponents([.day], from: uniqueDates[i], to: uniqueDates[i-1]).day!
            if diff == 1 {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    // MARK: - 월간 진행률

    func monthlyProgress(records: [RunRecord]) -> (runs: Int, distanceKm: Double) {
        let cal = Calendar.current
        let now = Date()
        let thisMonth = records.filter {
            cal.component(.month, from: $0.startDate) == cal.component(.month, from: now) &&
            cal.component(.year, from: $0.startDate) == cal.component(.year, from: now) &&
            $0.totalDistanceMeters > 100
        }
        let runs = thisMonth.count
        let dist = thisMonth.reduce(0.0) { $0 + $1.totalDistanceMeters / 1000.0 }
        return (runs, dist)
    }

    // MARK: - Persistence

    private struct ProfileData: Codable {
        var nickname: String
        var profileImageURL: String?
        var monthlyGoal: MonthlyGoal
    }

    private func saveProfile() {
        let data = ProfileData(
            nickname: nickname,
            profileImageURL: profileImageURL,
            monthlyGoal: monthlyGoal
        )
        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: savePath, options: .atomic)
        } catch {
            print("프로필 저장 실패: \(error)")
        }
    }

    private func loadProfile() {
        guard FileManager.default.fileExists(atPath: savePath.path) else { return }
        do {
            let data = try Data(contentsOf: savePath)
            let decoded = try JSONDecoder().decode(ProfileData.self, from: data)
            nickname = decoded.nickname
            profileImageURL = decoded.profileImageURL
            monthlyGoal = decoded.monthlyGoal
        } catch {
            print("프로필 로드 실패: \(error)")
        }
    }
}
