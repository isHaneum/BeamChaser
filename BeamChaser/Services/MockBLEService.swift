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

    override init() {
        super.init()
        print("🛠 MockBLEService 활성화됨")
    }

    override func startScanning() {
        isScanning = true
        // 1초 후 가상의 장치 발견 시뮬레이션
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.isScanning = false
            self.isConnected = true
            self.connectedDeviceName = "BeamChaser (Mock)"
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
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
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
        if isRunning {
            mockDistance += Int.random(in: 2...4)
            mockPace = Int.random(in: 320...340) // 약 5:30 페이스
            // 배터리 아주 천천히 감소
            if Int.random(in: 0...100) > 98 {
                mockBattery = max(0, mockBattery - 1)
            }
        }

        // 10바이트 가짜 패킷 생성
        // STX(0xAA) battery laserOn servoAngle zone pace_H pace_L dist_H dist_L ETX(0x55)
        var data = Data([BLEConstants.statusSTX])
        data.append(UInt8(mockBattery))
        data.append(isRunning ? 0x01 : 0x00)
        data.append(UInt8(servoAngle))
        data.append(deviceZone.rawValue)
        data.append(UInt8((mockPace >> 8) & 0xFF))
        data.append(UInt8(mockPace & 0xFF))
        data.append(UInt8((mockDistance >> 8) & 0xFF))
        data.append(UInt8(mockDistance & 0xFF))
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
        print("Mock: 목표 페이스 설정됨 -> \(secondsPerKm)s/km")
    }

    override func setServoAngle(_ degrees: Int) {
        self.servoAngle = degrees
    }

    override func setZone(_ zone: DeviceZone) {
        self.deviceZone = zone
    }

    override func startRun() {
        isRunning = true
        mockDistance = 0
    }

    override func stopRun() {
        isRunning = false
    }
}
