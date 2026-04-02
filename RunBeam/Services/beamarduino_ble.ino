/*
 * ================================================================
 *  RunBeam BLE v1.0 — iOS 앱 연동 버전
 *
 *  기존 GPS 독립 페이스 계산 + BLE(HM-10) 명령 수신/상태 전송
 *  앱에서 보내는 명령:
 *    CMD_LASER_OFF   0x00          → 레이저 끄기
 *    CMD_LASER_ON    0x01          → 레이저 켜기
 *    CMD_SET_PACE    0x02 HH LL   → 목표 페이스 설정 (초/km, 2바이트)
 *    CMD_SET_ANGLE   0x03 AA       → 서보 각도 직접 설정 (0~180)
 *    CMD_SET_ZONE    0x04 ZZ       → 존 직접 설정 (0=NONE,1=BLUE,2=GREEN,3=RED)
 *    CMD_START_RUN   0x05          → 러닝 시작 (GPS 트래킹 시작)
 *    CMD_STOP_RUN    0x06          → 러닝 종료 (레이저 끄기, WAIT 복귀)
 *    CMD_REQUEST_STATUS 0x07       → 상태 즉시 전송 요청
 *
 *  장치에서 보내는 상태 (1초마다 + 요청 시):
 *    STX(0xAA) battery laserOn servoAngle zone pace_H pace_L dist_H dist_L ETX(0x55)
 *    10바이트 고정
 *
 *  하드웨어 (Arduino UNO)
 *   - GPS : NEO M9N (SoftwareSerial D2,D3)
 *   - BLE : HM-10 (SoftwareSerial D9,D10)
 *   - 서보 : MG90S (D7)
 *   - 레이저 : 파랑(D6), 빨강(D5), 초록(D4)
 *   - 버튼 : D8 (INPUT_PULLUP)
 *
 *  BLE 모듈 설정 (AT 명령으로 사전 설정):
 *   AT+NAMERunBeam
 *   AT+UUID0xFFE0
 *   AT+CHAR0xFFE1
 *   AT+BAUD4 (9600)
 * ================================================================
 */

#include <Servo.h>
#include <TinyGPSPlus.h>
#include <SoftwareSerial.h>

// ─────────── 핀 정의 ───────────
static const uint8_t GPS_RX = 2;
static const uint8_t GPS_TX = 3;
static const uint8_t BLE_RX = 9;   // Arduino RX ← HM-10 TX
static const uint8_t BLE_TX = 10;  // Arduino TX → HM-10 RX

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

// ─────────── BLE 프로토콜 ───────────
#define CMD_LASER_OFF      0x00
#define CMD_LASER_ON       0x01
#define CMD_SET_PACE       0x02
#define CMD_SET_ANGLE      0x03
#define CMD_SET_ZONE       0x04
#define CMD_START_RUN      0x05
#define CMD_STOP_RUN       0x06
#define CMD_REQUEST_STATUS 0x07

#define STATUS_STX 0xAA
#define STATUS_ETX 0x55

// ─────────── 서보 ───────────
const float SERVO_MIN_deg = 60.0f;
const float SERVO_MAX_deg = 110.0f;
const float ALPHA_THETA   = 0.25f;
const float MAX_STEP_deg  = 5.0f;

float theta_cmd_deg = 85.0f;  // 중앙
float theta_out_deg = 85.0f;
bool  servoAttached = false;

// ─────────── GPS / 거리 / 속도 ───────────
const uint32_t GPS_MAX_AGE_MS   = 4000;
const float MOVE_SPEED_THRESH   = 0.6f;

float filteredSpeed_mps = 0.0f;
const float ALPHA_SPEED = 0.20f;

double lastLat = 0.0, lastLon = 0.0;
bool   hasLastPos = false;
double totalDist_m = 0.0;
uint32_t lastPosTime_ms = 0;
uint32_t runStart_ms    = 0;

