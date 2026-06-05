import Foundation
import CoreBluetooth
import Combine

struct BLEDiscoveredDeviceMetadata: Sendable {
    let localName: String?
    let rssi: Int
    let advertisedServiceUUIDs: [String]

    var displayName: String? {
        localName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? localName : nil
    }
}

/// BLE 서비스 — BeamChaser 장치 통신 (Base Class)
@MainActor
class BLEService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isScanning = false
    @Published var isScanningAllDevices = false
    @Published var isConnected = false
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var discoveredDeviceMetadata: [UUID: BLEDiscoveredDeviceMetadata] = [:]
    @Published var connectedDeviceName: String?
    @Published var deviceStatus: DeviceStatus?
    @Published var connectionError: String?
    @Published var scanHint: String?
    @Published var deviceZone: DeviceZone = .none
    @Published var servoAngle: Int = 85
    @Published var currentPitch: Int = 0        // 실시간 기울기 (도)
    @Published var sensitivity: Int = 128       // 짐벌 감도 (0~255)
    @Published var calibrationOffset: Int = 0   // 캘리브레이션 오프셋 (-90~90)
    @Published var isDayModeEnabled = false
    @Published var activeCharacteristicUUID: String?
    @Published var lastSentCommandHex: String?
    @Published var lastReceivedPacketHex: String?
    @Published var lastPhoneGPSPayload: PhoneGPSPayload?
    @Published var lastPhoneControlPayload: PhoneControlPayload?
    @Published var lastPhoneGPSCommandHex: String?
    @Published var lastPhoneControlCommandHex: String?

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
    func setSensitivity(_ value: Int) {}
    func setCalibration(_ offset: Int) {}
    func sendPhoneGPS(_ payload: PhoneGPSPayload) {}
    func sendPhoneControl(_ payload: PhoneControlPayload) {}
}
