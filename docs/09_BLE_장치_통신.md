# BLE 장치 통신 (BLEService + BLEProtocol)

## 파일 위치
- `BeamChaser/Services/BLEService.swift` — CoreBluetooth BLE 통신 서비스
- `BeamChaser/Models/BLEProtocol.swift` — 프로토콜 정의 (UUID, 커맨드, 상태 파싱)
- `BeamChaser/Services/beamarduino_ble.ino` — Arduino 펌웨어

---

## 하드웨어 구성

### Arduino UNO + BLE 페이스메이커
| 부품 | 연결 | 설명 |
|------|------|------|
| GPS NEO M9N | D2(RX), D3(TX) | SoftwareSerial, 9600 baud |
| HM-10 BLE | D9(RX), D10(TX) | SoftwareSerial, 9600 baud |
| 서보 MG90S | D7 | 레이저 각도 조절 (60~110°) |
| 레이저 (초록) | D4 | 적정 페이스 (기본 레이저) |
| 레이저 (빨강) | D5 | 느림 (페이스 하락 시) |
| 레이저 (파랑) | D6 | 빠름 (페이스 초과 시) |
| 버튼 | D8 | 물리 시작/정지 버튼 |

---

## BLE 프로토콜

### UUID
| 항목 | UUID |
|------|------|
| Service | `0000FFE0-0000-1000-8000-00805F9B34FB` |
| Characteristic | `0000FFE1-0000-1000-8000-00805F9B34FB` |

HM-10은 단일 Characteristic(FFE1)으로 읽기/쓰기/알림을 모두 처리합니다.

### 명령 (앱 → Arduino)

| 명령 타입 | 바이트 | 페이로드 | 설명 |
|-----------|--------|----------|------|
| `laserOff` | `0x00` | 없음 | 레이저 전체 끄기 |
| `laserOn` | `0x01` | 없음 | 레이저 전체 켜기 |
| `setPace` | `0x02` | `HH LL` (2바이트) | 목표 페이스 설정 (초/km, big-endian, 120~1200) |
| `setAngle` | `0x03` | `AA` (1바이트) | 서보 각도 직접 설정 (0~180°) |
| `setZone` | `0x04` | `ZZ` (1바이트) | Zone 설정 (0=없음, 1=파랑, 2=초록, 3=빨강) |
| `startRun` | `0x05` | 없음 | 러닝 시작 (GPS 트래킹 + 레이저 활성화) |
| `stopRun` | `0x06` | 없음 | 러닝 종료 (레이저 끄기 + 대기) |
| `requestStatus` | `0x07` | 없음 | 즉시 상태 패킷 요청 |
| `setDayMode` | `0x08` | `0x00/0x01` | 주간 점멸 모드 설정 |
| `setSensitivity` | `0x09` | `SS` (1바이트) | 짐벌 감도 설정 (0~255) |
| `setCalibration` | `0x0A` | `OO` (1바이트) | 짐벌 캘리브레이션 오프셋 설정 (Int8) |

### 상태 패킷 (Arduino → 앱)

12바이트 고정 길이 패킷:
```
[STX] [battery] [laserOn] [servo] [zone] [pitch] [pace_H] [pace_L] [dist_H] [dist_L] [spare] [ETX]
 0xAA   0-100     0/1     0-180   0-3   -90~90  big-endian(초/km)  big-endian(m)   0x00   0x55
```

| 바이트 | 필드 | 범위 | 설명 |
|--------|------|------|------|
| 0 | STX | `0xAA` | 시작 마커 |
| 1 | battery | 0~100 | 배터리 잔량 (%) |
| 2 | laserOn | 0/1 | 레이저 활성 여부 |
| 3 | servo | 0~180 | 현재 서보 각도 |
| 4 | zone | 0~3 | 현재 Zone (0=없음, 1=파랑, 2=초록, 3=빨강) |
| 5 | pitch | `Int8` | 실시간 기울기 (도) |
| 6-7 | pace | big-endian | 현재 페이스 (초/km) |
| 8-9 | distance | big-endian | 누적 거리 (m) |
| 10 | spare | `0x00` | 예약 바이트 |
| 11 | ETX | `0x55` | 종료 마커 |

