/*
 * ================================================================
 *  BeamChaser BLE v2.0 — Gimbal Optimized Version
 *
 *  [주요 개선 사항]
 *  1. MPU6050 (IMU) 통합: 실시간 6축 센싱 및 짐벌 보정
 *  2. 100Hz 실시간 제어: 시분할 멀티태스킹으로 GPS 지연 제거
 *  3. v2.0 프로토콜: 12바이트 패킷 (실시간 Pitch 포함)
 *  4. 동적 설정: 앱을 통한 짐벌 감도 및 영점 조절
 *
 *  [앱 명령 (v2.0)]
 *    0x00: Laser OFF, 0x01: Laser ON
 *    0x02 HH LL: Set Pace (s/km)
 *    0x03 AA: Set Servo Angle (Direct)
 *    0x04 ZZ: Set Zone (0:None, 1:Blue, 2:Green, 3:Red)
 *    0x05: Start Run, 0x06: Stop Run
 *    0x08 MM: Day Mode (0:OFF, 1:ON)
 *    0x09 SS: Set Gimbal Sensitivity (0~255)
 *    0x0A OO: Set Calibration Offset (Int8)
 *    0x0B [19B]: Phone GPS Telemetry (big-endian binary frame)
 *    0x0C [15B]: Phone Control Frame (big-endian binary frame)
 *
 *  [하드웨어]
 *   - MPU6050: I2C (SDA:A4, SCL:A5)
 *   - GPS: NEO M9N (D2, D3)
 *   - BLE: HM-10 (D9, D10)
 *   - Servo: MG90S (D7)
 * ================================================================
 */

#include <Wire.h>

#if defined(ARDUINO_ARCH_ESP32) || defined(ESP32)
#include <HardwareSerial.h>

class BeamServo {
public:
    bool attached() const { return attached_; }

    void attach(int pin) {
        pin_ = pin;
        attached_ = true;
    }

    void write(int angle) {
        angle_ = constrain(angle, 0, 180);
    }

    int read() const { return angle_; }

private:
    int pin_ = -1;
    int angle_ = 85;
    bool attached_ = false;
};
#else
#include <Servo.h>
#include <SoftwareSerial.h>
using BeamServo = Servo;
#endif

// ─────────── 핀 정의 ───────────
static const uint8_t GPS_RX = 2;
static const uint8_t GPS_TX = 3;
static const uint8_t BLE_RX = 9;
static const uint8_t BLE_TX = 10;

static const uint8_t LASER_BASE_PIN = 4;  // 초록
static const uint8_t LASER_SLOW_PIN = 5;  // 빨강
static const uint8_t LASER_FAST_PIN = 6;  // 파랑
static const uint8_t SERVO_PIN      = 7;
static const uint8_t SWITCH_PIN     = 8;

// ─────────── 라이브러리 객체 ───────────
#if defined(ARDUINO_ARCH_ESP32) || defined(ESP32)
HardwareSerial gpsSS(1);
HardwareSerial bleSS(2);
#else
SoftwareSerial gpsSS(GPS_RX, GPS_TX);
SoftwareSerial bleSS(BLE_RX, BLE_TX);
#endif
BeamServo servoTilt;

// ─────────── IMU (MPU6050) ───────────
const int MPU_ADDR = 0x68;
float accAngleX = 0, gyroAngleX = 0;
float currentPitch = 0;
uint32_t lastIMUTime = 0;

// ─────────── 짐벌 설정 ───────────
uint8_t  sensitivity = 128;   // 0~255 (기본 128 = 1.0배)
int8_t   calibrationOffset = 0;
float    base_angle = 85.0f;  // 페이스에 따른 기준 각도

// ─────────── BLE 프로토콜 ───────────
#define CMD_LASER_OFF      0x00
#define CMD_LASER_ON       0x01
#define CMD_SET_PACE       0x02
#define CMD_SET_ANGLE      0x03
#define CMD_SET_ZONE       0x04
#define CMD_START_RUN      0x05
#define CMD_STOP_RUN       0x06
#define CMD_REQUEST_STATUS 0x07
#define CMD_SET_DAY_MODE   0x08
#define CMD_SET_SENSITIVITY 0x09
#define CMD_SET_CALIBRATION 0x0A
#define CMD_PHONE_GPS      0x0B
#define CMD_PHONE_CONTROL  0x0C