// ─────────── 페이스 ───────────
float pace_speed_skm   = 1e6;
float pace_avg_skm     = 1e6;
float rawPace_skm      = 1e6;
float filteredPace_skm = 1e6;

const float AVG_BLEND_START_DIST_m = 300.0f;
const float AVG_BLEND_FULL_DIST_m  = 500.0f;
const float AVG_BLEND_START_TIME_s = 60.0f;
const float AVG_BLEND_FULL_TIME_s  = 150.0f;

const float ALPHA_PACE = 0.14f;
const float MAX_PACE_JUMP_PER_UPDATE_s = 0.4f;

#define PACE_BUFFER_SIZE 5
float paceBuffer[PACE_BUFFER_SIZE];
int   paceIndex = 0;
int   paceCount = 0;

// 앱에서 설정한 목표 페이스 (초/km)
int targetPace_skm = 420;  // 기본 7:00/km

// ─────────── 모드 & Zone ───────────
enum Mode { WAIT_SWITCH, PACE_TRACK };
Mode mode = WAIT_SWITCH;

enum Zone { ZONE_NONE = 0, ZONE_BLUE = 1, ZONE_GREEN = 2, ZONE_RED = 3 };
Zone currentZone = ZONE_NONE;

// Zone 경계: 목표 페이스 기준 ±20초
const int ZONE_FAST_OFFSET = -20;   // BLUE: 목표보다 20초 빠름
const int ZONE_SLOW_OFFSET =  20;   // RED:  목표보다 20초 느림
const int ZONE_MARGIN_s    =   3;

// ─────────── 레이저/BLE 상태 ───────────
bool laserEnabled = false;
bool bleConnected = false;  // BLE 연결 여부 추적
bool appControlled = false; // 앱이 제어 중인지

// ─────────── 스위치 디바운스 ───────────
bool     lastSwitchRaw       = HIGH;
uint32_t lastSwitchChange_ms = 0;
const uint32_t DEBOUNCE_MS   = 50;

// ─────────── 타이머 ───────────
uint32_t lastStatusSend_ms = 0;
const uint32_t STATUS_INTERVAL_MS = 1000; // 1초마다 상태 전송

uint32_t lastGpsRead_ms = 0;

// ─────────── BLE 수신 버퍼 ───────────
#define BLE_BUF_SIZE 8
uint8_t bleBuf[BLE_BUF_SIZE];
uint8_t bleIdx = 0;

// ================================================================
//  배터리 전압 읽기 (A0 핀에 분압 회로)
//  분압: VIN → 10kΩ → A0 → 10kΩ → GND
//  실제 전압 = ADC * 5.0/1023 * 2
//  9V 기준: 100% = 9V, 0% = 6V
// ================================================================
uint8_t readBatteryPercent() {
    int raw = analogRead(A0);
    float voltage = raw * (5.0 / 1023.0) * 2.0;  // 분압 보정
    float pct = (voltage - 6.0) / (9.0 - 6.0) * 100.0;
    return (uint8_t)constrain(pct, 0, 100);
}

// ================================================================
//  GPS → 거리/속도/페이스 계산 (기존 로직 유지)
// ================================================================
double haversine_m(double lat1, double lon1, double lat2, double lon2) {
    double R   = 6371000.0;
    double dLat = radians(lat2 - lat1);
    double dLon = radians(lon2 - lon1);
    double a   = sin(dLat/2)*sin(dLat/2)
               + cos(radians(lat1))*cos(radians(lat2))
               * sin(dLon/2)*sin(dLon/2);
    return R * 2.0 * atan2(sqrt(a), sqrt(1.0-a));
}

