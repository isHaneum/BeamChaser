/*
 * BeamChaser ESP32 Direct BLE Firmware
 *
 * Purpose
 * - iPhone app <-> ESP32 BLE direct connection
 * - ESP32 directly controls MPU6050 + 2-axis servo gimbal + laser color pins
 * - Compatible with the current iOS app protocol:
 *   Service UUID:        0000FFE0-0000-1000-8000-00805F9B34FB
 *   Characteristic UUID: 0000FFE1-0000-1000-8000-00805F9B34FB
 *
 * Required Arduino libraries
 * - ESP32 board package
 * - ESP32Servo
 *
 * Wiring defaults, change these to match the soldered board:
 * - MPU6050 SDA -> GPIO 21
 * - MPU6050 SCL -> GPIO 22
 * - Pitch servo signal -> GPIO 18
 * - Yaw servo signal   -> GPIO 19
 * - Green laser -> GPIO 25
 * - Red laser   -> GPIO 26
 * - Blue laser  -> GPIO 27
 *
 * Important
 * - Servo power must be separated from ESP32 3.3V.
 * - ESP32 GND, servo power GND, MPU6050 GND must be common.
 */

#include <Arduino.h>
#include <Wire.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ESP32Servo.h>

// ================================================================
// BLE UUIDs: must match BeamChaser iOS app BLEConstants
// ================================================================
static const char* DEVICE_NAME = "BeamChaser-ESP32";
static const char* SERVICE_UUID = "0000FFE0-0000-1000-8000-00805F9B34FB";
static const char* CHARACTERISTIC_UUID = "0000FFE1-0000-1000-8000-00805F9B34FB";

BLEServer* bleServer = nullptr;
BLECharacteristic* beamCharacteristic = nullptr;
bool bleConnected = false;

// ================================================================
// Pin map: adjust to the actual soldered board
// Avoid ESP32 GPIO 6~11 because they are usually connected to flash.
// ================================================================
static const int IMU_SDA_PIN = 21;
static const int IMU_SCL_PIN = 22;

static const int PITCH_SERVO_PIN = 18;
static const int YAW_SERVO_PIN = 19;

static const int LASER_GREEN_PIN = 25;
static const int LASER_RED_PIN = 26;
static const int LASER_BLUE_PIN = 27;

// ================================================================
// MPU6050 registers
// ================================================================
static const uint8_t MPU_ADDR = 0x68;
static const uint8_t MPU_PWR_MGMT_1 = 0x6B;
static const uint8_t MPU_ACCEL_XOUT_H = 0x3B;

// ================================================================
// iOS app command protocol
// ================================================================
static const uint8_t CMD_LASER_OFF = 0x00;
static const uint8_t CMD_LASER_ON = 0x01;
static const uint8_t CMD_SET_PACE = 0x02;
static const uint8_t CMD_SET_ANGLE = 0x03;
static const uint8_t CMD_SET_ZONE = 0x04;
static const uint8_t CMD_START_RUN = 0x05;
static const uint8_t CMD_STOP_RUN = 0x06;
static const uint8_t CMD_REQUEST_STATUS = 0x07;
static const uint8_t CMD_SET_DAY_MODE = 0x08;
static const uint8_t CMD_SET_SENSITIVITY = 0x09;
static const uint8_t CMD_SET_CALIBRATION = 0x0A;
static const uint8_t CMD_PHONE_GPS = 0x0B;
static const uint8_t CMD_PHONE_CONTROL = 0x0C;

static const uint8_t STATUS_STX = 0xAA;
static const uint8_t STATUS_ETX = 0x55;

static const size_t PHONE_GPS_PAYLOAD_LEN = 19;
static const size_t PHONE_CONTROL_PAYLOAD_LEN = 15;

enum DeviceZone : uint8_t {
  ZONE_NONE = 0,
  ZONE_BLUE = 1,
  ZONE_GREEN = 2,
  ZONE_RED = 3
};

// ================================================================
// Hardware state
// ================================================================
Servo pitchServo;
Servo yawServo;

bool laserEnabled = false;
bool dayModeEnabled = false;
DeviceZone currentZone = ZONE_NONE;

uint8_t sensitivity = 128;
int8_t calibrationOffset = 0;
uint16_t targetPaceSecondsPerKm = 420;
uint16_t currentPaceSecondsPerKm = 0;
uint16_t totalDistanceMeters = 0;
uint16_t elapsedSeconds = 0;

