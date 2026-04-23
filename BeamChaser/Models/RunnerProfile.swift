import Foundation

// MARK: - 러너 등급 시스템

enum RunnerLevel: String, CaseIterable, Codable {
    case starter = "스타터"
    case bronze = "브론즈"
    case silver = "실버"
    case gold = "골드"
    case laser = "레이저"
    case beam = "빔 마스터"

    var rank: Int {
        switch self {
        case .starter: return 1
        case .bronze: return 2
        case .silver: return 3
        case .gold: return 4
        case .laser: return 5
        case .beam: return 6
        }
    }

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

    /// 이 레벨에 도달하기 위한 최소 XP
    var minimumXP: Int {
        switch self {
        case .starter: return 0
        case .bronze: return 180
        case .silver: return 480
        case .gold: return 980
        case .laser: return 1800
        case .beam: return 3200
        }
    }

    /// 다음 레벨
    var next: RunnerLevel? {
        let all = RunnerLevel.allCases
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }

    func localizedName(_ appLanguage: AppLanguage = .current) -> String {
        let englishName: String
        switch self {
        case .starter:
            englishName = "Starter"
        case .bronze:
            englishName = "Bronze"
        case .silver:
            englishName = "Silver"
        case .gold:
            englishName = "Gold"
        case .laser:
            englishName = "Laser"
        case .beam:
            englishName = "Beam Master"
        }

        return appLanguage.text(rawValue, englishName)
    }
}

enum BadgeCategory: String, CaseIterable, Identifiable {
    case milestone = "성장"
    case distance = "거리"
    case pace = "페이스"
    case routine = "루틴"
    case special = "스페셜"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .milestone: return "sparkles"
        case .distance: return "road.lanes"
        case .pace: return "speedometer"
        case .routine: return "calendar"
        case .special: return "star.circle"
        }
    }
}

// MARK: - 뱃지 시스템

struct RunBadge: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let earnedDate: Date?

    var isEarned: Bool { earnedDate != nil }

    static func == (lhs: RunBadge, rhs: RunBadge) -> Bool {
        lhs.id == rhs.id && lhs.earnedDate == rhs.earnedDate
    }
}

enum BadgeType: String, CaseIterable {
    // 횟수 기반
    case firstRun = "first_run"
    case fiveRuns = "five_runs"
    case tenRuns = "ten_runs"
    case twentyFiveRuns = "twenty_five_runs"
    case fiftyRuns = "fifty_runs"
    case hundredRuns = "hundred_runs"

    // 단일 거리 기반
    case first1k = "first_1k"
    case first3k = "first_3k"
    case first5k = "first_5k"
    case first10k = "first_10k"
    case halfMarathon = "half_marathon"
    case fullMarathon = "full_marathon"

    // 누적 거리 기반
    case total10km = "total_10km"
    case total50km = "total_50km"
    case total100km = "total_100km"
    case total500km = "total_500km"
    case total1000km = "total_1000km"

    // 페이스/속도 기반
    case paceMatch = "pace_match"
    case paceMatch5 = "pace_match_5"
    case speedDemon = "speed_demon"
    case consistentPace = "consistent_pace"

    // 스트릭 기반
    case streak3 = "streak_3"
    case streak7 = "streak_7"
    case streak14 = "streak_14"
    case streak30 = "streak_30"

    // 시간대 기반
    case nightRunner = "night_runner"
    case earlyBird = "early_bird"
    case lunchRunner = "lunch_runner"

    // 시간 기반
    case run30min = "run_30min"
    case run60min = "run_60min"
    case totalTime10h = "total_time_10h"

    // 특별
    case weekendWarrior = "weekend_warrior"
    case allWeekdays = "all_weekdays"
    case laserPerfect = "laser_perfect"
    case caloriesBurner = "calories_burner"

