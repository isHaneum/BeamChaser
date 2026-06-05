#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <ESP32Servo.h>

namespace {
const char* DEVICE_NAME = "BeamChaser-ESP32";
const char* SERVICE_UUID = "0000FFE0-0000-1000-8000-00805F9B34FB";
const char* CHARACTERISTIC_UUID = "0000FFE1-0000-1000-8000-00805F9B34FB";

constexpr int PITCH_SERVO_PIN = 18;
constexpr int YAW_SERVO_PIN = 19;
constexpr int LED_RED_PIN = 25;
constexpr int LED_GREEN_PIN = 26;
constexpr int LED_BLUE_PIN = 27;

constexpr int PWM_CHANNEL_RED = 0;
constexpr int PWM_CHANNEL_GREEN = 1;
constexpr int PWM_CHANNEL_BLUE = 2;
constexpr int PWM_FREQUENCY = 5000;
constexpr int PWM_RESOLUTION = 8;

constexpr float MIN_PITCH_DEG = 35.0f;
constexpr float MAX_PITCH_DEG = 80.0f;
constexpr float MIN_YAW_DEG = -20.0f;
constexpr float MAX_YAW_DEG = 20.0f;
constexpr float SAFE_PITCH_DEG = 60.0f;
constexpr float SAFE_YAW_DEG = 0.0f;
constexpr uint32_t COMMAND_TIMEOUT_MS = 1500;
}

struct LaserPacket {
  float pitchDeg = SAFE_PITCH_DEG;
  float yawDeg = SAFE_YAW_DEG;
  int red = 0;
  int green = 0;
  int blue = 0;
  float intensity = 0.0f;
  String mode = "SAFE";
};

Servo pitchServo;
Servo yawServo;
BLECharacteristic* laserCharacteristic = nullptr;

bool bleClientConnected = false;
uint32_t lastCommandAtMs = 0;
LaserPacket currentPacket;

float clampFloat(float value, float minValue, float maxValue) {
  if (value < minValue) {
    return minValue;
  }

  if (value > maxValue) {
    return maxValue;
  }

  return value;
}

int clampInt(int value, int minValue, int maxValue) {
  if (value < minValue) {
    return minValue;
  }

  if (value > maxValue) {
    return maxValue;
  }

  return value;
}

bool extractFloatValue(const String& payload, const String& key, float& outValue) {
  const int keyIndex = payload.indexOf(key);
  if (keyIndex < 0) {
    return false;
  }

  const int colonIndex = payload.indexOf(':', keyIndex + key.length());
  if (colonIndex < 0) {
    return false;
  }

  int endIndex = colonIndex + 1;
  while (endIndex < payload.length()) {
    const char valueChar = payload.charAt(endIndex);
    if ((valueChar >= '0' && valueChar <= '9') || valueChar == '-' || valueChar == '.') {
      endIndex += 1;
      continue;
    }
    break;
  }

  if (endIndex <= colonIndex + 1) {
    return false;
  }

  outValue = payload.substring(colonIndex + 1, endIndex).toFloat();
  return true;
}

bool extractStringValue(const String& payload, const String& key, String& outValue) {
  const int keyIndex = payload.indexOf(key);
  if (keyIndex < 0) {
    return false;
  }

  const int colonIndex = payload.indexOf(':', keyIndex + key.length());
  const int quoteStart = payload.indexOf('"', colonIndex + 1);
  const int quoteEnd = payload.indexOf('"', quoteStart + 1);
  if (colonIndex < 0 || quoteStart < 0 || quoteEnd < 0) {
    return false;
  }

  outValue = payload.substring(quoteStart + 1, quoteEnd);
  return true;
}

bool extractColorValue(const String& payload, const String& key, int& outRed, int& outGreen, int& outBlue) {
  const int keyIndex = payload.indexOf(key);
  if (keyIndex < 0) {
    return false;
  }

  const int bracketStart = payload.indexOf('[', keyIndex + key.length());
  const int bracketEnd = payload.indexOf(']', bracketStart + 1);
  if (bracketStart < 0 || bracketEnd < 0) {
    return false;
  }

  const String colorPayload = payload.substring(bracketStart + 1, bracketEnd);
  int firstComma = colorPayload.indexOf(',');
  int secondComma = colorPayload.indexOf(',', firstComma + 1);
  if (firstComma < 0 || secondComma < 0) {
    return false;
  }

  outRed = colorPayload.substring(0, firstComma).toInt();
  outGreen = colorPayload.substring(firstComma + 1, secondComma).toInt();
  outBlue = colorPayload.substring(secondComma + 1).toInt();
  return true;
}

bool parseJsonPayload(const String& payload, LaserPacket& nextPacket) {
  float pitchDeg = SAFE_PITCH_DEG;
  float yawDeg = SAFE_YAW_DEG;
  float intensity = 0.0f;
  String mode = "SAFE";
  int red = 0;
  int green = 0;
  int blue = 0;

  const bool hasPitch = extractFloatValue(payload, "\"p\"", pitchDeg);
  const bool hasYaw = extractFloatValue(payload, "\"y\"", yawDeg);
  const bool hasColor = extractColorValue(payload, "\"c\"", red, green, blue);
  const bool hasIntensity = extractFloatValue(payload, "\"i\"", intensity);
  const bool hasMode = extractStringValue(payload, "\"m\"", mode);

  if (!hasPitch || !hasYaw || !hasColor || !hasIntensity || !hasMode) {
    return false;
  }

  nextPacket.pitchDeg = clampFloat(pitchDeg, MIN_PITCH_DEG, MAX_PITCH_DEG);
  nextPacket.yawDeg = clampFloat(yawDeg, MIN_YAW_DEG, MAX_YAW_DEG);
  nextPacket.red = clampInt(red, 0, 255);
  nextPacket.green = clampInt(green, 0, 255);
  nextPacket.blue = clampInt(blue, 0, 255);
  nextPacket.intensity = clampFloat(intensity, 0.0f, 1.0f);
  nextPacket.mode = mode == "RUNNING" ? "RUNNING" : "SAFE";
  return true;
}