// Pitch servo center is also changed by app ANGLE / phoneControl servo angle.
int pitchCenter = 90;
int yawCenter = 90;
int lastPitchServoAngle = 90;
int lastYawServoAngle = 90;

static const int SERVO_MIN = 40;
static const int SERVO_MAX = 140;

// ================================================================
// Gimbal control
// The goal is not absolute direction lock.
// - Pitch: adaptive baseline follows intentional posture changes slowly.
// - Yaw: rate damping only, no yaw angle integration.
// ================================================================
float currentPitch = 0.0f;
float pitchBaseline = 0.0f;
float gyroOffsetX = 0.0f;
float gyroOffsetZ = 0.0f;
float yawRateFiltered = 0.0f;

uint32_t lastImuMicros = 0;
uint32_t sustainedYawMs = 0;

static const float COMPLEMENTARY_ALPHA = 0.96f;
static const float PITCH_BASELINE_ALPHA = 0.006f;
static const float PITCH_DEADBAND_DEG = 0.8f;
static const float YAW_FILTER_ALPHA = 0.25f;
static const float YAW_RATE_DEADBAND_DPS = 3.0f;
static const float TURN_RATE_THRESHOLD_DPS = 25.0f;
static const uint32_t TURN_DETECT_MS = 250;

// ================================================================
// Timers
// ================================================================
uint32_t lastGimbalUpdateMs = 0;
uint32_t lastStatusNotifyMs = 0;
uint32_t lastLaserUpdateMs = 0;

// ================================================================
// Big-endian helpers matching BeamChaser/Models/BLEProtocol.swift
// ================================================================
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

// ================================================================
// BLE status packet: 12 bytes
// [AA, battery, laser, angle, zone, pitch, paceH, paceL, distH, distL, spare, 55]
// ================================================================
void notifyStatus() {
  if (!beamCharacteristic || !bleConnected) return;

  const uint8_t batteryPercent = 85; // TODO: replace with battery ADC reading
  const uint8_t laser = laserEnabled ? 1 : 0;
  const uint8_t angle = (uint8_t)constrain(lastPitchServoAngle, 0, 180);
  const uint8_t zone = (uint8_t)currentZone;
  const int8_t pitch = (int8_t)constrain((int)round(currentPitch), -90, 90);

  uint8_t packet[12] = {
      STATUS_STX,
      batteryPercent,
      laser,
      angle,
      zone,
      (uint8_t)pitch,
      (uint8_t)(currentPaceSecondsPerKm >> 8),
      (uint8_t)(currentPaceSecondsPerKm & 0xFF),
      (uint8_t)(totalDistanceMeters >> 8),
      (uint8_t)(totalDistanceMeters & 0xFF),
      0x00,
      STATUS_ETX
  };

  beamCharacteristic->setValue(packet, sizeof(packet));
  beamCharacteristic->notify();
}

// ================================================================
// Laser control
// ================================================================
void writeAllLasers(bool highGreen, bool highRed, bool highBlue) {
  digitalWrite(LASER_GREEN_PIN, highGreen ? HIGH : LOW);
  digitalWrite(LASER_RED_PIN, highRed ? HIGH : LOW);
  digitalWrite(LASER_BLUE_PIN, highBlue ? HIGH : LOW);
}

void updateLaser() {
  bool enabledNow = laserEnabled;
  if (dayModeEnabled && laserEnabled) {
    enabledNow = ((millis() / 50) % 2) == 0; // about 10 Hz blink
  }

  if (!enabledNow || currentZone == ZONE_NONE) {
    writeAllLasers(false, false, false);
    return;
  }

  switch (currentZone) {
    case ZONE_BLUE:
      writeAllLasers(false, false, true);
      break;
    case ZONE_GREEN:
      writeAllLasers(true, false, false);
      break;
    case ZONE_RED:
      writeAllLasers(false, true, false);
      break;
    default:
      writeAllLasers(false, false, false);
      break;
  }
}

