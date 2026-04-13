import Foundation
import CoreBluetooth
import Combine

/// BLE 서비스 — BeamChaser 장치 통신 (Base Class)
@MainActor
class BLEService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isScanning = false
    @Published var isConnected = false
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectedDeviceName: String?
    @Published var deviceStatus: DeviceStatus?
    @Published var connectionError: String?
    @Published var deviceZone: DeviceZone = .none
    @Published var servoAngle: Int = 85

    // MARK: - Public API (To be overridden)

    func startScanning() {}
    func startScanningAll() {}
    func stopScanning() {}
    func connect(to peripheral: CBPeripheral) {}
    func disconnect() {}

    // MARK: - 장치 제어 (명령 전송)

    func sendCommand(_ command: LaserCommand) {}
    func turnLaserOn() {}
    func turnLaserOff() {}
    func sendTargetPace(secondsPerKm: Int) {}
    func setServoAngle(_ degrees: Int) {}
    func setZone(_ zone: DeviceZone) {}
    func startRun() {}
    func stopRun() {}
    func requestStatus() {}
    func setDayMode(_ enabled: Bool) {}
}