#define PHONE_GPS_PAYLOAD_LEN 19
#define PHONE_CONTROL_PAYLOAD_LEN 15

#define STATUS_STX 0xAA
#define STATUS_ETX 0x55

// ─────────── 상태 관리 ───────────
enum Mode { WAIT_SWITCH, PACE_TRACK };
Mode mode = WAIT_SWITCH;
enum Zone { ZONE_NONE = 0, ZONE_BLUE = 1, ZONE_GREEN = 2, ZONE_RED = 3 };
Zone currentZone = ZONE_NONE;

bool laserEnabled = false;
bool dayMode      = false;
bool appControlled = false;

struct PhoneGPSFrame {
    int32_t latitudeE7;
    int32_t longitudeE7;
    uint16_t speedCmS;
    uint16_t courseCentidegrees;
    uint16_t accuracyCm;
    uint16_t distanceMeters;
    uint16_t elapsedSeconds;
    uint8_t flags;
};

struct PhoneControlFrame {
    uint16_t speedCmS;
    uint16_t paceSecondsPerKm;
    uint16_t targetPaceSecondsPerKm;
    uint16_t distanceMeters;
    uint16_t elapsedSeconds;
    int16_t gapCentimeters;
    uint8_t servoAngleDegrees;
    uint8_t zone;
    uint8_t flags;
};

PhoneGPSFrame lastPhoneGPS = {0, 0, 0, 0, 0, 0, 0, 0};
PhoneControlFrame lastPhoneControl = {0, 0, 0, 0, 0, 0, 0, 0, 0};

// ─────────── 페이스/거리 데이터 ───────────
int targetPace_skm = 420;
float filteredPace_skm = 1e6;
double totalDist_m = 0;
uint32_t runStart_ms = 0;

// ─────────── 타이머 ───────────
uint32_t lastGpsUpdate = 0;
uint32_t lastBleUpdate = 0;
uint32_t lastStatusSend = 0;

#if defined(ARDUINO_ARCH_ESP32) || defined(ESP32)
static const int IMU_SDA_PIN = 21;
static const int IMU_SCL_PIN = 22;

inline void bleListen() {}
inline void beginGPSSerial() {
    gpsSS.begin(38400, SERIAL_8N1, GPS_RX, GPS_TX);
}
inline void beginBLESerial() {
    bleSS.begin(9600, SERIAL_8N1, BLE_RX, BLE_TX);
}
#else
inline void bleListen() {
    bleSS.listen();
}
inline void beginGPSSerial() {
    gpsSS.begin(38400);
}
inline void beginBLESerial() {
    bleSS.begin(9600);
}
#endif

// ================================================================
//  IMU (MPU6050) 초기화 및 읽기
// ================================================================
void setupIMU() {
    #if defined(ARDUINO_ARCH_ESP32) || defined(ESP32)
    Wire.begin(IMU_SDA_PIN, IMU_SCL_PIN);
    #else
    Wire.begin();
    #endif
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(0x6B); // PWR_MGMT_1
    Wire.write(0);    // wake up
    Wire.endTransmission(true);
    Wire.setClock(400000L); // I2C 속도 업그레이드
}

void updateIMU() {
    uint32_t now = millis();
    if (lastIMUTime == 0) {
        lastIMUTime = now;
        return;
    }

    float dt = (now - lastIMUTime) / 1000.0f;
    lastIMUTime = now;

    Wire.beginTransmission(MPU_ADDR);
    Wire.write(0x3B); // AccelX
    Wire.endTransmission(false);
    Wire.requestFrom(MPU_ADDR, 6, true);

    int16_t accX = Wire.read() << 8 | Wire.read();
    int16_t accY = Wire.read() << 8 | Wire.read();
    int16_t accZ = Wire.read() << 8 | Wire.read();

    // Pitch 계산 (앞뒤 기울기)
    float accPitch = atan2(accY, sqrt(pow(accX, 2) + pow(accZ, 2))) * 180 / PI;

    Wire.beginTransmission(MPU_ADDR);
    Wire.write(0x43); // GyroX
    Wire.endTransmission(false);
    Wire.requestFrom(MPU_ADDR, 2, true);
    int16_t gyroX = Wire.read() << 8 | Wire.read();
    float gyroRateX = gyroX / 131.0f;

    // Complementary Filter: 노이즈 제거 및 드리프트 방지
    currentPitch = 0.96f * (currentPitch + gyroRateX * dt) + 0.04f * accPitch;
}