    var category: BadgeCategory {
        switch self {
        case .firstRun, .fiveRuns, .tenRuns, .twentyFiveRuns, .fiftyRuns, .hundredRuns, .totalTime10h:
            return .milestone
        case .first1k, .first3k, .first5k, .first10k, .halfMarathon, .fullMarathon,
             .total10km, .total50km, .total100km, .total500km, .total1000km:
            return .distance
        case .paceMatch, .paceMatch5, .speedDemon, .consistentPace:
            return .pace
        case .streak3, .streak7, .streak14, .streak30,
             .nightRunner, .earlyBird, .lunchRunner,
             .run30min, .run60min, .weekendWarrior, .allWeekdays:
            return .routine
        case .laserPerfect, .caloriesBurner:
            return .special
        }
    }

    var name: String {
        switch self {
        case .firstRun: return "첫 발걸음"
        case .fiveRuns: return "꾸준한 러너"
        case .tenRuns: return "10회 달성"
        case .twentyFiveRuns: return "25회 돌파"
        case .fiftyRuns: return "하프 센추리"
        case .hundredRuns: return "백 러너"

        case .first1k: return "1K 시작"
        case .first3k: return "3K 도전"
        case .first5k: return "5K 완주"
        case .first10k: return "10K 완주"
        case .halfMarathon: return "하프마라톤"
        case .fullMarathon: return "풀마라톤"

        case .total10km: return "10km 누적"
        case .total50km: return "50km 누적"
        case .total100km: return "100km 클럽"
        case .total500km: return "500km 정복"
        case .total1000km: return "1000km 전설"

        case .paceMatch: return "목표 달성"
        case .paceMatch5: return "5연속 목표 달성"
        case .speedDemon: return "스피드 데몬"
        case .consistentPace: return "일정한 페이스"

        case .streak3: return "3일 연속"
        case .streak7: return "7일 연속"
        case .streak14: return "2주 연속"
        case .streak30: return "30일 연속"

        case .nightRunner: return "야간 러너"
        case .earlyBird: return "얼리버드"
        case .lunchRunner: return "점심 러너"

        case .run30min: return "30분 러닝"
        case .run60min: return "1시간 러닝"
        case .totalTime10h: return "누적 10시간"

        case .weekendWarrior: return "주말 전사"
        case .allWeekdays: return "평일 정복"
        case .laserPerfect: return "레이저 동기화"
        case .caloriesBurner: return "칼로리 버너"
        }
    }

    var description: String {
        switch self {
        case .firstRun: return "첫 러닝 완료"
        case .fiveRuns: return "5회 러닝 완료"
        case .tenRuns: return "10회 러닝 완료"
        case .twentyFiveRuns: return "25회 러닝 완료"
        case .fiftyRuns: return "50회 러닝 완료"
        case .hundredRuns: return "100회 러닝 달성"

        case .first1k: return "1km 이상 한 번에 달리기"
        case .first3k: return "3km 이상 한 번에 달리기"
        case .first5k: return "5km 이상 한 번에 달리기"
        case .first10k: return "10km 이상 한 번에 달리기"
        case .halfMarathon: return "21.1km 이상 한 번에 달리기"
        case .fullMarathon: return "42.195km 이상 한 번에 달리기"

        case .total10km: return "누적 10km 달성"
        case .total50km: return "누적 50km 달성"
        case .total100km: return "누적 100km 달성"
        case .total500km: return "누적 500km 달성"
        case .total1000km: return "누적 1,000km 달성"

        case .paceMatch: return "목표 페이스 정확히 달성"
        case .paceMatch5: return "5회 연속 목표 페이스 달성"
        case .speedDemon: return "페이스 4분/km 이하 달성"
        case .consistentPace: return "전 구간 페이스 편차 10초 이내"

        case .streak3: return "3일 연속 러닝"
        case .streak7: return "7일 연속 러닝"
        case .streak14: return "14일 연속 러닝"
        case .streak30: return "30일 연속 러닝"

        case .nightRunner: return "밤 9시 이후 러닝"
        case .earlyBird: return "아침 6시 전 러닝"
        case .lunchRunner: return "점심시간(12~13시) 러닝"

        case .run30min: return "30분 이상 한 번에 달리기"
        case .run60min: return "60분 이상 한 번에 달리기"
        case .totalTime10h: return "누적 러닝 시간 10시간"

        case .weekendWarrior: return "주말에 5회 이상 러닝"
        case .allWeekdays: return "월~금 모두 러닝 완료"
        case .laserPerfect: return "전 구간 레이저 ±5m 이내 유지"
        case .caloriesBurner: return "한 번에 500kcal 이상 소모"
        }
    }