// ================================================================
// MPU6050 low-level read
// ================================================================
bool readMPU6050Raw(int16_t& accX, int16_t& accY, int16_t& accZ, int16_t& gyroX, int16_t& gyroY, int16_t& gyroZ) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(MPU_ACCEL_XOUT_H);
  if (Wire.endTransmission(false) != 0) return false;

  const uint8_t expectedBytes = 14;
  if (Wire.requestFrom(MPU_ADDR, expectedBytes, true) != expectedBytes) return false;

  accX = (Wire.read() << 8) | Wire.read();
  accY = (Wire.read() << 8) | Wire.read();
  accZ = (Wire.read() << 8) | Wire.read();
  Wire.read(); Wire.read(); // temperature, ignored
  gyroX = (Wire.read() << 8) | Wire.read();
  gyroY = (Wire.read() << 8) | Wire.read();
  gyroZ = (Wire.read() << 8) | Wire.read();
  return true;
}

void setupIMU() {
  Wire.begin(IMU_SDA_PIN, IMU_SCL_PIN);
  Wire.setClock(400000L);

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(MPU_PWR_MGMT_1);
  Wire.write(0x00);
  Wire.endTransmission(true);
  delay(100);

  Serial.println("Calibrating MPU6050 gyro offsets. Keep device still.");

  const int sampleCount = 500;
  double sumGyroX = 0;
  double sumGyroZ = 0;

  for (int i = 0; i < sampleCount; i++) {
    int16_t ax, ay, az, gx, gy, gz;
    if (readMPU6050Raw(ax, ay, az, gx, gy, gz)) {
      sumGyroX += gx / 131.0;
      sumGyroZ += gz / 131.0;
    }
    delay(3);
  }

  gyroOffsetX = sumGyroX / sampleCount;
  gyroOffsetZ = sumGyroZ / sampleCount;

  int16_t ax, ay, az, gx, gy, gz;
  if (readMPU6050Raw(ax, ay, az, gx, gy, gz)) {
    float accPitch = atan2((float)ay, sqrt((float)ax * ax + (float)az * az)) * 180.0f / PI;
    currentPitch = accPitch;
    pitchBaseline = accPitch;
  }

  lastImuMicros = micros();
  Serial.println("MPU6050 calibration done.");
}

void updateGimbal() {
  int16_t accX, accY, accZ, gyroX, gyroY, gyroZ;
  if (!readMPU6050Raw(accX, accY, accZ, gyroX, gyroY, gyroZ)) return;

  uint32_t nowMicros = micros();
  float dt = (nowMicros - lastImuMicros) / 1000000.0f;
  lastImuMicros = nowMicros;
  if (dt <= 0.0f || dt > 0.1f) dt = 0.01f;

  const float accPitch = atan2((float)accY, sqrt((float)accX * accX + (float)accZ * accZ)) * 180.0f / PI;
  const float gyroRateX = (gyroX / 131.0f) - gyroOffsetX;
  const float gyroRateZ = (gyroZ / 131.0f) - gyroOffsetZ;

  currentPitch = COMPLEMENTARY_ALPHA * (currentPitch + gyroRateX * dt)
               + (1.0f - COMPLEMENTARY_ALPHA) * accPitch;

  pitchBaseline = pitchBaseline * (1.0f - PITCH_BASELINE_ALPHA)
                + currentPitch * PITCH_BASELINE_ALPHA;

  float pitchError = currentPitch - pitchBaseline;
  if (fabs(pitchError) < PITCH_DEADBAND_DEG) pitchError = 0.0f;

  yawRateFiltered = yawRateFiltered * (1.0f - YAW_FILTER_ALPHA)
                  + gyroRateZ * YAW_FILTER_ALPHA;

  float yawForControl = yawRateFiltered;
  if (fabs(yawForControl) < YAW_RATE_DEADBAND_DPS) yawForControl = 0.0f;

  // Intentional turn guard:
  // If yaw rate is large and sustained, do not fight the user's direction change.
  if (fabs(yawRateFiltered) > TURN_RATE_THRESHOLD_DPS) {
    sustainedYawMs += (uint32_t)(dt * 1000.0f);
  } else {
    sustainedYawMs = 0;
  }

  const bool intentionalTurn = sustainedYawMs >= TURN_DETECT_MS;
  const float turnScale = intentionalTurn ? 0.15f : 1.0f;

  const float sensitivityScale = sensitivity / 128.0f;
  const float pitchGain = 1.6f * sensitivityScale;
  const float yawDampingGain = 0.45f * sensitivityScale;

  const int pitchOut = constrain(
      (int)round(pitchCenter - pitchError * pitchGain + calibrationOffset),
      SERVO_MIN,
      SERVO_MAX
  );

  const int yawOut = constrain(
      (int)round(yawCenter - yawForControl * yawDampingGain * turnScale),
      SERVO_MIN,
      SERVO_MAX
  );

  lastPitchServoAngle = pitchOut;
  lastYawServoAngle = yawOut;

  pitchServo.write(pitchOut);
  yawServo.write(yawOut);
}