void updateGPS() {
    // SoftwareSerial 전환: GPS 읽기
    gpsSS.listen();
    uint32_t start = millis();
    while (millis() - start < 100) {
        while (gpsSS.available()) {
            gps.encode(gpsSS.read());
        }
    }

    if (!gps.location.isValid() || gps.location.age() > GPS_MAX_AGE_MS) return;
    if (mode != PACE_TRACK) return;

    double lat = gps.location.lat();
    double lon = gps.location.lng();
    uint32_t now = millis();

    if (hasLastPos) {
        double d = haversine_m(lastLat, lastLon, lat, lon);
        float dt = (now - lastPosTime_ms) / 1000.0f;
        if (dt > 0.1f && d > 0.5 && d < 50.0 * dt) {
            totalDist_m += d;
            float instSpeed = d / dt;

            // 속도 필터
            filteredSpeed_mps = ALPHA_SPEED * instSpeed + (1.0f - ALPHA_SPEED) * filteredSpeed_mps;

            // 속도 기반 페이스
            if (filteredSpeed_mps > MOVE_SPEED_THRESH) {
                pace_speed_skm = 1000.0f / filteredSpeed_mps;
            }

            // 평균 페이스
            float elapsed_s = (now - runStart_ms) / 1000.0f;
            if (totalDist_m > 50 && elapsed_s > 10) {
                pace_avg_skm = elapsed_s / (totalDist_m / 1000.0f);
            }

            // 하이브리드 블렌딩
            float blendDist = constrain((totalDist_m - AVG_BLEND_START_DIST_m) /
                              (AVG_BLEND_FULL_DIST_m - AVG_BLEND_START_DIST_m), 0.0f, 1.0f);
            float blendTime = constrain((elapsed_s - AVG_BLEND_START_TIME_s) /
                              (AVG_BLEND_FULL_TIME_s - AVG_BLEND_START_TIME_s), 0.0f, 1.0f);
            float avgWeight = max(blendDist, blendTime) * 0.5f;
            rawPace_skm = pace_speed_skm * (1.0f - avgWeight) + pace_avg_skm * avgWeight;

            // EMA 필터
            float diff = rawPace_skm - filteredPace_skm;
            diff = constrain(diff, -MAX_PACE_JUMP_PER_UPDATE_s, MAX_PACE_JUMP_PER_UPDATE_s);
            filteredPace_skm += ALPHA_PACE * diff;

            // 이동 평균
            paceBuffer[paceIndex] = filteredPace_skm;
            paceIndex = (paceIndex + 1) % PACE_BUFFER_SIZE;
            if (paceCount < PACE_BUFFER_SIZE) paceCount++;
            float sum = 0;
            for (int i = 0; i < paceCount; i++) sum += paceBuffer[i];
            filteredPace_skm = sum / paceCount;
        }
    }

    lastLat = lat;
    lastLon = lon;
    hasLastPos = true;
    lastPosTime_ms = now;
}

// ================================================================
//  Zone 판정 (목표 페이스 기준 동적)
// ================================================================
Zone calcZone(float pace_skm) {
    int p = (int)pace_skm;
    int blueMax  = targetPace_skm + ZONE_FAST_OFFSET;  // 빠름
    int redMin   = targetPace_skm + ZONE_SLOW_OFFSET;  // 느림

    // 히스테리시스 적용
    if (currentZone == ZONE_BLUE && p > blueMax + ZONE_MARGIN_s) {
        return ZONE_GREEN;
    }
    if (currentZone == ZONE_RED && p < redMin - ZONE_MARGIN_s) {
        return ZONE_GREEN;
    }
    if (currentZone == ZONE_GREEN) {
        if (p < blueMax - ZONE_MARGIN_s) return ZONE_BLUE;
        if (p > redMin + ZONE_MARGIN_s) return ZONE_RED;
    }

    // 초기 판정
    if (p <= blueMax) return ZONE_BLUE;
    if (p >= redMin) return ZONE_RED;
    return ZONE_GREEN;
}