    var icon: String {
        switch self {
        case .firstRun: return "shoe.fill"
        case .fiveRuns: return "5.circle.fill"
        case .tenRuns: return "10.circle.fill"
        case .twentyFiveRuns: return "25.circle.fill"
        case .fiftyRuns: return "50.circle.fill"
        case .hundredRuns: return "star.circle.fill"

        case .first1k: return "figure.walk"
        case .first3k: return "figure.run"
        case .first5k: return "flag.fill"
        case .first10k: return "flag.checkered"
        case .halfMarathon: return "trophy"
        case .fullMarathon: return "trophy.fill"

        case .total10km: return "road.lanes"
        case .total50km: return "map"
        case .total100km: return "globe.americas.fill"
        case .total500km: return "airplane"
        case .total1000km: return "crown.fill"

        case .paceMatch: return "target"
        case .paceMatch5: return "scope"
        case .speedDemon: return "hare.fill"
        case .consistentPace: return "metronome"

        case .streak3: return "flame"
        case .streak7: return "flame.fill"
        case .streak14: return "bolt.heart.fill"
        case .streak30: return "bolt.fill"

        case .nightRunner: return "moon.fill"
        case .earlyBird: return "sunrise.fill"
        case .lunchRunner: return "sun.max.fill"

        case .run30min: return "timer"
        case .run60min: return "hourglass"
        case .totalTime10h: return "clock.fill"

        case .weekendWarrior: return "calendar.badge.checkmark"
        case .allWeekdays: return "calendar"
        case .laserPerfect: return "laser.burst"
        case .caloriesBurner: return "flame.circle.fill"
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
    @Published var experiencePoints: Int = 0
    @Published var badges: [RunBadge] = []
    @Published var monthlyGoal: MonthlyGoal = .current()
    @Published var currentStreak: Int = 0

    @Published var nickname: String = "러너"
    @Published var profileImageURL: String?
    @Published var showNicknameSetup = false
    @Published var newlyEarnedBadge: RunBadge?
    @Published var pendingBadges: [RunBadge] = []

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
        let totalTimeSeconds = validRecords.reduce(0.0) { $0 + $1.elapsedSeconds }

        let oldBadgeIds = Set(badges.map(\.id))
        let oldBadgeDates = Dictionary(uniqueKeysWithValues: badges.compactMap { badge in
            badge.earnedDate.map { (badge.id, $0) }
        })
        var newBadges: [RunBadge] = []

        // 횟수 기반
        if validRecords.count >= 1 { newBadges.append(makeBadge(.firstRun, existingEarnedDate: oldBadgeDates[BadgeType.firstRun.rawValue])) }
        if validRecords.count >= 5 { newBadges.append(makeBadge(.fiveRuns, existingEarnedDate: oldBadgeDates[BadgeType.fiveRuns.rawValue])) }
        if validRecords.count >= 10 { newBadges.append(makeBadge(.tenRuns, existingEarnedDate: oldBadgeDates[BadgeType.tenRuns.rawValue])) }
        if validRecords.count >= 25 { newBadges.append(makeBadge(.twentyFiveRuns, existingEarnedDate: oldBadgeDates[BadgeType.twentyFiveRuns.rawValue])) }
        if validRecords.count >= 50 { newBadges.append(makeBadge(.fiftyRuns, existingEarnedDate: oldBadgeDates[BadgeType.fiftyRuns.rawValue])) }
        if validRecords.count >= 100 { newBadges.append(makeBadge(.hundredRuns, existingEarnedDate: oldBadgeDates[BadgeType.hundredRuns.rawValue])) }

        // 단일 거리 기반
        if validRecords.contains(where: { $0.totalDistanceMeters >= 1000 }) {
            newBadges.append(makeBadge(.first1k, existingEarnedDate: oldBadgeDates[BadgeType.first1k.rawValue]))
        }
        if validRecords.contains(where: { $0.totalDistanceMeters >= 3000 }) {
            newBadges.append(makeBadge(.first3k, existingEarnedDate: oldBadgeDates[BadgeType.first3k.rawValue]))
        }
        if validRecords.contains(where: { $0.totalDistanceMeters >= 5000 }) {
            newBadges.append(makeBadge(.first5k, existingEarnedDate: oldBadgeDates[BadgeType.first5k.rawValue]))
        }
        if validRecords.contains(where: { $0.totalDistanceMeters >= 10000 }) {
            newBadges.append(makeBadge(.first10k, existingEarnedDate: oldBadgeDates[BadgeType.first10k.rawValue]))
        }
        if validRecords.contains(where: { $0.totalDistanceMeters >= 21100 }) {
            newBadges.append(makeBadge(.halfMarathon, existingEarnedDate: oldBadgeDates[BadgeType.halfMarathon.rawValue]))
        }
        if validRecords.contains(where: { $0.totalDistanceMeters >= 42195 }) {
            newBadges.append(makeBadge(.fullMarathon, existingEarnedDate: oldBadgeDates[BadgeType.fullMarathon.rawValue]))
        }

        // 누적 거리 기반
        if totalDistanceKm >= 10 { newBadges.append(makeBadge(.total10km, existingEarnedDate: oldBadgeDates[BadgeType.total10km.rawValue])) }
        if totalDistanceKm >= 50 { newBadges.append(makeBadge(.total50km, existingEarnedDate: oldBadgeDates[BadgeType.total50km.rawValue])) }
        if totalDistanceKm >= 100 { newBadges.append(makeBadge(.total100km, existingEarnedDate: oldBadgeDates[BadgeType.total100km.rawValue])) }
        if totalDistanceKm >= 500 { newBadges.append(makeBadge(.total500km, existingEarnedDate: oldBadgeDates[BadgeType.total500km.rawValue])) }
        if totalDistanceKm >= 1000 { newBadges.append(makeBadge(.total1000km, existingEarnedDate: oldBadgeDates[BadgeType.total1000km.rawValue])) }

        // 속도 기반
        if validRecords.contains(where: {
            $0.averagePaceSecondsPerKm > 0 && $0.averagePaceSecondsPerKm < 240
        }) {
            newBadges.append(makeBadge(.speedDemon, existingEarnedDate: oldBadgeDates[BadgeType.speedDemon.rawValue]))
        }

        // 목표 달성
        let paceMatchRecords = validRecords.filter {
            guard let target = $0.targetPace else { return false }
            return $0.averagePaceSecondsPerKm <= target.totalSecondsPerKm
        }
        if !paceMatchRecords.isEmpty {
            newBadges.append(makeBadge(.paceMatch, existingEarnedDate: oldBadgeDates[BadgeType.paceMatch.rawValue]))
        }
        if paceMatchRecords.count >= 5 {
            newBadges.append(makeBadge(.paceMatch5, existingEarnedDate: oldBadgeDates[BadgeType.paceMatch5.rawValue]))
        }

        // 일정한 페이스 (구간 편차 10초 이내)
        if validRecords.contains(where: { record in
            guard record.routePoints.count >= 10 else { return false }
            let paces = record.routePoints.compactMap { $0.speed > 0 ? 1000.0 / $0.speed : nil }
            guard paces.count >= 5 else { return false }
            let avg = paces.reduce(0, +) / Double(paces.count)
            let maxDev = paces.map { abs($0 - avg) }.max() ?? 999
            return maxDev <= 10
        }) {
            newBadges.append(makeBadge(.consistentPace, existingEarnedDate: oldBadgeDates[BadgeType.consistentPace.rawValue]))
        }

        // 시간대 기반
        let cal = Calendar.current
        if validRecords.contains(where: { cal.component(.hour, from: $0.startDate) >= 21 }) {
            newBadges.append(makeBadge(.nightRunner, existingEarnedDate: oldBadgeDates[BadgeType.nightRunner.rawValue]))
        }
        if validRecords.contains(where: { cal.component(.hour, from: $0.startDate) < 6 }) {
            newBadges.append(makeBadge(.earlyBird, existingEarnedDate: oldBadgeDates[BadgeType.earlyBird.rawValue]))
        }
        if validRecords.contains(where: {
            let hour = cal.component(.hour, from: $0.startDate)
            return hour >= 12 && hour < 13
        }) {
            newBadges.append(makeBadge(.lunchRunner, existingEarnedDate: oldBadgeDates[BadgeType.lunchRunner.rawValue]))
        }

        // 시간 기반
        if validRecords.contains(where: { $0.elapsedSeconds >= 1800 }) {
            newBadges.append(makeBadge(.run30min, existingEarnedDate: oldBadgeDates[BadgeType.run30min.rawValue]))
        }
        if validRecords.contains(where: { $0.elapsedSeconds >= 3600 }) {
            newBadges.append(makeBadge(.run60min, existingEarnedDate: oldBadgeDates[BadgeType.run60min.rawValue]))
        }
        if totalTimeSeconds >= 36000 {
            newBadges.append(makeBadge(.totalTime10h, existingEarnedDate: oldBadgeDates[BadgeType.totalTime10h.rawValue]))
        }

        // 칼로리 (MET 10 × 70kg 가정)
        if validRecords.contains(where: { ($0.elapsedSeconds / 3600.0) * 10.0 * 70.0 >= 500 }) {
            newBadges.append(makeBadge(.caloriesBurner, existingEarnedDate: oldBadgeDates[BadgeType.caloriesBurner.rawValue]))
        }

        // 주말 전사 (주말 5회 이상)
        let weekendRuns = validRecords.filter {
            let weekday = cal.component(.weekday, from: $0.startDate)
            return weekday == 1 || weekday == 7
        }
        if weekendRuns.count >= 5 {
            newBadges.append(makeBadge(.weekendWarrior, existingEarnedDate: oldBadgeDates[BadgeType.weekendWarrior.rawValue]))
        }

        // 평일 정복 (한 주 내 월~금 모두 러닝)
        let cal2 = Calendar.current
        let weekGrouped = Dictionary(grouping: validRecords) { record -> Date in
            let comps = cal2.dateComponents([.yearForWeekOfYear, .weekOfYear], from: record.startDate)
            return cal2.date(from: comps) ?? record.startDate
        }
        let hasFullWeekday = weekGrouped.values.contains { weekRecords in
            let weekdays = Set(weekRecords.compactMap { r -> Int? in
                let wd = cal.component(.weekday, from: r.startDate)
                return (wd >= 2 && wd <= 6) ? wd : nil
            })
            return weekdays.count == 5
        }
        if hasFullWeekday {
            newBadges.append(makeBadge(.allWeekdays, existingEarnedDate: oldBadgeDates[BadgeType.allWeekdays.rawValue]))
        }

        // 연속 러닝 스트릭
        currentStreak = calculateStreak(records: validRecords)
        if currentStreak >= 3 { newBadges.append(makeBadge(.streak3, existingEarnedDate: oldBadgeDates[BadgeType.streak3.rawValue])) }
        if currentStreak >= 7 { newBadges.append(makeBadge(.streak7, existingEarnedDate: oldBadgeDates[BadgeType.streak7.rawValue])) }
        if currentStreak >= 14 { newBadges.append(makeBadge(.streak14, existingEarnedDate: oldBadgeDates[BadgeType.streak14.rawValue])) }
        if currentStreak >= 30 { newBadges.append(makeBadge(.streak30, existingEarnedDate: oldBadgeDates[BadgeType.streak30.rawValue])) }

        // 레이저 동기화 (목표 페이스 러닝에서 전 구간 레이저 범위 ±5m 이내)
        // 레이저 동기화 = 목표 페이스 달성하면서 페이스 편차가 매우 작은 러닝
        if validRecords.contains(where: { record in
            guard let target = record.targetPace,
                  record.averagePaceSecondsPerKm <= target.totalSecondsPerKm,
                  record.routePoints.count >= 10 else { return false }
            let paces = record.routePoints.compactMap { $0.speed > 0 ? 1000.0 / $0.speed : nil }
            guard paces.count >= 5 else { return false }
            let avg = paces.reduce(0, +) / Double(paces.count)
            let maxDev = paces.map { abs($0 - avg) }.max() ?? 999
            return maxDev <= 5
        }) {
            newBadges.append(makeBadge(.laserPerfect, existingEarnedDate: oldBadgeDates[BadgeType.laserPerfect.rawValue]))
        }

        experiencePoints = calculateExperience(
            totalDistanceKm: totalDistanceKm,
            totalTimeSeconds: totalTimeSeconds,
            runCount: validRecords.count,
            earnedBadgeCount: newBadges.count,
            streak: currentStreak
        )

        for lvl in RunnerLevel.allCases.reversed() {
            if experiencePoints >= lvl.minimumXP {
                level = lvl
                break
            }
        }

        badges = newBadges

        // 새로 획득한 뱃지 감지 (여러 개 지원)
        let newBadgeIds = Set(newBadges.map(\.id))
        let freshlyEarned = newBadgeIds.subtracting(oldBadgeIds)
        let freshBadges = newBadges.filter { freshlyEarned.contains($0.id) }
        if let first = freshBadges.first {
            newlyEarnedBadge = first
            if freshBadges.count > 1 {
                pendingBadges = Array(freshBadges.dropFirst())
            }
        } else {
            newlyEarnedBadge = nil
            pendingBadges = []
        }

        saveProfile()
    }

    private func makeBadge(_ type: BadgeType, existingEarnedDate: Date?) -> RunBadge {
        RunBadge(
            id: type.rawValue,
            name: type.name,
            description: type.description,
            icon: type.icon,
            earnedDate: existingEarnedDate ?? Date()
        )
    }

    private func calculateExperience(
        totalDistanceKm: Double,
        totalTimeSeconds: Double,
        runCount: Int,
        earnedBadgeCount: Int,
        streak: Int
    ) -> Int {
        let distanceXP = Int((totalDistanceKm * 5.0).rounded())
        let runXP = runCount * 16
        let durationXP = Int((totalTimeSeconds / 180.0).rounded(.down))
        let badgeXP = earnedBadgeCount * 24
        let streakXP = min(streak, 30) * 6

        return distanceXP + runXP + durationXP + badgeXP + streakXP
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

    func resetLocalProfile() {
        level = .starter
        experiencePoints = 0
        badges = []
        monthlyGoal = .current()
        currentStreak = 0
        nickname = "러너"
        profileImageURL = nil
        newlyEarnedBadge = nil
        pendingBadges = []

        do {
            if FileManager.default.fileExists(atPath: savePath.path) {
                try FileManager.default.removeItem(at: savePath)
            }
        } catch {
            print("프로필 파일 삭제 실패: \(error)")
        }
    }
}