// ================================================================
//  짐벌 제어 루프
// ================================================================
void updateGimbal() {
    float sensRatio = sensitivity / 128.0f;
    // 보정값 = -(기울기 * 감도) + 오프셋
    float correction = -(currentPitch * sensRatio) + calibrationOffset;
    float finalAngle = base_angle + correction;
    
    finalAngle = constrain(finalAngle, 45, 135); // 물리적 한계 보호

    if (!servoTilt.attached()) {
        servoTilt.attach(SERVO_PIN);
    }
    servoTilt.write((int)finalAngle);
}

// ================================================================
//  v2.0 BLE 상태 전송 (12바이트)
//  [STX, bat, laser, angle, zone, pitch, paceH, paceL, distH, distL, spare, ETX]
// ================================================================
void sendBLEStatus() {
    uint8_t battery = 85; // 임시 (analogRead 생략)
    uint8_t laser   = laserEnabled ? 1 : 0;
    uint8_t angle   = (uint8_t)servoTilt.read();
    uint8_t zone    = (uint8_t)currentZone;
    int8_t  pitch   = (int8_t)constrain(currentPitch, -90, 90);

    uint16_t pace = (filteredPace_skm < 1e5) ? (uint16_t)filteredPace_skm : 0;
    uint16_t dist = (totalDist_m < 65535) ? (uint16_t)totalDist_m : 65535;

    uint8_t packet[12] = {
        STATUS_STX, battery, laser, angle, zone, (uint8_t)pitch,
        (uint8_t)(pace >> 8), (uint8_t)(pace & 0xFF),
        (uint8_t)(dist >> 8), (uint8_t)(dist & 0xFF),
        0x00, STATUS_ETX
    };

    bleListen();
    bleSS.write(packet, 12);
}

uint16_t readUInt16BE(const uint8_t* bytes) {
    return ((uint16_t)bytes[0] << 8) | (uint16_t)bytes[1];
}

int16_t readInt16BE(const uint8_t* bytes) {
    return (int16_t)readUInt16BE(bytes);
}

int32_t readInt32BE(const uint8_t* bytes) {
    uint32_t bitPattern =
        ((uint32_t)bytes[0] << 24) |
        ((uint32_t)bytes[1] << 16) |
        ((uint32_t)bytes[2] << 8) |
        (uint32_t)bytes[3];
    return (int32_t)bitPattern;
}

bool consumeCommand(uint8_t expectedCmd) {
    bleListen();
    if (bleSS.available() < 1) return false;
    if (bleSS.peek() != expectedCmd) return false;
    bleSS.read();
    return true;
}

bool readCommandPayload(uint8_t expectedCmd, uint8_t* payload, size_t payloadLength) {
    bleListen();
    if (bleSS.available() < (int)(payloadLength + 1)) return false;
    if (bleSS.peek() != expectedCmd) return false;

    bleSS.read();
    for (size_t i = 0; i < payloadLength; i++) {
        payload[i] = (uint8_t)bleSS.read();
    }
    return true;
}

void applyPhoneGPSPayload(const uint8_t* payload) {
    lastPhoneGPS.latitudeE7 = readInt32BE(payload);
    lastPhoneGPS.longitudeE7 = readInt32BE(payload + 4);
    lastPhoneGPS.speedCmS = readUInt16BE(payload + 8);
    lastPhoneGPS.courseCentidegrees = readUInt16BE(payload + 10);
    lastPhoneGPS.accuracyCm = readUInt16BE(payload + 12);
    lastPhoneGPS.distanceMeters = readUInt16BE(payload + 14);
    lastPhoneGPS.elapsedSeconds = readUInt16BE(payload + 16);
    lastPhoneGPS.flags = payload[18];

    if (lastPhoneGPS.distanceMeters > 0) {
        totalDist_m = lastPhoneGPS.distanceMeters;
    }
}

