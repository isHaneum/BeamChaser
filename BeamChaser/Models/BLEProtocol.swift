import Foundation

// MARK: - BLE 프로토콜 정의 (HM-10 BLE 모듈 + Arduino)

enum BLEConstants {
    /// HM-10 기본 서비스 UUID
    static let serviceUUID = "0000FFE0-0000-1000-8000-00805F9B34FB"

    /// HM-10 기본 Characteristic UUID (읽기/쓰기/알림 공용)
    static let characteristicUUID = "0000FFE1-0000-1000-8000-00805F9B34FB"

    /// 장치 이름 필터
    static let deviceNamePrefix = "BeamChaser"

    /// 상태 패킷 마커 (v2.0: 12바이트)
    static let statusSTX: UInt8 = 0xAA
    static let statusETX: UInt8 = 0x55
    static let statusPacketLength = 12
}

// MARK: - 장치로 보내는 커맨드

struct LaserCommand {
    enum CommandType: UInt8 {
        case laserOff        = 0x00
        case laserOn         = 0x01
        case setPace         = 0x02  // + 2바이트 (초/km)
        case setAngle        = 0x03  // + 1바이트 (0~180도)
        case setZone         = 0x04  // + 1바이트 (0=NONE,1=BLUE,2=GREEN,3=RED)
        case startRun        = 0x05
        case stopRun         = 0x06
        case requestStatus   = 0x07
        case setDayMode      = 0x08  // + 1바이트 (0x00=OFF, 0x01=ON)
        case setSensitivity  = 0x09  // + 1바이트 (0~255, 짐벌 감도)
        case setCalibration  = 0x0A  // + 1바이트 (Int8 오프셋)
        case phoneGPS        = 0x0B  // + 19바이트 (휴대폰 GPS 실시간 패킷)
        case phoneControl    = 0x0C  // 앱 계산 기반 실시간 제어 프레임
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

    /// 짐벌 감도 설정 (0~255)
    static func setSensitivity(_ sensitivity: UInt8) -> LaserCommand {
        LaserCommand(type: .setSensitivity, payload: [sensitivity])
    }

    /// 캘리브레이션 오프셋 설정 (-90~90)
    static func setCalibration(offset: Int8) -> LaserCommand {
        LaserCommand(type: .setCalibration, payload: [UInt8(bitPattern: offset)])
    }

    /// 휴대폰 GPS 실시간 전송 패킷 (명령 포함 20바이트, 기본 BLE MTU 안전)
    static func phoneGPS(_ payload: PhoneGPSPayload) -> LaserCommand {
        var bytes: [UInt8] = []
        bytes.appendInt32(payload.latitudeE7)
        bytes.appendInt32(payload.longitudeE7)
        bytes.appendUInt16(payload.speedCentimetersPerSecond)
        bytes.appendUInt16(payload.courseCentidegrees)
        bytes.appendUInt16(payload.horizontalAccuracyCentimeters)
        bytes.appendUInt16(payload.distanceMeters)
        bytes.appendUInt16(payload.elapsedSeconds)
        bytes.append(payload.flags)
        return LaserCommand(type: .phoneGPS, payload: bytes)
    }

