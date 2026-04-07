import Foundation

// MARK: - BLE 프로토콜 정의 (HM-10 BLE 모듈 + Arduino)

enum BLEConstants {
    /// HM-10 기본 서비스 UUID
    static let serviceUUID = "0000FFE0-0000-1000-8000-00805F9B34FB"

    /// HM-10 기본 Characteristic UUID (읽기/쓰기/알림 공용)
    static let characteristicUUID = "0000FFE1-0000-1000-8000-00805F9B34FB"

    /// 장치 이름 필터
    static let deviceNamePrefix = "BeamChaser"

    /// 상태 패킷 마커
    static let statusSTX: UInt8 = 0xAA
    static let statusETX: UInt8 = 0x55
    static let statusPacketLength = 10
}

// MARK: - 장치로 보내는 커맨드

struct LaserCommand {
    enum CommandType: UInt8 {
        case laserOff      = 0x00
        case laserOn       = 0x01
        case setPace       = 0x02  // + 2바이트 (초/km)
        case setAngle      = 0x03  // + 1바이트 (0~180도)
        case setZone       = 0x04  // + 1바이트 (0=NONE,1=BLUE,2=GREEN,3=RED)
        case startRun      = 0x05
        case stopRun       = 0x06
        case requestStatus = 0x07
        case setDayMode    = 0x08  // + 1바이트 (0x00=OFF, 0x01=ON)
    }

    let type: CommandType
    let payload: [UInt8]

    var data: Data {
        var bytes: [UInt8] = [type.rawValue]
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    static func laserOn() -> LaserCommand {
        LaserCommand(type: .laserOn, payload: [])
    }

    static func laserOff() -> LaserCommand {
        LaserCommand(type: .laserOff, payload: [])
    }

    /// 목표 페이스 전송 (초/km → 2바이트 big-endian)
    static func setPace(secondsPerKm: Int) -> LaserCommand {
        let clamped = min(max(secondsPerKm, 120), 1200)
        let high = UInt8((clamped >> 8) & 0xFF)
        let low = UInt8(clamped & 0xFF)
        return LaserCommand(type: .setPace, payload: [high, low])
    }

    /// 서보 각도 직접 설정 (0~180도)
    static func setAngle(degrees: Int) -> LaserCommand {
        let clamped = UInt8(min(max(degrees, 0), 180))
        return LaserCommand(type: .setAngle, payload: [clamped])
    }

    /// Zone 직접 설정 (0=NONE, 1=BLUE, 2=GREEN, 3=RED)
    static func setZone(_ zone: DeviceZone) -> LaserCommand {
        LaserCommand(type: .setZone, payload: [zone.rawValue])
    }

    /// 러닝 시작 명령 (Arduino GPS 트래킹 + 레이저 활성화)
    static func startRun() -> LaserCommand {
        LaserCommand(type: .startRun, payload: [])
    }

    /// 러닝 종료 명령 (레이저 끄기 + WAIT 복귀)
    static func stopRun() -> LaserCommand {
        LaserCommand(type: .stopRun, payload: [])
    }

    /// 낮 점멸 모드 설정 (10Hz 깜빡임으로 주간 가시성 향상)
    static func setDayMode(_ enabled: Bool) -> LaserCommand {
        LaserCommand(type: .setDayMode, payload: [enabled ? 0x01 : 0x00])
    }

    /// 상태 즉시 요청
    static func requestStatus() -> LaserCommand {
        LaserCommand(type: .requestStatus, payload: [])
    }
}

// MARK: - 장치 Zone

enum DeviceZone: UInt8 {
    case none  = 0
    case blue  = 1  // 빠름 (파랑 레이저)
    case green = 2  // 적정 (초록 레이저)
    case red   = 3  // 느림 (빨강 레이저)

    var label: String {
        switch self {
        case .none:  return "없음"
        case .blue:  return "빠름"
        case .green: return "적정"
        case .red:   return "느림"
        }
    }

    var colorName: String {
        switch self {
        case .none:  return "gray"
        case .blue:  return "blue"
        case .green: return "green"
        case .red:   return "red"
        }
    }
}

// MARK: - 장치에서 받는 상태 (10바이트 패킷)

struct DeviceStatus {
    let batteryPercent: Int
    let isLaserActive: Bool
    let servoAngleDegrees: Int
    let zone: DeviceZone
    let paceSecondsPerKm: Int       // 장치 측 현재 페이스
    let totalDistanceMeters: Int    // 장치 측 누적 거리
    let isCharging: Bool

    /// STX(0xAA) battery laserOn servoAngle zone pace_H pace_L dist_H dist_L ETX(0x55)
    init(from data: Data) {
        guard data.count >= BLEConstants.statusPacketLength,
              data[0] == BLEConstants.statusSTX,
              data[data.count - 1] == BLEConstants.statusETX else {
            self.batteryPercent = 0
            self.isLaserActive = false
            self.servoAngleDegrees = 85
            self.zone = .none
            self.paceSecondsPerKm = 0
            self.totalDistanceMeters = 0
            self.isCharging = false
            return
        }
        self.batteryPercent = min(100, max(0, Int(data[1])))
        self.isLaserActive = data[2] == 0x01
        self.servoAngleDegrees = Int(data[3])
        self.zone = DeviceZone(rawValue: data[4]) ?? .none
        self.paceSecondsPerKm = (Int(data[5]) << 8) | Int(data[6])
        self.totalDistanceMeters = (Int(data[7]) << 8) | Int(data[8])
        self.isCharging = false  // Arduino 배터리 충전 감지 없음
    }
}
