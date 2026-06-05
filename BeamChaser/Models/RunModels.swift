import Foundation
import CoreLocation

// MARK: - 러닝 세션 데이터

struct RunRecord: Identifiable, Codable {
    let id: UUID
    let startDate: Date
    var endDate: Date?
    var routePoints: [RoutePoint]
    var totalDistanceMeters: Double
    var elapsedSeconds: TimeInterval
    var targetPace: PaceTarget?
    var runGoal: RunGoal?
    var intervalProgram: IntervalProgram?
    var averageCadenceSpm: Int? = nil
    var averageHeartRateBpm: Int? = nil
    var caloriesEstimatedKcal: Double? = nil
    var dataQuality: RunDataQuality? = nil

    var averagePaceSecondsPerKm: Double {
        guard totalDistanceMeters > 0 else { return 0 }
        return elapsedSeconds / (totalDistanceMeters / 1000.0)
    }

    var formattedDistance: String {
        String(format: "%.2fkm", totalDistanceMeters / 1000.0)
    }

    var formattedPace: String {
        Self.formatPace(averagePaceSecondsPerKm)
    }

    var formattedDuration: String {
        Self.formatDuration(elapsedSeconds)
    }

    var formattedCadence: String {
        guard let averageCadenceSpm, averageCadenceSpm > 0 else { return "--" }
        return "\(averageCadenceSpm) spm"
    }

    var formattedAverageHeartRate: String {
        guard let averageHeartRateBpm, averageHeartRateBpm > 0 else { return "-- bpm" }
        return "\(averageHeartRateBpm) bpm"
    }

    var distanceKm: Double {
        totalDistanceMeters / 1000.0
    }

    var averageSpeedKmh: Double {
        analyzedMetrics.averageSpeedKmh
    }

    var maxSpeedKmh: Double {
        analyzedMetrics.maxSpeedKmh ?? 0
    }

    var elevationGainMeters: Double {
        analyzedMetrics.elevationGainMeters ?? 0
    }

    var reliableMaxSpeedKmh: Double? {
        analyzedMetrics.maxSpeedKmh
    }

    var reliableElevationGainMeters: Double? {
        analyzedMetrics.elevationGainMeters
    }

    var averageGPSAccuracyMeters: Double? {
        let samples = routePoints
            .map(\.horizontalAccuracy)
            .filter { $0 > 0 && $0.isFinite }

        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }

    var estimatedCaloriesKcal: Double {
        analyzedMetrics.caloriesEstimatedKcal
    }

    var resolvedDataQuality: RunDataQuality {
        analyzedMetrics.dataQuality
    }

    var analyzedMetrics: RunMetricAnalysis {
        RunMetricsAnalyzer.analyze(record: self)
    }

    var goalDeltaSeconds: Int? {
        guard let targetPace, averagePaceSecondsPerKm > 0 else { return nil }
        return Int((averagePaceSecondsPerKm - targetPace.totalSecondsPerKm).rounded())
    }

    static func formatPace(_ secondsPerKm: Double) -> String {
        guard secondsPerKm > 0, secondsPerKm.isFinite else { return "--:--" }
        let minutes = Int(secondsPerKm) / 60
        let seconds = Int(secondsPerKm) % 60
        return String(format: "%d'%02d\"", minutes, seconds)
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

enum RunShareMetricKey: String, CaseIterable, Codable, Identifiable {
    case duration
    case pace
    case averageHeartRate
    case averageSpeed
    case cadence
    case elevationGain
    case calories
    case goalDelta

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .duration:
            return "timer"
        case .pace:
            return "speedometer"
        case .averageHeartRate:
            return "heart.fill"
        case .averageSpeed:
            return "gauge.with.dots.needle.50percent"
        case .cadence:
            return "figure.run"
        case .elevationGain:
            return "mountain.2"
        case .calories:
            return "flame.fill"
        case .goalDelta:
            return "target"
        }
    }

    func title(_ appLanguage: AppLanguage = .current) -> String {
        switch self {
        case .duration:
            return appLanguage.text("시간", "Time")
        case .pace:
            return appLanguage.text("평균 페이스", "Average Pace")
        case .averageHeartRate:
            return appLanguage.text("평균 심박수", "Average Heart Rate")
        case .averageSpeed:
            return appLanguage.text("평균 속도", "Average Speed")
        case .cadence:
            return appLanguage.text("케이던스", "Cadence")
        case .elevationGain:
            return appLanguage.text("고도 상승", "Elevation Gain")
        case .calories:
            return appLanguage.text("칼로리", "Calories")
        case .goalDelta:
            return appLanguage.text("목표 결과", "Goal Result")
        }
    }
}

