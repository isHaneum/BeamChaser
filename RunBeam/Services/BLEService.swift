import Foundation
import CoreBluetooth
import Combine

/// BLE 서비스 — ESP32 런빔 장치와의 블루투스 통신 관리
@MainActor
final class BLEService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isScanning = false
    @Published var isConnected = false
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectedDeviceName: String?
    @Published var deviceStatus: DeviceStatus?
    @Published var connectionError: String?

    // MARK: - Private

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var laserCharacteristic: CBCharacteristic?
    private var memsCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var paceCharacteristic: CBCharacteristic?

    private nonisolated(unsafe) let serviceUUID = CBUUID(string: BLEConstants.serviceUUID)
    private nonisolated(unsafe) let characteristicUUIDs = [
        CBUUID(string: BLEConstants.laserControlUUID),
        CBUUID(string: BLEConstants.memsAngleUUID),
        CBUUID(string: BLEConstants.deviceStatusUUID),
        CBUUID(string: BLEConstants.paceDataUUID),
    ]

    // MARK: - Init

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionError = "블루투스를 켜주세요"
            return
        }
        discoveredDevices.removeAll()
        isScanning = true
        centralManager.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // 10초 후 자동 스캔 중지
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.stopScanning()
        }
    }

    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }

    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    // MARK: - 장치 제어

    func sendCommand(_ command: LaserCommand) {
        guard let characteristic = laserCharacteristic else { return }
        connectedPeripheral?.writeValue(
            command.data,
            for: characteristic,
            type: .withResponse
        )
    }

    func turnLaserOn() {
        sendCommand(.laserOn())
    }

    func turnLaserOff() {
        sendCommand(.laserOff())
    }

    func sendTargetPace(secondsPerKm: Int) {
        sendCommand(.setPace(secondsPerKm: secondsPerKm))
    }

    func setMEMSPattern(_ pattern: UInt8) {
        sendCommand(.setPattern(pattern))
    }

    func sendCalibration(angleDegrees: Double, projectionDistance: Double) {
        sendCommand(.setCalibration(angleDegrees: angleDegrees, projectionDistance: projectionDistance))
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { @MainActor in
            switch state {
            case .poweredOn:
                connectionError = nil
            case .poweredOff:
                connectionError = "블루투스를 켜주세요"
            case .unauthorized:
                connectionError = "블루투스 권한을 허용해주세요"
            case .unsupported:
                connectionError = "이 기기는 BLE를 지원하지 않습니다"
            default:
                break
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let id = peripheral.identifier
        Task { @MainActor in
            if !discoveredDevices.contains(where: { $0.identifier == id }) {
                discoveredDevices.append(peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name
        let svcUUID = serviceUUID
        Task { @MainActor in
            isConnected = true
            connectedDeviceName = name ?? "런빔 장치"
            connectionError = nil
            peripheral.discoverServices([svcUUID])
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            isConnected = false
            connectedDeviceName = nil
            connectedPeripheral = nil
            laserCharacteristic = nil
            memsCharacteristic = nil
            statusCharacteristic = nil
            paceCharacteristic = nil
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let msg = error?.localizedDescription ?? "알 수 없는 오류"
        Task { @MainActor in
            connectionError = "연결 실패: \(msg)"
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEService: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
        let charUUIDs = characteristicUUIDs
        peripheral.discoverCharacteristics(charUUIDs, for: service)
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let chars = service.characteristics else { return }
        let charsCopy = Array(chars)

        Task { @MainActor in
            for characteristic in charsCopy {
                switch characteristic.uuid.uuidString {
                case BLEConstants.laserControlUUID:
                    laserCharacteristic = characteristic
                case BLEConstants.memsAngleUUID:
                    memsCharacteristic = characteristic
                case BLEConstants.deviceStatusUUID:
                    statusCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                case BLEConstants.paceDataUUID:
                    paceCharacteristic = characteristic
                default:
                    break
                }
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value else { return }
        let uuidString = characteristic.uuid.uuidString

        Task { @MainActor in
            if uuidString == BLEConstants.deviceStatusUUID {
                deviceStatus = DeviceStatus(from: data)
            }
        }
    }
}