---

## BLEService 클래스

### 퍼블리셔 (Published)
| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `isScanning` | `Bool` | BLE 스캔 중 여부 |
| `isConnected` | `Bool` | 장치 연결 여부 |
| `discoveredDevices` | `[CBPeripheral]` | 발견된 BLE 장치 목록 |
| `connectedDeviceName` | `String?` | 연결된 장치 이름 |
| `deviceStatus` | `DeviceStatus?` | 장치 상태 (12바이트 패킷 파싱) |
| `connectionError` | `String?` | 연결 에러 메시지 |
| `deviceZone` | `DeviceZone` | 현재 Zone |
| `servoAngle` | `Int` | 현재 서보 각도 |

### 공개 API
| 메서드 | 설명 |
|--------|------|
| `startScanning()` | FFE0 서비스 UUID로 BLE 스캔 시작 (15초 타임아웃) |
| `startScanningAll()` | UUID 필터 없이 전체 BLE 스캔 |
| `stopScanning()` | 스캔 중지 |
| `connect(to:)` | 특정 장치에 연결 |
| `disconnect()` | 연결 해제 |
| `sendCommand(_:)` | LaserCommand 전송 |
| `turnLaserOn()` | 레이저 켜기 |
| `turnLaserOff()` | 레이저 끄기 |
| `sendTargetPace(secondsPerKm:)` | 목표 페이스 전송 |
| `setServoAngle(_:)` | 서보 각도 설정 |
| `setZone(_:)` | Zone 직접 설정 |
| `startRun()` | 러닝 시작 명령 |
| `stopRun()` | 러닝 종료 명령 |
| `requestStatus()` | 상태 패킷 요청 |

### 연결 흐름
```
1. startScanning()
   ↓
2. didDiscover peripheral (discoveredDevices에 추가)
   ↓
3. connect(to: peripheral)
   ↓
4. didConnect → discoverServices(nil)
   ↓
5. didDiscoverServices → discoverCharacteristics(nil)
   ↓
6. didDiscoverCharacteristics → FFE1 찾기
   ↓
7. setNotifyValue(true) + requestStatus()
   ↓
8. didUpdateValue → parseReceivedData()
   → DeviceStatus 갱신
```

### 수신 데이터 파싱
- `receiveBuffer`에 데이터 축적
- STX(`0xAA`)를 찾아 12바이트 패킷 조립
- ETX(`0x55`) 확인 후 `DeviceStatus` 파싱
- 200바이트 초과 시 버퍼 클리어 (오버플로우 방지)

### Zone 모델
```swift
enum DeviceZone: UInt8 {
    case none  = 0  // 없음 (회색)
    case blue  = 1  // 빠름 (파랑 레이저)
    case green = 2  // 적정 (초록 레이저)
    case red   = 3  // 느림 (빨강 레이저)
}
```

---

## Arduino 펌웨어 동작

### 상태 머신
```
WAIT → RUNNING → WAIT
  ↑        ↓
  └────────┘
```

- **WAIT**: 레이저 OFF, BLE 명령 대기
- **RUNNING**: GPS 트래킹, 페이스 계산, Zone별 레이저 제어

### GPS 페이스 계산
- 매 루프마다 GPS 좌표 읽기
- Haversine 공식으로 거리 계산
- 5초 이동 평균으로 속도 산출
- 목표 페이스 대비 Zone 판정:
  - 목표 ±5% 이내 → GREEN (초록 레이저)
  - 목표보다 빠름 → BLUE (파랑 레이저)
  - 목표보다 느림 → RED (빨강 레이저)

### BLE 상태 전송
- 1초마다 12바이트 상태 패킷 전송
- BLE 명령 수신 즉시 처리 (서보 각도, Zone, 주간 모드, 짐벌 감도/영점 등)
