import Foundation
import CoreBluetooth
import Combine

/// 하드웨어 없이 작동하는 가상 BLE 서비스 (개발/테스트용)
@MainActor
final class MockBLEService: BLEService {

    private var statusTimer: Timer?
    private var mockBattery: Int = 85
    private var mockPace: Int = 0
    private var mockDistance: Int = 0
    private var isRunning: Bool = false
    
    // 시뮬레이션용 시간축
    private var timeStep: Double = 0

    override init() {
        super.init()
        print("🛠 MockBLEService v2.0 활성화됨")
        // 기본값 설정
        self.sensitivity = 128
        self.calibrationOffset = 0
    }

    override func startScanning() {
        isScanning = true
        // 1초 후 가상의 장치 발견 시뮬레이션
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.isScanning = false
            self.isConnected = true
            self.connectedDeviceName = "BeamChaser (Mock v2.0)"
            self.startStatusSimulation()
        }
    }

    override func disconnect() {
        stopStatusSimulation()
        isConnected = false
        connectedDeviceName = nil
    }

    // MARK: - 시뮬레이션 로직

    private func startStatusSimulation() {
        statusTimer?.invalidate()
        // 100ms 주기로 업데이트 (실시간 수평계 및 부드러운 짐벌 시뮬레이션)
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMockStatus()
            }
        }
    }

    private func stopStatusSimulation() {
        statusTimer?.invalidate()
        statusTimer = nil
    }

    private func updateMockStatus() {
        timeStep += 0.1
        
        if isRunning {
            // 1초마다 거리/페이스 업데이트 (10번에 한 번)
            if Int(timeStep * 10) % 10 == 0 {
                mockDistance += Int.random(in: 2...4)
                mockPace = Int.random(in: 320...340) // 약 5:30 페이스
                if Int.random(in: 0...100) > 98 {
                    mockBattery = max(0, mockBattery - 1)
                }
            }
        }

        // 실시간 기울기 시뮬레이션 (Sine 함수 활용)
        // 러너의 상체 흔들림: -10 ~ +10도 사이 진동
        let basePitch = sin(timeStep * 2.5) * 8.0 
        let noise = Double.random(in: -0.5...0.5)
        self.currentPitch = Int(basePitch + noise)

        // 짐벌 보정 시뮬레이션
        // Servo = Base(85) - (Pitch * Sensitivity_Ratio) + Offset
        let sensitivityRatio = Double(self.sensitivity) / 128.0
        let baseAngle: Double = 85.0
        let correction = Double(self.currentPitch) * sensitivityRatio
        let finalAngle = baseAngle - correction + Double(self.calibrationOffset)
        self.servoAngle = Int(min(max(finalAngle, 0), 180))

        // 12바이트 가짜 패킷 생성
        // STX bat laser angle zone pitch paceH paceL distH distL spare ETX
        var data = Data([BLEConstants.statusSTX])
        data.append(UInt8(mockBattery))
        data.append(isRunning ? 0x01 : 0x00)
        data.append(UInt8(self.servoAngle))
        data.append(self.deviceZone.rawValue)
        data.append(UInt8(bitPattern: Int8(self.currentPitch))) // Pitch (Int8)
        data.append(UInt8((mockPace >> 8) & 0xFF))
        data.append(UInt8(mockPace & 0xFF))
        data.append(UInt8((mockDistance >> 8) & 0xFF))
        data.append(UInt8(mockDistance & 0xFF))
        data.append(0x00) // Spare
        data.append(BLEConstants.statusETX)

        self.deviceStatus = DeviceStatus(from: data)
    }

    // MARK: - Command Overrides

    override func turnLaserOn() {
        isRunning = true
    }

    override func turnLaserOff() {
        isRunning = false
    }

    override func sendTargetPace(secondsPerKm: Int) {
        print("Mock: 목표 페이스 설정 -> \(secondsPerKm)s/km")
    }

    override func setServoAngle(_ degrees: Int) {
        self.servoAngle = degrees
    }

    override func setZone(_ zone: DeviceZone) {
        self.deviceZone = zone
    }

    override func setDayMode(_ enabled: Bool) {
        isDayModeEnabled = enabled
    }

    override func startRun() {
        isRunning = true
        mockDistance = 0
    }

    override func stopRun() {
        isRunning = false
    }

    override func setSensitivity(_ value: Int) {
        self.sensitivity = value
        print("Mock: 짐벌 감도 설정 -> \(value)")
    }

    override func setCalibration(_ offset: Int) {
        self.calibrationOffset = offset
        print("Mock: 캘리브레이션 오프셋 설정 -> \(offset)")
    }

    override func sendPhoneGPS(_ payload: PhoneGPSPayload) {
        let command = LaserCommand.phoneGPS(payload)
        lastPhoneGPSPayload = payload
        lastPhoneGPSCommandHex = command.data.hexString
        lastSentCommandHex = command.data.hexString
    }

    override func sendPhoneControl(_ payload: PhoneControlPayload) {
        let command = LaserCommand.phoneControl(payload)
        lastPhoneControlPayload = payload
        lastPhoneControlCommandHex = command.data.hexString
        lastSentCommandHex = command.data.hexString
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