// ================================================================
// Command handlers
// ================================================================
void setZoneFromString(const String& color) {
  if (color == "BLUE") currentZone = ZONE_BLUE;
  else if (color == "GREEN") currentZone = ZONE_GREEN;
  else if (color == "RED") currentZone = ZONE_RED;
  else currentZone = ZONE_NONE;
}

void handleTextCommand(String command) {
  command.trim();
  command.toUpperCase();

  Serial.print("BLE text command: ");
  Serial.println(command);

  if (command == "ON" || command == "START") {
    laserEnabled = true;
    if (currentZone == ZONE_NONE) currentZone = ZONE_GREEN;
  } else if (command == "OFF" || command == "STOP") {
    laserEnabled = false;
  } else if (command == "STATUS") {
    notifyStatus();
    return;
  } else if (command.startsWith("ANGLE:")) {
    int angle = command.substring(6).toInt();
    pitchCenter = constrain(angle, 0, 180);
  } else if (command.startsWith("COLOR:")) {
    setZoneFromString(command.substring(6));
    if (currentZone != ZONE_NONE) laserEnabled = true;
  } else if (command == "RESET_YAW") {
    yawRateFiltered = 0.0f;
    sustainedYawMs = 0;
  } else if (command == "CALIBRATE") {
    pitchBaseline = currentPitch;
    yawRateFiltered = 0.0f;
    sustainedYawMs = 0;
  }

  updateLaser();
  notifyStatus();
}

void handleBinaryCommand(const uint8_t* data, size_t len) {
  if (len < 1) return;

  const uint8_t cmd = data[0];
  const uint8_t* payload = data + 1;
  const size_t payloadLen = len - 1;

  Serial.print("BLE binary command: 0x");
  Serial.println(cmd, HEX);

  switch (cmd) {
    case CMD_LASER_OFF:
      laserEnabled = false;
      break;

    case CMD_LASER_ON:
      laserEnabled = true;
      if (currentZone == ZONE_NONE) currentZone = ZONE_GREEN;
      break;

    case CMD_SET_PACE:
      if (payloadLen >= 2) targetPaceSecondsPerKm = readUInt16BE(payload);
      break;

    case CMD_SET_ANGLE:
      if (payloadLen >= 1) pitchCenter = constrain((int)payload[0], 0, 180);
      break;

    case CMD_SET_ZONE:
      if (payloadLen >= 1 && payload[0] <= ZONE_RED) currentZone = (DeviceZone)payload[0];
      break;

    case CMD_START_RUN:
      laserEnabled = true;
      if (currentZone == ZONE_NONE) currentZone = ZONE_GREEN;
      elapsedSeconds = 0;
      totalDistanceMeters = 0;
      break;

    case CMD_STOP_RUN:
      laserEnabled = false;
      break;

    case CMD_REQUEST_STATUS:
      notifyStatus();
      return;

    case CMD_SET_DAY_MODE:
      if (payloadLen >= 1) dayModeEnabled = payload[0] == 0x01;
      break;

    case CMD_SET_SENSITIVITY:
      if (payloadLen >= 1) sensitivity = payload[0];
      break;

    case CMD_SET_CALIBRATION:
      if (payloadLen >= 1) calibrationOffset = (int8_t)payload[0];
      break;

    case CMD_PHONE_GPS:
      if (payloadLen >= PHONE_GPS_PAYLOAD_LEN) {
        const uint16_t speedCmS = readUInt16BE(payload + 8);
        totalDistanceMeters = readUInt16BE(payload + 14);
        elapsedSeconds = readUInt16BE(payload + 16);
        if (speedCmS > 0) {
          currentPaceSecondsPerKm = constrain((uint16_t)(100000.0f / speedCmS), 1, 65535);
        }
      }
      break;

    case CMD_PHONE_CONTROL:
      if (payloadLen >= PHONE_CONTROL_PAYLOAD_LEN) {
        const uint16_t speedCmS = readUInt16BE(payload);
        currentPaceSecondsPerKm = readUInt16BE(payload + 2);
        targetPaceSecondsPerKm = readUInt16BE(payload + 4);
        totalDistanceMeters = readUInt16BE(payload + 6);
        elapsedSeconds = readUInt16BE(payload + 8);
        const uint8_t servoAngle = payload[12];
        const uint8_t zone = payload[13];
        const uint8_t flags = payload[14];

        pitchCenter = constrain((int)servoAngle, 0, 180);
        if (zone <= ZONE_RED) currentZone = (DeviceZone)zone;
        laserEnabled = (flags & 0x01) != 0;
        dayModeEnabled = (flags & 0x02) != 0;

        if (currentPaceSecondsPerKm == 0 && speedCmS > 0) {
          currentPaceSecondsPerKm = constrain((uint16_t)(100000.0f / speedCmS), 1, 65535);
        }
      }
      break;

    default:
      break;
  }

  updateLaser();
  notifyStatus();
}