void applyPhoneControlPayload(const uint8_t* payload) {
    lastPhoneControl.speedCmS = readUInt16BE(payload);
    lastPhoneControl.paceSecondsPerKm = readUInt16BE(payload + 2);
    lastPhoneControl.targetPaceSecondsPerKm = readUInt16BE(payload + 4);
    lastPhoneControl.distanceMeters = readUInt16BE(payload + 6);
    lastPhoneControl.elapsedSeconds = readUInt16BE(payload + 8);
    lastPhoneControl.gapCentimeters = readInt16BE(payload + 10);
    lastPhoneControl.servoAngleDegrees = payload[12];
    lastPhoneControl.zone = payload[13];
    lastPhoneControl.flags = payload[14];

    appControlled = true;
    laserEnabled = (lastPhoneControl.flags & 0x01) != 0;
    dayMode = (lastPhoneControl.flags & 0x02) != 0;
    if (lastPhoneControl.zone <= ZONE_RED) {
        currentZone = (Zone)lastPhoneControl.zone;
    }
    if (lastPhoneControl.paceSecondsPerKm > 0) {
        filteredPace_skm = lastPhoneControl.paceSecondsPerKm;
    }
    if (lastPhoneControl.distanceMeters > 0) {
        totalDist_m = lastPhoneControl.distanceMeters;
    }
}

// ================================================================
//  명령 수신 처리 (v2.0)
// ================================================================
void processBLECommand() {
    bleListen();
    if (!bleSS.available()) return;

    uint8_t cmd = (uint8_t)bleSS.peek();
    switch (cmd) {
        case CMD_LASER_OFF:
            if (!consumeCommand(CMD_LASER_OFF)) return;
            laserEnabled = false;
            break;
        case CMD_LASER_ON:
            if (!consumeCommand(CMD_LASER_ON)) return;
            laserEnabled = true;
            break;
        case CMD_SET_PACE: {
            uint8_t payload[2];
            if (!readCommandPayload(CMD_SET_PACE, payload, sizeof(payload))) return;
            targetPace_skm = readUInt16BE(payload);
            break;
        }
        case CMD_SET_ANGLE:
            {
                uint8_t payload[1];
                if (!readCommandPayload(CMD_SET_ANGLE, payload, sizeof(payload))) return;
                base_angle = constrain((float)payload[0], 0.0f, 180.0f);
                servoTilt.write((int)base_angle);
            }
            break;
        case CMD_SET_ZONE:
            {
                uint8_t payload[1];
                if (!readCommandPayload(CMD_SET_ZONE, payload, sizeof(payload))) return;
                if (payload[0] <= ZONE_RED) {
                    currentZone = (Zone)payload[0];
                }
            }
            break;
        case CMD_SET_ANGLE:
            if (bleSS.available()) {
                base_angle = constrain((float)bleSS.read(), 0.0f, 180.0f);
                servoTilt.write((int)base_angle);
            }
            break;
        case CMD_SET_ZONE:
            if (bleSS.available()) {
                uint8_t zone = bleSS.read();
                if (zone <= ZONE_RED) {
                    currentZone = (Zone)zone;
                }
            }
            break;
        case CMD_SET_SENSITIVITY:
            {
                uint8_t payload[1];
                if (!readCommandPayload(CMD_SET_SENSITIVITY, payload, sizeof(payload))) return;
                sensitivity = payload[0];
            }
            break;
        case CMD_SET_CALIBRATION:
            {
                uint8_t payload[1];
                if (!readCommandPayload(CMD_SET_CALIBRATION, payload, sizeof(payload))) return;
                calibrationOffset = (int8_t)payload[0];
            }
            break;
        case CMD_REQUEST_STATUS:
            if (!consumeCommand(CMD_REQUEST_STATUS)) return;
            sendBLEStatus();
            break;
        case CMD_SET_DAY_MODE:
            {
                uint8_t payload[1];
                if (!readCommandPayload(CMD_SET_DAY_MODE, payload, sizeof(payload))) return;
                dayMode = payload[0] == 0x01;
            }
            break;
        case CMD_REQUEST_STATUS:
            sendBLEStatus();
            break;
        case CMD_SET_DAY_MODE:
            if (bleSS.available()) {
                dayMode = bleSS.read() == 0x01;
            }
            break;
        case CMD_START_RUN:
            if (!consumeCommand(CMD_START_RUN)) return;
            mode = PACE_TRACK;
            runStart_ms = millis();
            totalDist_m = 0;
            laserEnabled = true;
            appControlled = true;
            break;
        case CMD_STOP_RUN:
            if (!consumeCommand(CMD_STOP_RUN)) return;
            mode = WAIT_SWITCH;
            laserEnabled = false;
            appControlled = false;
            break;
        case CMD_PHONE_GPS:
            {
                uint8_t payload[PHONE_GPS_PAYLOAD_LEN];
                if (!readCommandPayload(CMD_PHONE_GPS, payload, sizeof(payload))) return;
                applyPhoneGPSPayload(payload);
            }
            break;
        case CMD_PHONE_CONTROL:
            {
                uint8_t payload[PHONE_CONTROL_PAYLOAD_LEN];
                if (!readCommandPayload(CMD_PHONE_CONTROL, payload, sizeof(payload))) return;
                applyPhoneControlPayload(payload);
            }
            break;
        default:
            bleSS.read();
            break;
    }
}