// ================================================================
//  레이저 & 서보 제어
// ================================================================
void setLasers(Zone z) {
    if (!laserEnabled) {
        digitalWrite(LASER_FAST_PIN, LOW);
        digitalWrite(LASER_BASE_PIN, LOW);
        digitalWrite(LASER_SLOW_PIN, LOW);
        return;
    }
    switch (z) {
        case ZONE_BLUE:
            digitalWrite(LASER_FAST_PIN, HIGH);
            digitalWrite(LASER_BASE_PIN, LOW);
            digitalWrite(LASER_SLOW_PIN, LOW);
            break;
        case ZONE_GREEN:
            digitalWrite(LASER_FAST_PIN, LOW);
            digitalWrite(LASER_BASE_PIN, HIGH);
            digitalWrite(LASER_SLOW_PIN, LOW);
            break;
        case ZONE_RED:
            digitalWrite(LASER_FAST_PIN, LOW);
            digitalWrite(LASER_BASE_PIN, LOW);
            digitalWrite(LASER_SLOW_PIN, HIGH);
            break;
        default:
            digitalWrite(LASER_FAST_PIN, LOW);
            digitalWrite(LASER_BASE_PIN, HIGH);  // 기본 초록
            digitalWrite(LASER_SLOW_PIN, LOW);
            break;
    }
}

void updateServoAngle(Zone z) {
    // Zone에 따라 목표 각도 설정
    switch (z) {
        case ZONE_BLUE:
            theta_cmd_deg = SERVO_MAX_deg;  // 빠름 → 110도
            break;
        case ZONE_RED:
            theta_cmd_deg = SERVO_MIN_deg;  // 느림 → 60도
            break;
        default:
            theta_cmd_deg = (SERVO_MIN_deg + SERVO_MAX_deg) / 2.0f;  // 중앙
            break;
    }

    // 부드럽게 이동
    float diff = theta_cmd_deg - theta_out_deg;
    diff = constrain(diff, -MAX_STEP_deg, MAX_STEP_deg);
    theta_out_deg += ALPHA_THETA * diff;
    theta_out_deg = constrain(theta_out_deg, SERVO_MIN_deg, SERVO_MAX_deg);

    if (!servoAttached) {
        servoTilt.attach(SERVO_PIN);
        servoAttached = true;
    }
    servoTilt.write((int)theta_out_deg);
}

// ================================================================
//  BLE 상태 전송
//  [STX, battery, laserOn, servoAngle, zone, pace_H, pace_L, dist_H, dist_L, ETX]
// ================================================================
void sendBLEStatus() {
    uint8_t battery = readBatteryPercent();
    uint8_t laser   = laserEnabled ? 1 : 0;
    uint8_t angle   = (uint8_t)constrain(theta_out_deg, 0, 180);
    uint8_t zone    = (uint8_t)currentZone;

    uint16_t pace = (filteredPace_skm < 1e5) ? (uint16_t)filteredPace_skm : 0;
    uint16_t dist = (totalDist_m < 65535) ? (uint16_t)totalDist_m : 65535;

    uint8_t packet[10] = {
        STATUS_STX,
        battery,
        laser,
        angle,
        zone,
        (uint8_t)(pace >> 8), (uint8_t)(pace & 0xFF),
        (uint8_t)(dist >> 8), (uint8_t)(dist & 0xFF),
        STATUS_ETX
    };

    bleSS.listen();
    bleSS.write(packet, 10);
}