enum RunPresentationFormatter {
    static func scheduleString(from date: Date, appLanguage: AppLanguage = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLanguage.isEnglish ? Locale(identifier: "en_US") : Locale(identifier: "ko_KR")
        formatter.dateFormat = appLanguage.isEnglish
            ? "EEEE, MMM d, yyyy · h:mm a"
            : "yyyy년 M월 d일 EEEE · HH:mm"
        return formatter.string(from: date)
    }

    static func shortWeekdayString(from date: Date, appLanguage: AppLanguage = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLanguage.isEnglish ? Locale(identifier: "en_US") : Locale(identifier: "ko_KR")
        formatter.dateFormat = appLanguage.isEnglish ? "EEE" : "E"
        return formatter.string(from: date)
    }
}

// MARK: - GPS 좌표 포인트

struct RoutePoint: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let timestamp: Date
    let speed: Double          // m/s
    let horizontalAccuracy: Double
    let verticalAccuracy: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(
        latitude: Double,
        longitude: Double,
        altitude: Double,
        timestamp: Date,
        speed: Double,
        horizontalAccuracy: Double,
        verticalAccuracy: Double?
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.timestamp = timestamp
        self.speed = speed
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
    }

    init(from location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.timestamp = location.timestamp
        self.speed = max(0, location.speed)
        self.horizontalAccuracy = location.horizontalAccuracy
        self.verticalAccuracy = location.verticalAccuracy
    }
}

// MARK: - 목표 페이스

struct PaceTarget: Codable {
    let minutesPerKm: Int
    let secondsPerKm: Int

    var totalSecondsPerKm: Double {
        Double(minutesPerKm * 60 + secondsPerKm)
    }

    var formatted: String {
        String(format: "%d'%02d\"/km", minutesPerKm, secondsPerKm)
    }
}

// MARK: - 러닝 상태

enum RunState: Equatable {
    case idle
    case countdown(Int)
    case running
    case paused
    case finished
}

// MARK: - 앱 모드

enum AppMode: String, CaseIterable {
    case running = "러닝 모드"
    case game = "게임 모드"

    var icon: String {
        switch self {
        case .running: return "figure.run"
        case .game: return "gamecontroller.fill"
        }
    }

    var description: String {
        switch self {
        case .running: return "목표 페이스로 달리기"
        case .game: return "재미있는 러닝 게임"
        }
    }
}

// MARK: - 러닝 목표 타입

enum RunGoalType: String, CaseIterable, Codable {
    case none = "자유 러닝"
    case distance = "목표 거리"
    case time = "목표 시간"
    case combined = "복합 목표"

    var icon: String {
        switch self {
        case .none: return "infinity"
        case .distance: return "flag.checkered"
        case .time: return "timer"
        case .combined: return "scope"
        }
    }
}

struct RunGoal: Codable {
    let type: RunGoalType
    let targetDistanceKm: Double?     // 목표 거리 (km)
    let targetTimeMinutes: Int?       // 목표 시간 (분)

    var hasDistanceTarget: Bool { (targetDistanceKm ?? 0) > 0 }
    var hasTimeTarget: Bool { (targetTimeMinutes ?? 0) > 0 }

    static let none = RunGoal(type: .none, targetDistanceKm: nil, targetTimeMinutes: nil)
}

// MARK: - 인터벌 트레이닝

struct IntervalSegment: Identifiable, Codable {
    let id: UUID
    let name: String                  // "웜업", "본운동", "쿨다운" 등
    let distanceKm: Double            // 이 구간 거리 (km)
    let paceMinutes: Int
    let paceSeconds: Int

    init(name: String, distanceKm: Double, paceMinutes: Int, paceSeconds: Int) {
        self.id = UUID()
        self.name = name
        self.distanceKm = distanceKm
        self.paceMinutes = paceMinutes
        self.paceSeconds = paceSeconds
    }

    var totalSecondsPerKm: Double {
        Double(paceMinutes * 60 + paceSeconds)
    }

    var formattedPace: String {
        String(format: "%d'%02d\"/km", paceMinutes, paceSeconds)
    }
}

struct IntervalProgram: Codable {
    let name: String
    let segments: [IntervalSegment]

    var totalDistanceKm: Double {
        segments.reduce(0) { $0 + $1.distanceKm }
    }

