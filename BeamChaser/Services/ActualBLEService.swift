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
    private var discoveredCharacteristics: [CBCharacteristic] = []
    private var pendingCharacteristicServiceIDs = Set<String>()
    private var scanSessionID = UUID()
    private var lastTransmittedLaserState: Bool?
    private var lastTransmittedZone: DeviceZone?
    private var lastTransmittedServoAngle: Int?
    private var reconnectPeripheral: CBPeripheral?
    private var reconnectWorkItem: DispatchWorkItem?
    private var manualDisconnectRequested = false

    private nonisolated(unsafe) let serviceUUID = CBUUID(string: BLEConstants.serviceUUID)
    private nonisolated(unsafe) let charUUID = CBUUID(string: BLEConstants.characteristicUUID)
    private nonisolated(unsafe) let nordicUARTWriteUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private nonisolated(unsafe) let nordicUARTNotifyUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    /// 수신 버퍼 (패킷 조립용)
    private var receiveBuffer = Data()

    // MARK: - Init

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    private func beginScanning(withServices services: [CBUUID]?) {
        stopScanning()
        scanSessionID = UUID()
        discoveredDevices.removeAll()
        discoveredDeviceMetadata.removeAll()
        isScanningAllDevices = services == nil
        connectionError = nil
        scanHint = nil
        isScanning = true

        centralManager.scanForPeripherals(
            withServices: services,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        let currentScanSessionID = scanSessionID
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard self?.scanSessionID == currentScanSessionID else { return }
            if self?.discoveredDevices.isEmpty == true {
                self?.scanHint = AppLanguage.current.text(
                    "주변에서 BeamChaser 장치를 찾지 못했습니다. 전원을 확인하고 다시 검색해주세요.",
                    "No BeamChaser device found nearby. Check power and scan again."
                )
            }
            self?.stopScanning()
        }
    }

    // MARK: - Public API Overrides

    override func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionError = AppLanguage.current.text("블루투스를 켜주세요", "Turn on Bluetooth.")
            return
        }
        beginScanning(withServices: [serviceUUID])
    }

    override func startScanningAll() {
        guard centralManager.state == .poweredOn else {
            connectionError = AppLanguage.current.text("블루투스를 켜주세요", "Turn on Bluetooth.")
            return
        }
        beginScanning(withServices: nil)
    }

    override func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }

    override func connect(to peripheral: CBPeripheral) {
        stopScanning()
        reconnectWorkItem?.cancel()
        manualDisconnectRequested = false
        reconnectPeripheral = peripheral
        connectedPeripheral = peripheral
        peripheral.delegate = self
        discoveredCharacteristics.removeAll()
        pendingCharacteristicServiceIDs.removeAll()
        resetTransmittedCommandState()
        mainCharacteristic = nil
        activeCharacteristicUUID = nil
        isScanningAllDevices = false
        connectionError = nil
        scanHint = nil
        centralManager.connect(peripheral, options: nil)
    }

    override func disconnect() {
        manualDisconnectRequested = true
        reconnectWorkItem?.cancel()
        reconnectPeripheral = nil
        guard let peripheral = connectedPeripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    // MARK: - 장치 제어 (명령 전송)

    override func sendCommand(_ command: LaserCommand) {
        if let textCommand = textCommand(for: command) {
            sendTextCommand(textCommand)
        } else {
            sendDataCommand(command)
        }
    }

    override func turnLaserOn() {
        guard lastTransmittedLaserState != true else { return }
        lastTransmittedLaserState = true
        sendCommand(.laserOn())
    }

    override func turnLaserOff() {
        guard lastTransmittedLaserState != false else { return }
        lastTransmittedLaserState = false
        lastTransmittedZone = nil
        deviceZone = .none
        sendCommand(.laserOff())
    }

    override func sendTargetPace(secondsPerKm: Int) {
        sendCommand(.setPace(secondsPerKm: secondsPerKm))
    }

    override func setServoAngle(_ degrees: Int) {
        let clampedDegrees = min(max(degrees, 60), 110)
        servoAngle = clampedDegrees

        guard lastTransmittedServoAngle != clampedDegrees else { return }
        lastTransmittedServoAngle = clampedDegrees
        sendCommand(.setAngle(degrees: clampedDegrees))
    }

    override func setZone(_ zone: DeviceZone) {
        deviceZone = zone

        guard zone != .none else {
            lastTransmittedZone = nil
            return
        }

        guard lastTransmittedZone != zone else { return }
        lastTransmittedZone = zone
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
        isDayModeEnabled = enabled
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

    override func sendPhoneGPS(_ payload: PhoneGPSPayload) {
        let command = LaserCommand.phoneGPS(payload)
        lastPhoneGPSPayload = payload
        lastPhoneGPSCommandHex = command.data.hexString
        sendCommand(command)
    }

    override func sendPhoneControl(_ payload: PhoneControlPayload) {
        let command = LaserCommand.phoneControl(payload)
        lastPhoneControlPayload = payload
        lastPhoneControlCommandHex = command.data.hexString
        sendCommand(command)

        let laserEnabled = (payload.flags & (1 << 0)) != 0
        guard laserEnabled else {
            turnLaserOff()
            return
        }

        turnLaserOn()
        setServoAngle(Int(payload.servoAngleDegrees))
        setZone(payload.zone)
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
                reconnectIfNeeded()
            case .poweredOff:
                reconnectWorkItem?.cancel()
                connectionError = AppLanguage.current.text("블루투스를 켜주세요", "Turn on Bluetooth.")
            case .resetting:
                reconnectWorkItem?.cancel()
                connectionError = AppLanguage.current.text(
                    "블루투스가 재설정되는 중입니다. 잠시 후 자동으로 다시 연결합니다.",
                    "Bluetooth is resetting. The app will try to reconnect shortly."
                )
            case .unauthorized:
                reconnectWorkItem?.cancel()
                connectionError = AppLanguage.current.text("블루투스 권한을 허용해주세요", "Allow Bluetooth access.")
            case .unsupported:
                reconnectWorkItem?.cancel()
                connectionError = AppLanguage.current.text("이 기기는 BLE를 지원하지 않습니다", "This device does not support BLE.")
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
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let overflowServiceUUIDs = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []
        let allAdvertisedServiceUUIDs = serviceUUIDs + overflowServiceUUIDs
        let metadata = BLEDiscoveredDeviceMetadata(
            localName: localName,
            rssi: RSSI.intValue,
            advertisedServiceUUIDs: allAdvertisedServiceUUIDs.map(\.uuidString)
        )
        Task { @MainActor in
            discoveredDeviceMetadata[id] = metadata
            if !discoveredDevices.contains(where: { $0.identifier == id }) {
                discoveredDevices.append(peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name
        Task { @MainActor in
            reconnectWorkItem?.cancel()
            reconnectPeripheral = peripheral
            manualDisconnectRequested = false
            isConnected = true
            connectedDeviceName = name ?? "BeamChaser"
            connectionError = nil
            scanHint = nil
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            let shouldReconnect = !manualDisconnectRequested
            isConnected = false
            connectedDeviceName = nil
            connectedPeripheral = nil
            resetTransmittedCommandState()
            mainCharacteristic = nil
            activeCharacteristicUUID = nil
            lastReceivedPacketHex = nil
            lastSentCommandHex = nil
            lastPhoneGPSCommandHex = nil
            lastPhoneControlCommandHex = nil
            discoveredCharacteristics.removeAll()
            pendingCharacteristicServiceIDs.removeAll()
            deviceStatus = nil
            deviceZone = .none
            isScanningAllDevices = false

            if shouldReconnect {
                connectionError = AppLanguage.current.text(
                    "장치 연결이 끊어졌습니다. 자동으로 다시 연결합니다.",
                    "The device disconnected. Reconnecting automatically."
                )
                reconnectPeripheral = peripheral
                scheduleReconnect(to: peripheral)
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let msg = error?.localizedDescription ?? AppLanguage.current.text("알 수 없는 오류", "Unknown error")
        Task { @MainActor in
            connectionError = AppLanguage.current.text("연결 실패: \(msg)", "Connection failed: \(msg)")
            if !manualDisconnectRequested {
                reconnectPeripheral = peripheral
                scheduleReconnect(to: peripheral, delay: 2.0)
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension ActualBLEService: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            let msg = error.localizedDescription
            Task { @MainActor in
                connectionError = AppLanguage.current.text("서비스 검색 실패: \(msg)", "Service discovery failed: \(msg)")
            }
            return
        }

        guard let services = peripheral.services, !services.isEmpty else {
            Task { @MainActor in
                connectionError = AppLanguage.current.text(
                    "BLE 서비스를 찾지 못했습니다. ESP32-S3 펌웨어의 service UUID를 확인해주세요.",
                    "No BLE services were found. Check the ESP32-S3 service UUID."
                )
            }
            return
        }

        let serviceIDs = Set(services.map(\.uuid.uuidString))
        Task { @MainActor in
            discoveredCharacteristics.removeAll()
            pendingCharacteristicServiceIDs = serviceIDs

            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let serviceID = service.uuid.uuidString
        let charsCopy = Array(service.characteristics ?? [])
        let errorMessage = error?.localizedDescription

        Task { @MainActor in
            if let errorMessage {
                connectionError = AppLanguage.current.text(
                    "Characteristic 검색 실패: \(errorMessage)",
                    "Characteristic discovery failed: \(errorMessage)"
                )
            }

            discoveredCharacteristics.append(contentsOf: charsCopy)
            pendingCharacteristicServiceIDs.remove(serviceID)

            if pendingCharacteristicServiceIDs.isEmpty {
                configureDiscoveredCharacteristics(for: peripheral)
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

// MARK: - Characteristic Selection

extension ActualBLEService {
    private func reconnectIfNeeded() {
        guard let peripheral = reconnectPeripheral,
              !manualDisconnectRequested,
              !isConnected,
              centralManager.state == .poweredOn else { return }
        scheduleReconnect(to: peripheral, delay: 0.3)
    }

    private func scheduleReconnect(to peripheral: CBPeripheral, delay: TimeInterval = 1.5) {
        reconnectWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.manualDisconnectRequested,
                  !self.isConnected,
                  self.centralManager.state == .poweredOn else { return }

            self.connectedPeripheral = peripheral
            peripheral.delegate = self
            self.centralManager.connect(peripheral, options: nil)
        }

        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func configureDiscoveredCharacteristics(for peripheral: CBPeripheral) {
        guard mainCharacteristic == nil else { return }

        let writeCandidates = discoveredCharacteristics
            .filter(isWritableCharacteristic)
            .sorted { writePriority($0) > writePriority($1) }

        guard let writeCharacteristic = writeCandidates.first else {
            connectionError = AppLanguage.current.text(
                "쓰기 가능한 BLE characteristic을 찾지 못했습니다. nRF Connect에서 ESP32-S3의 Write 속성과 UUID를 확인해주세요.",
                "No writable BLE characteristic was found. Check the ESP32-S3 Write property and UUID in nRF Connect."
            )
            return
        }

        mainCharacteristic = writeCharacteristic
        activeCharacteristicUUID = writeCharacteristic.uuid.uuidString
        connectionError = nil

        let notifyCandidates = discoveredCharacteristics
            .filter(isNotifiableCharacteristic)
            .sorted { notifyPriority($0) > notifyPriority($1) }
            .reduce(into: [CBCharacteristic]()) { unique, characteristic in
                if !unique.contains(where: { $0.uuid == characteristic.uuid }) {
                    unique.append(characteristic)
                }
            }

        notifyCandidates.prefix(3).forEach { characteristic in
            peripheral.setNotifyValue(true, for: characteristic)
        }

        scanHint = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.requestStatus()
        }
    }

    private func sendTextCommand(_ command: String) {
        guard let characteristic = mainCharacteristic,
              let peripheral = connectedPeripheral,
              let data = command.data(using: .utf8) else {
            connectionError = AppLanguage.current.text(
                "쓰기 가능한 BLE 특성을 아직 찾지 못했습니다. nRF Connect에서 characteristic UUID를 확인해주세요.",
                "No writable BLE characteristic is ready yet. Check the characteristic UUID in nRF Connect."
            )
            return
        }

        connectionError = nil
        lastSentCommandHex = command

        let writeType: CBCharacteristicWriteType =
            characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: writeType)
    }

    private func sendDataCommand(_ command: LaserCommand) {
        guard let characteristic = mainCharacteristic,
              let peripheral = connectedPeripheral else {
            connectionError = AppLanguage.current.text(
                "쓰기 가능한 BLE 특성을 아직 찾지 못했습니다. nRF Connect에서 characteristic UUID를 확인해주세요.",
                "No writable BLE characteristic is ready yet. Check the characteristic UUID in nRF Connect."
            )
            return
        }

        let data = command.data
        connectionError = nil
        lastSentCommandHex = data.hexString

        let writeType: CBCharacteristicWriteType =
            characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: writeType)
    }

    private func textCommand(for command: LaserCommand) -> String? {
        switch command.type {
        case .laserOff:
            return "OFF"
        case .laserOn:
            return "ON"
        case .setAngle:
            guard let degrees = command.payload.first else { return nil }
            return "ANGLE:\(Int(degrees))"
        case .setZone:
            guard let rawValue = command.payload.first,
                  let zone = DeviceZone(rawValue: rawValue) else {
                return nil
            }

            switch zone {
            case .blue:
                return "COLOR:BLUE"
            case .green:
                return "COLOR:GREEN"
            case .red:
                return "COLOR:RED"
            case .none:
                return nil
            }
        case .startRun:
            return "ON"
        case .stopRun:
            return "OFF"
        case .requestStatus:
            return "STATUS"
        case .setPace, .setDayMode, .setSensitivity, .setCalibration, .phoneGPS, .phoneControl:
            return nil
        }
    }

    private func resetTransmittedCommandState() {
        lastTransmittedLaserState = nil
        lastTransmittedZone = nil
        lastTransmittedServoAngle = nil
    }

    private func isWritableCharacteristic(_ characteristic: CBCharacteristic) -> Bool {
        characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)
    }

    private func isNotifiableCharacteristic(_ characteristic: CBCharacteristic) -> Bool {
        characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)
    }

    private func writePriority(_ characteristic: CBCharacteristic) -> Int {
        if characteristic.uuid == charUUID { return 100 }
        if characteristic.uuid == nordicUARTWriteUUID { return 90 }
        if characteristic.uuid.uuidString.uppercased().contains("FFE1") { return 80 }
        return 10
    }

    private func notifyPriority(_ characteristic: CBCharacteristic) -> Int {
        if characteristic.uuid == charUUID { return 100 }
        if characteristic.uuid == nordicUARTNotifyUUID { return 90 }
        if characteristic.uuid.uuidString.uppercased().contains("FFE1") { return 80 }
        return 10
    }
}

// MARK: - 패킷 파싱

extension ActualBLEService {
    private func parseReceivedData(_ data: Data) {
        lastReceivedPacketHex = data.hexString
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

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
