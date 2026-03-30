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

    var averagePaceSecondsPerKm: Double {
        guard totalDistanceMeters > 0 else { return 0 }
        return elapsedSeconds / (totalDistanceMeters / 1000.0)
    }

    var formattedDistance: String {
        String(format: "%.2f km", totalDistanceMeters / 1000.0)
    }

    var formattedPace: String {
        Self.formatPace(averagePaceSecondsPerKm)
    }

    var formattedDuration: String {
        Self.formatDuration(elapsedSeconds)
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

// MARK: - GPS 좌표 포인트

struct RoutePoint: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let timestamp: Date
    let speed: Double          // m/s
    let horizontalAccuracy: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(from location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.timestamp = location.timestamp
        self.speed = max(0, location.speed)
        self.horizontalAccuracy = location.horizontalAccuracy
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

    var icon: String {
        switch self {
        case .none: return "infinity"
        case .distance: return "flag.checkered"
        case .time: return "timer"
        }
    }
}

struct RunGoal: Codable {
    let type: RunGoalType
    let targetDistanceKm: Double?     // 목표 거리 (km)
    let targetTimeMinutes: Int?       // 목표 시간 (분)

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