    /// 앱에서 계산한 속도/페이스/레이저/서보 제어 프레임
    static func phoneControl(_ payload: PhoneControlPayload) -> LaserCommand {
        var bytes: [UInt8] = []
        bytes.appendUInt16(payload.speedCentimetersPerSecond)
        bytes.appendUInt16(payload.paceSecondsPerKm)
        bytes.appendUInt16(payload.targetPaceSecondsPerKm)
        bytes.appendUInt16(payload.distanceMeters)
        bytes.appendUInt16(payload.elapsedSeconds)
        bytes.appendInt16(payload.gapCentimeters)
        bytes.append(payload.servoAngleDegrees)
        bytes.append(payload.zone.rawValue)
        bytes.append(payload.flags)
        return LaserCommand(type: .phoneControl, payload: bytes)
    }
}

// MARK: - 휴대폰 GPS 송신 페이로드

struct PhoneGPSPayload: Equatable, Sendable {
    /// latitude * 10,000,000
    let latitudeE7: Int32
    /// longitude * 10,000,000
    let longitudeE7: Int32
    /// fused/current speed in cm/s
    let speedCentimetersPerSecond: UInt16
    /// course * 100. Unknown = 0xFFFF.
    let courseCentidegrees: UInt16
    /// horizontal accuracy in cm
    let horizontalAccuracyCentimeters: UInt16
    /// app-side running distance in meters, clamped to UInt16
    let distanceMeters: UInt16
    /// current run elapsed seconds, clamped to UInt16
    let elapsedSeconds: UInt16
    /// bit0 valid fix, bit1 speed valid, bit2 course valid, bit3 stale fix
    let flags: UInt8
}

// MARK: - 앱 계산 기반 실시간 제어 페이로드

struct PhoneControlPayload: Equatable, Sendable {
    /// fused/current speed in cm/s
    let speedCentimetersPerSecond: UInt16
    /// phone-calculated current pace in seconds/km
    let paceSecondsPerKm: UInt16
    /// target pace in seconds/km. Unknown = 0.
    let targetPaceSecondsPerKm: UInt16
    /// app-side running distance in meters, clamped to UInt16
    let distanceMeters: UInt16
    /// current run elapsed seconds, clamped to UInt16
    let elapsedSeconds: UInt16
    /// pacemaker gap in centimeters. Positive means runner is ahead.
    let gapCentimeters: Int16
    /// app-calculated servo target angle, 0...180
    let servoAngleDegrees: UInt8
    /// app-calculated laser zone
    let zone: DeviceZone
    /// bit0 laserOn, bit1 dayMode, bit2 gpsValid, bit3 staleFix, bit4 speedValid
    let flags: UInt8
}

private extension Array where Element == UInt8 {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendInt32(_ value: Int32) {
        let bitPattern = UInt32(bitPattern: value)
        append(UInt8((bitPattern >> 24) & 0xFF))
        append(UInt8((bitPattern >> 16) & 0xFF))
        append(UInt8((bitPattern >> 8) & 0xFF))
        append(UInt8(bitPattern & 0xFF))
    }

    mutating func appendInt16(_ value: Int16) {
        let bitPattern = UInt16(bitPattern: value)
        appendUInt16(bitPattern)
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

// MARK: - 장치에서 받는 상태 (12바이트 패킷)

struct DeviceStatus {
    let batteryPercent: Int
    let isLaserActive: Bool
    let servoAngleDegrees: Int
    let zone: DeviceZone
    let currentPitch: Int8          // 실시간 기울기 (도)
    let paceSecondsPerKm: Int       // 장치 측 현재 페이스
    let totalDistanceMeters: Int    // 장치 측 누적 거리
    let isCharging: Bool

    /// STX(0xAA) bat laser angle zone pitch paceH paceL distH distL spare ETX(0x55)
    init(from data: Data) {
        guard data.count >= BLEConstants.statusPacketLength,
              data[0] == BLEConstants.statusSTX,
              data[data.count - 1] == BLEConstants.statusETX else {
            self.batteryPercent = 0
            self.isLaserActive = false
            self.servoAngleDegrees = 85
            self.zone = .none
            self.currentPitch = 0
            self.paceSecondsPerKm = 0
            self.totalDistanceMeters = 0
            self.isCharging = false
            return
        }
        self.batteryPercent = min(100, max(0, Int(data[1])))
        self.isLaserActive = data[2] == 0x01
        self.servoAngleDegrees = Int(data[3])
        self.zone = DeviceZone(rawValue: data[4]) ?? .none
        self.currentPitch = Int8(bitPattern: data[5])
        self.paceSecondsPerKm = (Int(data[6]) << 8) | Int(data[7])
        self.totalDistanceMeters = (Int(data[8]) << 8) | Int(data[9])
        self.isCharging = false
    }
}