// ================================================================
//  BLE 명령 수신 처리
// ================================================================
void processBLECommand() {
    bleSS.listen();

    while (bleSS.available()) {
        uint8_t b = bleSS.read();

        // 첫 바이트가 유효한 커맨드인지 확인
        if (bleIdx == 0) {
            if (b > CMD_REQUEST_STATUS) continue; // 잘못된 커맨드 무시
        }

        bleBuf[bleIdx++] = b;

        // 커맨드별 완성 길이 체크 및 실행
        uint8_t cmd = bleBuf[0];
        bool complete = false;

        switch (cmd) {
            case CMD_LASER_OFF:
                laserEnabled = false;
                setLasers(ZONE_NONE);
                Serial.println(F("[BLE] Laser OFF"));
                complete = true;
                break;

            case CMD_LASER_ON:
                laserEnabled = true;
                setLasers(currentZone);
                Serial.println(F("[BLE] Laser ON"));
                complete = true;
                break;

            case CMD_SET_PACE:
                if (bleIdx >= 3) {
                    targetPace_skm = ((int)bleBuf[1] << 8) | bleBuf[2];
                    Serial.print(F("[BLE] Target pace: "));
                    Serial.print(targetPace_skm / 60);
                    Serial.print(F("'"));
                    Serial.print(targetPace_skm % 60);
                    Serial.println(F("\"/km"));
                    complete = true;
                }
                break;

            case CMD_SET_ANGLE:
                if (bleIdx >= 2) {
                    int angle = constrain(bleBuf[1], 0, 180);
                    theta_cmd_deg = angle;
                    theta_out_deg = angle;
                    if (!servoAttached) {
                        servoTilt.attach(SERVO_PIN);
                        servoAttached = true;
                    }
                    servoTilt.write(angle);
                    Serial.print(F("[BLE] Servo angle: "));
                    Serial.println(angle);
                    complete = true;
                }
                break;

            case CMD_SET_ZONE:
                if (bleIdx >= 2) {
                    currentZone = (Zone)constrain(bleBuf[1], 0, 3);
                    setLasers(currentZone);
                    updateServoAngle(currentZone);
                    Serial.print(F("[BLE] Zone: "));
                    Serial.println(bleBuf[1]);
                    complete = true;
                }
                break;

            case CMD_START_RUN:
                mode = PACE_TRACK;
                runStart_ms = millis();
                totalDist_m = 0;
                hasLastPos = false;
                filteredSpeed_mps = 0;
                filteredPace_skm = 1e6;
                pace_speed_skm = 1e6;
                pace_avg_skm = 1e6;
                paceCount = 0;
                paceIndex = 0;
                laserEnabled = true;
                currentZone = ZONE_GREEN;
                setLasers(ZONE_GREEN);
                appControlled = true;
                Serial.println(F("[BLE] Run START"));
                complete = true;
                break;

            case CMD_STOP_RUN:
                mode = WAIT_SWITCH;
                laserEnabled = false;
                setLasers(ZONE_NONE);
                if (servoAttached) {
                    servoTilt.write(85); // 중앙
                    delay(200);
                    servoTilt.detach();
                    servoAttached = false;
                }
                appControlled = false;
                Serial.println(F("[BLE] Run STOP"));
                complete = true;
                break;

            case CMD_REQUEST_STATUS:
                sendBLEStatus();
                Serial.println(F("[BLE] Status sent"));
                complete = true;
                break;

            default:
                complete = true; // 알 수 없는 명령 → 버림
                break;
        }

        if (complete) {
            bleIdx = 0;
        }

        if (bleIdx >= BLE_BUF_SIZE) {
            bleIdx = 0;  // 버퍼 오버플로우 방지
        }
    }
}

// ================================================================
//  물리 버튼 처리 (앱 미연결 시 독립 동작용)
// ================================================================
void checkSwitch() {
    if (appControlled) return; // 앱 제어 중이면 버튼 무시

    bool raw = digitalRead(SWITCH_PIN);
    uint32_t now = millis();

    if (raw != lastSwitchRaw) {
        lastSwitchChange_ms = now;
    }
    lastSwitchRaw = raw;

    if ((now - lastSwitchChange_ms) > DEBOUNCE_MS && raw == LOW) {
        if (mode == WAIT_SWITCH) {
            mode = PACE_TRACK;
            runStart_ms = now;
            totalDist_m = 0;
            hasLastPos = false;
            filteredSpeed_mps = 0;
            filteredPace_skm = 1e6;
            pace_speed_skm = 1e6;
            pace_avg_skm = 1e6;
            paceCount = 0;
            paceIndex = 0;
            laserEnabled = true;
            currentZone = ZONE_GREEN;
            setLasers(ZONE_GREEN);
            Serial.println(F("[BTN] Run START"));
        } else {
            mode = WAIT_SWITCH;
            laserEnabled = false;
            setLasers(ZONE_NONE);
            if (servoAttached) {
                servoTilt.write(85);
                delay(200);
                servoTilt.detach();
                servoAttached = false;
            }
            Serial.println(F("[BTN] Run STOP"));
        }
        delay(300); // 중복 방지
    }
}

