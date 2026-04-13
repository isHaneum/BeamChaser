import Foundation
import CoreBluetooth
import Combine

/// 실제 하드웨어와 통신하는 BLE 서비스 (iOS 전용)
@MainActor
final class ActualBLEService: BLEService {

    // MARK: - Private

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var mainCharacteristic: CBCharacteristic?

    private nonisolated(unsafe) let serviceUUID = CBUUID(string: BLEConstants.serviceUUID)
    private nonisolated(unsafe) let charUUID = CBUUID(string: BLEConstants.characteristicUUID)

    /// 수신 버퍼 (패킷 조립용)
    private var receiveBuffer = Data()

    // MARK: - Init

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API Overrides

    override func startScanning() {
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.stopScanning()
        }
    }

    override func startScanningAll() {
        guard centralManager.state == .poweredOn else {
            connectionError = "블루투스를 켜주세요"
            return
        }
        discoveredDevices.removeAll()
        isScanning = true
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.stopScanning()
        }
    }

    override func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }

    override func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    override func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    // MARK: - 장치 제어 (명령 전송)

    override func sendCommand(_ command: LaserCommand) {
        guard let characteristic = mainCharacteristic,
              let peripheral = connectedPeripheral else { return }
        let writeType: CBCharacteristicWriteType =
            characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(command.data, for: characteristic, type: writeType)
    }

    override func turnLaserOn() {
        sendCommand(.laserOn())
    }

    override func turnLaserOff() {
        sendCommand(.laserOff())
    }

    override func sendTargetPace(secondsPerKm: Int) {
        sendCommand(.setPace(secondsPerKm: secondsPerKm))
    }

    override func setServoAngle(_ degrees: Int) {
        servoAngle = degrees
        sendCommand(.setAngle(degrees: degrees))
    }

    override func setZone(_ zone: DeviceZone) {
        deviceZone = zone
        sendCommand(.setZone(zone))
    }

    override func startRun() {
        sendCommand(.startRun())
    }

    override func stopRun() {
        sendCommand(.stopRun())
    }

    override func requestStatus() {
        sendCommand(.requestStatus())
    }

    override func setDayMode(_ enabled: Bool) {
        sendCommand(.setDayMode(enabled))
    }

    override func setSensitivity(_ value: Int) {
        self.sensitivity = value
        sendCommand(.setSensitivity(UInt8(min(max(value, 0), 255))))
    }

    override func setCalibration(_ offset: Int) {
        self.calibrationOffset = offset
        sendCommand(.setCalibration(offset: Int8(min(max(offset, -90), 90))))
    }
}

// MARK: - CBCentralManagerDelegate

extension ActualBLEService: CBCentralManagerDelegate {
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
        Task { @MainActor in
            isConnected = true
            connectedDeviceName = name ?? "BeamChaser"
            connectionError = nil
            peripheral.discoverServices(nil)
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
            mainCharacteristic = nil
            deviceStatus = nil
            deviceZone = .none
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

extension ActualBLEService: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let chars = service.characteristics else { return }
        let charsCopy = Array(chars)
        let targetUUID = charUUID

        Task { @MainActor in
            for characteristic in charsCopy {
                if characteristic.uuid == targetUUID || characteristic.uuid.uuidString.contains("FFE1") {
                    mainCharacteristic = characteristic

                    if characteristic.properties.contains(.notify) {
                        peripheral.setNotifyValue(true, for: characteristic)
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.requestStatus()
                    }
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
        guard let data = characteristic.value, !data.isEmpty else { return }

        Task { @MainActor in
            parseReceivedData(data)
        }
    }
}

// MARK: - 패킷 파싱

extension ActualBLEService {
    private func parseReceivedData(_ data: Data) {
        receiveBuffer.append(data)

        while receiveBuffer.count >= BLEConstants.statusPacketLength {
            guard let stxIndex = receiveBuffer.firstIndex(of: BLEConstants.statusSTX) else {
                receiveBuffer.removeAll()
                return
            }

            if stxIndex > receiveBuffer.startIndex {
                receiveBuffer.removeSubrange(receiveBuffer.startIndex..<stxIndex)
            }

            guard receiveBuffer.count >= BLEConstants.statusPacketLength else { return }

            let packetData = receiveBuffer.prefix(BLEConstants.statusPacketLength)

            if packetData[packetData.startIndex + BLEConstants.statusPacketLength - 1] == BLEConstants.statusETX {
                let status = DeviceStatus(from: Data(packetData))
                deviceStatus = status
                deviceZone = status.zone
                servoAngle = status.servoAngleDegrees
                currentPitch = Int(status.currentPitch)
            }

            receiveBuffer.removeFirst(BLEConstants.statusPacketLength)
        }

        if receiveBuffer.count > 200 {
            receiveBuffer.removeAll()
        }
    }
}