    static let presets: [IntervalProgram] = [
        IntervalProgram(name: "5km 인터벌", segments: [
            IntervalSegment(name: "웜업", distanceKm: 1.0, paceMinutes: 6, paceSeconds: 30),
            IntervalSegment(name: "빠르게", distanceKm: 1.0, paceMinutes: 4, paceSeconds: 30),
            IntervalSegment(name: "회복", distanceKm: 1.0, paceMinutes: 6, paceSeconds: 0),
            IntervalSegment(name: "빠르게", distanceKm: 1.0, paceMinutes: 4, paceSeconds: 30),
            IntervalSegment(name: "쿨다운", distanceKm: 1.0, paceMinutes: 7, paceSeconds: 0),
        ]),
        IntervalProgram(name: "웜업-본운동-쿨다운", segments: [
            IntervalSegment(name: "웜업", distanceKm: 1.0, paceMinutes: 7, paceSeconds: 0),
            IntervalSegment(name: "본운동", distanceKm: 3.0, paceMinutes: 5, paceSeconds: 0),
            IntervalSegment(name: "쿨다운", distanceKm: 1.0, paceMinutes: 7, paceSeconds: 0),
        ]),
        IntervalProgram(name: "피라미드 인터벌", segments: [
            IntervalSegment(name: "웜업", distanceKm: 0.5, paceMinutes: 6, paceSeconds: 30),
            IntervalSegment(name: "1단계", distanceKm: 1.0, paceMinutes: 5, paceSeconds: 30),
            IntervalSegment(name: "2단계", distanceKm: 1.0, paceMinutes: 5, paceSeconds: 0),
            IntervalSegment(name: "3단계", distanceKm: 1.0, paceMinutes: 4, paceSeconds: 30),
            IntervalSegment(name: "2단계", distanceKm: 1.0, paceMinutes: 5, paceSeconds: 0),
            IntervalSegment(name: "1단계", distanceKm: 1.0, paceMinutes: 5, paceSeconds: 30),
            IntervalSegment(name: "쿨다운", distanceKm: 0.5, paceMinutes: 6, paceSeconds: 30),
        ]),
    ]
}

// MARK: - 레이저 캘리브레이션

struct LaserCalibration: Codable {
    var userHeightCm: Int             // 사용자 키 (cm)
    var mountPosition: MountPosition  // 기기 장착 위치
    var laserAngleOffset: Double      // 레이저 각도 미세 조절 (-5 ~ +5도)
    var projectionDistanceM: Double   // 기본 투사 거리 (m)

    enum MountPosition: String, CaseIterable, Codable {
        case chest = "가슴"
        case waist = "허리"
        case armband = "팔"

        func displayName(_ appLanguage: AppLanguage = .current) -> String {
            let englishName: String
            switch self {
            case .chest:
                englishName = "Chest"
            case .waist:
                englishName = "Waist"
            case .armband:
                englishName = "Arm"
            }

            return appLanguage.text(rawValue, englishName)
        }

        var heightRatio: Double {
            switch self {
            case .chest: return 0.75
            case .waist: return 0.55
            case .armband: return 0.65
            }
        }
    }

    /// 기본 투사 거리 계산 (키 × 장착 위치 비율로 추정)
    var estimatedProjectionDistance: Double {
        let mountHeight = Double(userHeightCm) / 100.0 * mountPosition.heightRatio
        return mountHeight / tan(max(0.1, (30.0 + laserAngleOffset) * .pi / 180.0))
    }

    static let `default` = LaserCalibration(
        userHeightCm: 170,
        mountPosition: .chest,
        laserAngleOffset: 0,
        projectionDistanceM: 2.0
    )
}

// MARK: - 음성 안내 설정

struct VoiceGuideSettings: Codable {
    var isEnabled: Bool
    var distanceInterval: Double      // km마다 안내 (0 = 비활성)
    var paceAlertThreshold: Double    // 레이저와 이 거리(m) 이상 벌어지면 경고
    var countdownAlert: Bool          // 카운트다운 음성 안내

    static let `default` = VoiceGuideSettings(
        isEnabled: false,
        distanceInterval: 1.0,
        paceAlertThreshold: 15.0,
        countdownAlert: true
    )
}

// MARK: - 게임 타입

enum GameType: String, CaseIterable {
    case heartRun = "하트런"
    case appleRun = "사과런"
    case hiFive = "HI-FIVE!"
    case roadRun = "ROAD RUN"

    var icon: String {
        switch self {
        case .heartRun: return "heart.fill"
        case .appleRun: return "apple.logo"
        case .hiFive: return "hand.raised.fill"
        case .roadRun: return "road.lanes"
        }
    }

    var color: String {
        switch self {
        case .heartRun: return "red"
        case .appleRun: return "green"
        case .hiFive: return "yellow"
        case .roadRun: return "blue"
        }
    }
}
