#include <Servo.h>
#include <TinyGPSPlus.h>
#include <SoftwareSerial.h>

/*
 * ================================================================
 *  RunBeam_M9N v3.0 (페이스 안정화 + 서보 방향 보정 버전)
 *  - 항상 상태를 시리얼에 출력 (WAIT / PACE 모두)
 *  - GPS 상태(문자 수, fix 여부, age)도 함께 표시
 *  - 페이스: 속도 기반 + 평균 기반 하이브리드 (반응 + 안정 타협)
 *  - 추가: 페이스 필터 더 보수적으로 + 이동 평균 적용으로 튐 감소
 *  - 레이저/서보: 300m 이후, 페이스 존에 따라 색/각도 제어
 *    * 기본은 GREEN(초록)
 *    * 빨라질수록 서보 각도 110도 쪽으로
 *    * 느려질수록 서보 각도 60도 쪽으로
 *
 *  하드웨어
 *   - Arduino UNO
 *   - GPS : NEO 3 GNSS u-blox M9N (SoftwareSerial D2,D3)
 *   - 서보 : MG90S (D7)
 *   - 레이저 : BL1245(파랑 D4), RL1245(빨강 D5), GL1245(초록 D6)
 *   - 버튼 : 푸시버튼 텍트 스위치 (D8, INPUT_PULLUP, 눌렀을 때 LOW)
 * ================================================================
 */

// ---------------- 핀 정의 ----------------
static const uint8_t GPS_RX = 2;  // Arduino RX (GPS TX 연결)
static const uint8_t GPS_TX = 3;  // Arduino TX (GPS RX 연결)

static const uint8_t LASER_FAST_PIN = 6; // 파랑
static const uint8_t LASER_SLOW_PIN = 5; // 빨강
static const uint8_t LASER_BASE_PIN = 4; // 초록

static const uint8_t SERVO_PIN  = 7;
static const uint8_t SWITCH_PIN = 8;

// ---------------- 라이브러리 객체 ----------------
SoftwareSerial gpsSS(GPS_RX, GPS_TX);
TinyGPSPlus gps;
Servo servoTilt;

// ---------------- 서보 관련 상수 ----------------
const float SERVO_NEAR_deg = 60.0f;  // 느릴 때 쪽
const float SERVO_FAR_deg  = 110.0f; // 빠를 때 쪽

const float ALPHA_THETA = 0.25f; // 서보 부드럽게
const float MAX_STEP_deg = 5.0f;

// ---------------- GPS / 거리 / 속도 ----------------
const uint32_t GPS_MAX_AGE_MS = 4000;   // 4초 이상된 위치는 무효
const float LASER_ENABLE_DIST_m = 300.0f; // 300m 이후 레이저/서보 활성
const float MOVE_SPEED_THRESH   = 0.6f;   // m/s, 이 이상이어야 "이동 중"

// 속도 필터
float instSpeed_mps     = 0.0f;
float filteredSpeed_mps = 0.0f;
// 더 부드럽게 (기존 0.35 → 0.20)
const float ALPHA_SPEED = 0.20f;

// 위치/거리/시간
double lastLat = 0.0;
double lastLon = 0.0;
bool   hasLastPos = false;
double totalDist_m = 0.0;

uint32_t lastPosTime_ms = 0;
uint32_t runStart_ms    = 0;

// ---------------- 페이스 관련 ----------------
// 속도 기반 페이스, 평균 페이스, 원본 페이스, 필터 후 페이스 (초/킬로미터)
float pace_speed_skm   = 1e6;
float pace_avg_skm     = 1e6;
float rawPace_skm      = 1e6;
float filteredPace_skm = 1e6;

// 평균 페이스 비중을 올리는 구간
const float AVG_BLEND_START_DIST_m = 300.0f;  // 200m부터 평균 페이스 반영 시작
const float AVG_BLEND_FULL_DIST_m  = 500.0f;  // 500m 이후 평균 비중 충분히 커짐
const float AVG_BLEND_START_TIME_s = 60.0f;   // 60초부터 평균 반영 시작
const float AVG_BLEND_FULL_TIME_s  = 150.0f;  // 150초 이후 평균 비중 충분히 커짐

// 페이스 필터 (반응 vs 안정 타협)
// 더 보수적으로: ALPHA_PACE ↓, 점프 제한 ↓
const float ALPHA_PACE = 0.14f;                // 0.30 → 0.15
const float MAX_PACE_JUMP_PER_UPDATE_s = 0.4f; // 0.7 → 0.4

// 페이스 이동 평균 버퍼
#define PACE_BUFFER_SIZE 5
float paceBuffer[PACE_BUFFER_SIZE];
int   paceIndex = 0;
int   paceCount = 0;

// ---------------- 모드 & zone ----------------
enum Mode { WAIT_SWITCH, PACE_TRACK };
Mode mode = WAIT_SWITCH;

enum Zone { ZONE_NONE, ZONE_BLUE, ZONE_GREEN, ZONE_RED };
Zone currentZone = ZONE_NONE;

// 페이스 zone (초/킬로미터)
// BLUE : 6:40 ~ 6:59
const int PACE_BLUE_MIN  = 6*60 + 30; // 400
const int PACE_BLUE_MAX  = 6*60 + 59; // 419
// GREEN: 7:00 ~ 7:19
const int PACE_GREEN_MIN = 7*60 +  0; // 420
const int PACE_GREEN_MAX = 7*60 + 29; // 439
// RED  : 7:20 ~ 7:39
const int PACE_RED_MIN   = 7*60 + 30; // 440
const int PACE_RED_MAX   = 7*60 + 59; // 459

// zone 경계 히스테리시스 (±3초)
const int ZONE_MARGIN_s = 3;

const char* zoneToString(Zone z) {
  switch (z) {
    case ZONE_BLUE:  return "BLUE";
    case ZONE_GREEN: return "GREEN";
    case ZONE_RED:   return "RED";
    default:         return "NONE";
  }
}

// ---------------- 스위치 디바운스 ----------------
bool     lastSwitchRaw       = HIGH;
uint32_t lastSwitchChange_ms = 0;
const uint32_t DEBOUNCE_MS   = 50;

// ---------------- 서보 상태 ----------------
float theta_cmd_deg = SERVO_NEAR_deg;
float theta_out_deg = SERVO_NEAR_deg;
bool  servoAttached = false;

// ---------------- 디버그 출력 ----------------
u