// ================================================================
//  Setup & Loop
// ================================================================
void setup() {
    Serial.begin(115200);
    beginGPSSerial();
    beginBLESerial();
    setupIMU();

    pinMode(LASER_BASE_PIN, OUTPUT);
    pinMode(LASER_SLOW_PIN, OUTPUT);
    pinMode(LASER_FAST_PIN, OUTPUT);
    pinMode(SWITCH_PIN, INPUT_PULLUP);

    servoTilt.attach(SERVO_PIN);
    servoTilt.write(85);
    
    Serial.println(F("BeamChaser Firmware v2.0 - Gimbal Ready"));
}

void loop() {
    uint32_t now = millis();

    // 1. 10ms (100Hz) - 짐벌 & IMU (최우선)
    if (now - lastIMUTime >= 10) {
        updateIMU();
        updateGimbal();
    }

    // 2. 50ms (20Hz) - BLE 명령 처리
    if (now - lastBleUpdate >= 50) {
        processBLECommand();
        lastBleUpdate = now;
    }

    // 3. 200ms (5Hz) - GPS & 페이스 (Non-blocking)
    if (now - lastGpsUpdate >= 200) {
        // [TODO] Non-blocking TinyGPS+ 로직
        lastGpsUpdate = now;
    }

    // 4. 1000ms (1Hz) - 상태 보고
    if (now - lastStatusSend >= 1000) {
        sendBLEStatus();
        lastStatusSend = now;
    }

    // 레이저 제어 (Day Mode 점멸 포함)
    if (laserEnabled) {
        // 낮 점멸 모드: 50ms ON / 50ms OFF = 10Hz 깜빡임
        if (dayMode && (millis() % 100) >= 50) {
            digitalWrite(LASER_BASE_PIN, LOW);
            digitalWrite(LASER_SLOW_PIN, LOW);
            digitalWrite(LASER_FAST_PIN, LOW);
        } else {
            // Zone에 맞는 색상만 켜기
            digitalWrite(LASER_FAST_PIN, (currentZone == ZONE_BLUE) ? HIGH : LOW);
            digitalWrite(LASER_BASE_PIN, (currentZone == ZONE_GREEN) ? HIGH : LOW);
            digitalWrite(LASER_SLOW_PIN, (currentZone == ZONE_RED) ? HIGH : LOW);
        }
    } else {
        digitalWrite(LASER_BASE_PIN, LOW);
        digitalWrite(LASER_SLOW_PIN, LOW);
        digitalWrite(LASER_FAST_PIN, LOW);
    }
}
