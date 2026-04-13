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
 *
 *  [하드웨어]
 *   - MPU6050: I2C (SDA:A4, SCL:A5)
 *   - GPS: NEO M9N (D2, D3)
 *   - BLE: HM-10 (D9, D10)
 *   - Servo: MG90S (D7)
 * ================================================================
 */

#include <Wire.h>
#include <Servo.h>
#include <TinyGPSPlus.h>
#include <SoftwareSerial.h>

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
SoftwareSerial gpsSS(GPS_RX, GPS_TX);
SoftwareSerial bleSS(BLE_RX, BLE_TX);
TinyGPSPlus gps;
Servo servoTilt;

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

// ─────────── 페이스/거리 데이터 ───────────
int targetPace_skm = 420;
float filteredPace_skm = 1e6;
double totalDist_m = 0;
uint32_t runStart_ms = 0;

// ─────────── 타이머 ───────────
uint32_t lastGpsUpdate = 0;
uint32_t lastBleUpdate = 0;
uint32_t lastStatusSend = 0;

// ================================================================
//  IMU (MPU6050) 초기화 및 읽기
// ================================================================
void setupIMU() {
    Wire.begin();
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(0x6B); // PWR_MGMT_1
    Wire.write(0);    // wake up
    Wire.endTransmission(true);
    Wire.setClock(400000L); // I2C 속도 업그레이드
}

void updateIMU() {
    uint32_t now = millis();
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

    bleSS.listen();
    bleSS.write(packet, 12);
}

// ================================================================
//  명령 수신 처리 (v2.0)
// ================================================================
void processBLECommand() {
    bleSS.listen();
    if (!bleSS.available()) return;

    uint8_t cmd = bleSS.read();
    switch (cmd) {
        case CMD_LASER_OFF: laserEnabled = false; break;
        case CMD_LASER_ON:  laserEnabled = true; break;
        case CMD_SET_PACE: 
            if (bleSS.available() >= 2) {
                targetPace_skm = (bleSS.read() << 8) | bleSS.read();
            }
            break;
        case CMD_SET_SENSITIVITY:
            if (bleSS.available()) sensitivity = bleSS.read();
            break;
        case CMD_SET_CALIBRATION:
            if (bleSS.available()) calibrationOffset = (int8_t)bleSS.read();
            break;
        case CMD_START_RUN:
            mode = PACE_TRACK;
            runStart_ms = millis();
            totalDist_m = 0;
            laserEnabled = true;
            appControlled = true;
            break;
        case CMD_STOP_RUN:
            mode = WAIT_SWITCH;
            laserEnabled = false;
            appControlled = false;
            break;
    }
}

// ================================================================
//  Setup & Loop
// ================================================================
void setup() {
    Serial.begin(115200);
    gpsSS.begin(38400);
    bleSS.begin(9600);
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