// ================================================================
//  setup()
// ================================================================
void setup() {
    Serial.begin(115200);  // 디버그 (USB)
    gpsSS.begin(38400);    // GPS
    bleSS.begin(9600);     // HM-10 BLE

    pinMode(LASER_FAST_PIN, OUTPUT);
    pinMode(LASER_BASE_PIN, OUTPUT);
    pinMode(LASER_SLOW_PIN, OUTPUT);
    pinMode(SWITCH_PIN, INPUT_PULLUP);

    digitalWrite(LASER_FAST_PIN, LOW);
    digitalWrite(LASER_BASE_PIN, LOW);
    digitalWrite(LASER_SLOW_PIN, LOW);

    Serial.println(F("=== RunBeam BLE v1.0 ==="));
    Serial.println(F("GPS: D2,D3 | BLE: D9,D10 | Servo: D7"));
    Serial.println(F("Laser: B=D6 R=D5 G=D4 | Button: D8"));
    Serial.println(F("Waiting for BLE connection or button press..."));
}

// ================================================================
//  loop()
// ================================================================
void loop() {
    uint32_t now = millis();

    // 1) BLE 명령 처리
    processBLECommand();

    // 2) 물리 버튼 확인
    checkSwitch();

    // 3) GPS 업데이트 (200ms 간격으로 전환)
    if (now - lastGpsRead_ms > 200) {
        updateGPS();
        lastGpsRead_ms = now;
    }

    // 4) PACE_TRACK 모드일 때 Zone/서보/레이저 업데이트
    if (mode == PACE_TRACK) {
        if (filteredPace_skm < 1e5 && totalDist_m > 100) {
            Zone newZone = calcZone(filteredPace_skm);
            currentZone = newZone;
        }
        setLasers(currentZone);
        updateServoAngle(currentZone);
    }

    // 5) BLE 상태 주기적 전송 (1초마다)
    if (now - lastStatusSend_ms >= STATUS_INTERVAL_MS) {
        sendBLEStatus();
        lastStatusSend_ms = now;

        // 디버그 시리얼 출력
        Serial.print(mode == PACE_TRACK ? F("[PACE] ") : F("[WAIT] "));
        Serial.print(F("Dist:"));
        Serial.print(totalDist_m, 1);
        Serial.print(F("m Pace:"));
        if (filteredPace_skm < 1e5) {
            Serial.print((int)filteredPace_skm / 60);
            Serial.print("'");
            Serial.print((int)filteredPace_skm % 60);
            Serial.print("\"");
        } else {
            Serial.print(F("--:--"));
        }
        Serial.print(F(" Target:"));
        Serial.print(targetPace_skm / 60);
        Serial.print("'");
        Serial.print(targetPace_skm % 60);
        Serial.print(F("\" Zone:"));
        switch (currentZone) {
            case ZONE_BLUE:  Serial.print(F("BLUE"));  break;
            case ZONE_GREEN: Serial.print(F("GREEN")); break;
            case ZONE_RED:   Serial.print(F("RED"));   break;
            default:         Serial.print(F("NONE"));  break;
        }
        Serial.print(F(" Servo:"));
        Serial.print((int)theta_out_deg);
        Serial.print(F(" Laser:"));
        Serial.println(laserEnabled ? F("ON") : F("OFF"));
    }
}
