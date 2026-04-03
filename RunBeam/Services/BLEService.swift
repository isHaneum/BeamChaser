import Foundation
import CoreBluetooth
import Combine

/// BLE 서비스 — HM-10 BLE 모듈을 통한 Arduino RunBeam 장치 통신
@MainActor
final class BLEService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isScanning = false
    @Published var isConnected = false
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectedDeviceName: String?
    @Published var deviceStatus: DeviceStatus?
    @Published var connectionError: String?
    @Published var deviceZone: DeviceZone = .none
    @Published var servoAngle: Int = 85

    // MARK: - Private

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var mainCharacteristic: CBCharacteristic?  // HM-10은 단일 Characteristic

    private nonisolated(unsafe) let serviceUUID = CBUUID(string: BLEConstants.serviceUUID)
    private nonisolated(unsafe) let charUUID = CBUUID(string: BLEConstants.characteristicUUID)

    /// 수신 버퍼 (패킷 조립용)
    private var receiveBuffer = Data()

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
        // HM-10은 서비스 UUID로 필터링 or nil(모든 장치)
        centralManager.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.stopScanning()
        }
    }

    /// 이름 필터 없이 모든 BLE 장치 검색 (HM-10이 서비스 UUID를 advertise 안 할 경우)
    func startScanningAll() {
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

    // MARK: - 장치 제어 (명령 전송)

    func sendCommand(_ command: LaserCommand) {
        guard let characteristic = mainCharacteristic,
              let peripheral = connectedPeripheral else { return }
        let writeType: CBCharacteristicWriteType =
            characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(command.data, for: characteristic, type: writeType)
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

    /// 서보 각도 설정 (0~180도)
    func setServoAngle(_ degrees: Int) {
        servoAngle = degrees
        sendCommand(.setAngle(degrees: degrees))
    }

    /// Zone 직접 설정
    func setZone(_ zone: DeviceZone) {
        deviceZone = zone
        sendCommand(.setZone(zone))
    }

    /// 러닝 시작 명령 (Arduino 측 GPS 트래킹 + 레이저 활성화)
    func startRun() {
        sendCommand(.startRun())
    }

    /// 러닝 종료 명령
    func stopRun() {
        sendCommand(.stopRun())
    }

    /// 상태 요청
    func requestStatus() {
        sendCommand(.requestStatus())
    }

    /// 낮 점멸 모드 설정 (10Hz 깜빡임으로 주간 가시성 향상)
    func setDayMode(_ enabled: Bool) {
        sendCommand(.setDayMode(enabled))
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
        Task { @MainActor in
            isConnected = true
            connectedDeviceName = name ?? "RunBeam"
            connectionError = nil
            // HM-10은 서비스 1개만 있으므로 nil로 전체 검색 가능
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

extension BLEService: CBPeripheralDelegate {
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
                // HM-10 FFE1 or 표준 UUID 매칭
                if characteristic.uuid == targetUUID || characteristic.uuid.uuidString.contains("FFE1") {
                    mainCharacteristic = characteristic

                    // 알림 활성화 (장치 → 앱 상태 수신)
                    if characteristic.properties.contains(.notify) {
                        peripheral.setNotifyValue(true, for: characteristic)
                    }

                    // 연결 후 상태 요청
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

extension BLEService {
    /// 수신 데이터를 버퍼에 추가하고 완전한 상태 패킷을 찾아 파싱
    private func parseReceivedData(_ data: Data) {
        receiveBuffer.append(data)

        // STX(0xAA)로 시작하는 10바이트 패킷 검색
        while receiveBuffer.count >= BLEConstants.statusPacketLength {
            // STX 찾기
            guard let stxIndex = receiveBuffer.firstIndex(of: BLEConstants.statusSTX) else {
                receiveBuffer.removeAll()
                return
            }

            // STX 앞의 쓰레기 데이터 제거
            if stxIndex > receiveBuffer.startIndex {
                receiveBuffer.removeSubrange(receiveBuffer.startIndex..<stxIndex)
            }

            // 패킷 완성 확인
            guard receiveBuffer.count >= BLEConstants.statusPacketLength else { return }

            let packetData = receiveBuffer.prefix(BLEConstants.statusPacketLength)

            // ETX 확인
            if packetData[packetData.startIndex + BLEConstants.statusPacketLength - 1] == BLEConstants.statusETX {
                let status = DeviceStatus(from: Data(packetData))
                deviceStatus = status
                deviceZone = status.zone
                servoAngle = status.servoAngleDegrees
            }

            // 처리된 패킷 제거
            receiveBuffer.removeFirst(BLEConstants.statusPacketLength)
        }

        // 버퍼 오버플로우 방지 (200바이트 초과 시 정리)
        if receiveBuffer.count > 200 {
            receiveBuffer.removeAll()
        }
    }
}
