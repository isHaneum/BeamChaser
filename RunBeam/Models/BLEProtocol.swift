import Foundation

// MARK: - BLE 프로토콜 정의 (ESP32 장치와의 통신)

enum BLEConstants {
    /// 런빔 장치의 BLE 서비스 UUID (ESP32에 맞게 수정 필요)
    static let serviceUUID = "12345678-1234-1234-1234-123456789ABC"

    /// 레이저 제어 Characteristic
    static let laserControlUUID = "12345678-1234-1234-1234-123456789A01"

    /// MEMS 미러 각도 Characteristic
    static let memsAngleUUID = "12345678-1234-1234-1234-123456789A02"

    /// 장치 상태 (배터리 등) Characteristic
    static let deviceStatusUUID = "12345678-1234-1234-1234-123456789A03"

    /// 페이스 데이터 전송 Characteristic
    static let paceDataUUID = "12345678-1234-1234-1234-123456789A04"

    /// 장치 이름 필터
    static let deviceNamePrefix = "RunBeam"
}

// MARK: - 장치로 보내는 커맨드

struct LaserCommand {
    enum CommandType: UInt8 {
        case laserOff = 0x00
        case laserOn = 0x01
        case setPace = 0x02
        case setPattern = 0x03
        case setGameMode = 0x04
        case setCalibration = 0x05
    }

    let type: CommandType
    let payload: [UInt8]

    var data: Data {
        var bytes: [UInt8] = [type.rawValue]
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    // 레이저 On/Off
    static func laserOn() -> LaserCommand {
        LaserCommand(type: .laserOn, payload: [])
    }

    static func laserOff() -> LaserCommand {
        LaserCommand(type: .laserOff, payload: [])
    }

    // 목표 페이스 전송 (초/km → 2바이트)
    static func setPace(secondsPerKm: Int) -> LaserCommand {
        let high = UInt8((secondsPerKm >> 8) & 0xFF)
        let low = UInt8(secondsPerKm & 0xFF)
        return LaserCommand(type: .setPace, payload: [high, low])
    }

    // MEMS 미러 패턴 설정
    static func setPattern(_ pattern: UInt8) -> LaserCommand {
        LaserCommand(type: .setPattern, payload: [pattern])
    }

    // 캘리브레이션 데이터 전송 (각도 + 투사 거리)
    static func setCalibration(angleDegrees: Double, projectionDistance: Double) -> LaserCommand {
        let angleInt = Int16(angleDegrees * 100)
        let distInt = UInt16(projectionDistance * 100)
        return LaserCommand(type: .setCalibration, payload: [
            UInt8((angleInt >> 8) & 0xFF), UInt8(angleInt & 0xFF),
            UInt8((distInt >> 8) & 0xFF), UInt8(distInt & 0xFF),
        ])
    }
}

// MARK: - 장치에서 받는 상태

struct DeviceStatus {
    let batteryPercent: Int
    let isLaserActive: Bool
    let memsAngleDegrees: Float
    let isCharging: Bool  // 자가발전 충전 중

    init(from data: Data) {
        guard data.count >= 4 else {
            self.batteryPercent = 0
            self.isLaserActive = false
            self.memsAngleDegrees = 0
            self.isCharging = false
            return
        }
        self.batteryPercent = min(100, max(0, Int(data[0])))
        self.isLaserActive = data[1] == 0x01
        self.memsAngleDegrees = Float(Int8(bitPattern: data[2]))
        self.isCharging = data[3] == 0x01
    }
}