bool parseCompactPayload(const String& payload, LaserPacket& nextPacket) {
  float pitchDeg = 0.0f;
  float yawDeg = 0.0f;
  float intensity = 0.0f;
  char modeBuffer[16] = {0};
  int red = 0;
  int green = 0;
  int blue = 0;

  const int matches = sscanf(
    payload.c_str(),
    "P:%f;Y:%f;C:%d,%d,%d;I:%f;M:%15s",
    &pitchDeg,
    &yawDeg,
    &red,
    &green,
    &blue,
    &intensity,
    modeBuffer
  );

  if (matches != 7) {
    return false;
  }

  nextPacket.pitchDeg = clampFloat(pitchDeg, MIN_PITCH_DEG, MAX_PITCH_DEG);
  nextPacket.yawDeg = clampFloat(yawDeg, MIN_YAW_DEG, MAX_YAW_DEG);
  nextPacket.red = clampInt(red, 0, 255);
  nextPacket.green = clampInt(green, 0, 255);
  nextPacket.blue = clampInt(blue, 0, 255);
  nextPacket.intensity = clampFloat(intensity, 0.0f, 1.0f);
  nextPacket.mode = String(modeBuffer) == "RUNNING" ? "RUNNING" : "SAFE";
  return true;
}

void applyPacket(const LaserPacket& packet) {
  currentPacket = packet;

  const int pitchServoDeg = clampInt((int)round(packet.pitchDeg), (int)MIN_PITCH_DEG, (int)MAX_PITCH_DEG);
  const int yawServoDeg = clampInt((int)round(90.0f + packet.yawDeg), 70, 110);
  pitchServo.write(pitchServoDeg);
  yawServo.write(yawServoDeg);

  const float brightness = packet.mode == "RUNNING" ? packet.intensity : 0.0f;
  ledcWrite(PWM_CHANNEL_RED, (uint32_t)round(packet.red * brightness));
  ledcWrite(PWM_CHANNEL_GREEN, (uint32_t)round(packet.green * brightness));
  ledcWrite(PWM_CHANNEL_BLUE, (uint32_t)round(packet.blue * brightness));
}

void enterSafeMode() {
  LaserPacket safePacket;
  applyPacket(safePacket);
}

class LaserCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    std::string rawValue = characteristic->getValue();
    if (rawValue.empty()) {
      return;
    }

    String payload(rawValue.c_str());
    payload.trim();

    LaserPacket nextPacket;
    const bool parsed = payload.startsWith("{")
      ? parseJsonPayload(payload, nextPacket)
      : parseCompactPayload(payload, nextPacket);

    if (!parsed) {
      Serial.print("Invalid laser payload: ");
      Serial.println(payload);
      enterSafeMode();
      return;
    }

    lastCommandAtMs = millis();
    applyPacket(nextPacket);
    characteristic->setValue(nextPacket.mode.c_str());
    characteristic->notify();
  }
};

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    bleClientConnected = true;
    lastCommandAtMs = millis();
    Serial.println("BLE client connected");
  }

  void onDisconnect(BLEServer* server) override {
    bleClientConnected = false;
    enterSafeMode();
    server->startAdvertising();
    Serial.println("BLE client disconnected, safe mode engaged");
  }
};

void setupPwmChannel(int pin, int channel) {
  ledcSetup(channel, PWM_FREQUENCY, PWM_RESOLUTION);
  ledcAttachPin(pin, channel);
  ledcWrite(channel, 0);
}

void setup() {
  Serial.begin(115200);

  pitchServo.setPeriodHertz(50);
  yawServo.setPeriodHertz(50);
  pitchServo.attach(PITCH_SERVO_PIN, 500, 2400);
  yawServo.attach(YAW_SERVO_PIN, 500, 2400);

  setupPwmChannel(LED_RED_PIN, PWM_CHANNEL_RED);
  setupPwmChannel(LED_GREEN_PIN, PWM_CHANNEL_GREEN);
  setupPwmChannel(LED_BLUE_PIN, PWM_CHANNEL_BLUE);
  enterSafeMode();

  BLEDevice::init(DEVICE_NAME);
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService* service = server->createService(SERVICE_UUID);
  laserCharacteristic = service->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ |
      BLECharacteristic::PROPERTY_WRITE |
      BLECharacteristic::PROPERTY_NOTIFY
  );
  laserCharacteristic->addDescriptor(new BLE2902());
  laserCharacteristic->setCallbacks(new LaserCallbacks());
  laserCharacteristic->setValue("SAFE");

  service->start();
  server->getAdvertising()->start();
  Serial.println("BeamChaser ESP32 BLE laser controller ready");
}

void loop() {
  if (!bleClientConnected) {
    delay(20);
    return;
  }

  if (millis() - lastCommandAtMs > COMMAND_TIMEOUT_MS) {
    enterSafeMode();
  }

  delay(20);
}