bool looksLikeTextCommand(const uint8_t* data, size_t len) {
  if (len == 0) return false;
  if (data[0] <= CMD_PHONE_CONTROL) return false;

  for (size_t i = 0; i < len; i++) {
    const uint8_t c = data[i];
    if (c == '\r' || c == '\n' || c == '\t') continue;
    if (c < 0x20 || c > 0x7E) return false;
  }
  return true;
}

class BeamServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    bleConnected = true;
    Serial.println("BLE connected");
  }

  void onDisconnect(BLEServer* server) override {
    bleConnected = false;
    Serial.println("BLE disconnected. Restart advertising.");
    delay(100);
    server->getAdvertising()->start();
  }
};

class BeamCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    std::string value = characteristic->getValue();
    if (value.empty()) return;

    const uint8_t* data = reinterpret_cast<const uint8_t*>(value.data());
    const size_t len = value.length();

    if (looksLikeTextCommand(data, len)) {
      String command;
      for (size_t i = 0; i < len; i++) command += (char)data[i];
      handleTextCommand(command);
    } else {
      handleBinaryCommand(data, len);
    }
  }
};

void setupBLE() {
  BLEDevice::init(DEVICE_NAME);

  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new BeamServerCallbacks());

  BLEService* service = bleServer->createService(SERVICE_UUID);
  beamCharacteristic = service->createCharacteristic(
      CHARACTERISTIC_UUID,
      BLECharacteristic::PROPERTY_READ |
      BLECharacteristic::PROPERTY_WRITE |
      BLECharacteristic::PROPERTY_WRITE_NR |
      BLECharacteristic::PROPERTY_NOTIFY
  );

  beamCharacteristic->addDescriptor(new BLE2902());
  beamCharacteristic->setCallbacks(new BeamCharacteristicCallbacks());

  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("BLE advertising started as BeamChaser-ESP32");
}

void setup() {
  Serial.begin(115200);
  delay(500);

  pinMode(LASER_GREEN_PIN, OUTPUT);
  pinMode(LASER_RED_PIN, OUTPUT);
  pinMode(LASER_BLUE_PIN, OUTPUT);
  writeAllLasers(false, false, false);

  pitchServo.setPeriodHertz(50);
  yawServo.setPeriodHertz(50);
  pitchServo.attach(PITCH_SERVO_PIN, 500, 2400);
  yawServo.attach(YAW_SERVO_PIN, 500, 2400);
  pitchServo.write(pitchCenter);
  yawServo.write(yawCenter);

  setupIMU();
  setupBLE();

  Serial.println("BeamChaser ESP32 Direct BLE Firmware Ready");
}

void loop() {
  const uint32_t now = millis();

  if (now - lastGimbalUpdateMs >= 10) {
    lastGimbalUpdateMs = now;
    updateGimbal();
  }

  if (now - lastLaserUpdateMs >= 20) {
    lastLaserUpdateMs = now;
    updateLaser();
  }

  if (now - lastStatusNotifyMs >= 1000) {
    lastStatusNotifyMs = now;
    notifyStatus();
  }
}
