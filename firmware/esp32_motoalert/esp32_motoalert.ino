#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <string.h>
#include <Wire.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// MotoAlert: ESP32 DevKit V1 + 16x2 I2C LCD + HC-SR04 via BLE.
// Semua pin dibuat di SISI KIRI ESP32 supaya rapi satu deret:
// LCD: SDA->GPIO32 (D32), SCL->GPIO33 (D33), VCC->VIN/5V, GND->GND.
// Sensor: TRIG->GPIO25 (D25), ECHO->GPIO26 (D26) through 1k/2k voltage divider.
// Default LCD I2C address is 0x27. Change it to 0x3F if needed.

#define LCD_I2C_ADDRESS 0x27
#define LCD_SDA_PIN 32
#define LCD_SCL_PIN 33
#define LCD_COLUMNS 16
#define LCD_ROWS 2

#define ULTRASONIC_TRIG_PIN 25
#define ULTRASONIC_ECHO_PIN 26
#define DISTANCE_PUBLISH_INTERVAL_MS 250
#define ULTRASONIC_TIMEOUT_US 25000UL

#define SERVICE_UUID        "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_RX   "6E400002-B5A3-F393-E0A9-E50E24DCCA9E" // App writes here
#define CHARACTERISTIC_TX   "6E400003-B5A3-F393-E0A9-E50E24DCCA9E" // ESP32 notifies here
#define BLE_DEVICE_NAME     "MotoAlert-ESP32"

const uint16_t MIN_SCROLL_SPEED_MS = 80;
const uint16_t MAX_SCROLL_SPEED_MS = 1000;
const size_t MAX_TEXT_LENGTH = 80;
const size_t MAX_COMMAND_LENGTH = 180;

// ---------------- Minimal PCF8574 I2C LCD driver ----------------
// Assumed backpack mapping: P0=RS, P1=RW, P2=EN, P3=backlight,
// P4..P7=LCD D4..D7. This matches most common 1602 I2C backpacks.
class BuiltinI2CLCD {
 public:
  BuiltinI2CLCD(uint8_t address, uint8_t columns, uint8_t rows)
      : _address(address), _columns(columns), _rows(rows), _backlight(0x08) {}

  void init() {
    delay(50);
    expanderWrite(0x00);
    delay(5);
    write4bits(0x30);
    delay(5);
    write4bits(0x30);
    delayMicroseconds(150);
    write4bits(0x30);
    delayMicroseconds(150);
    write4bits(0x20);
    command(0x28);
    command(0x08);
    clear();
    command(0x06);
    command(0x0C);
  }

  void backlight() {
    _backlight = 0x08;
    expanderWrite(0x00);
  }

  void clear() {
    command(0x01);
    delay(2);
  }

  void setCursor(uint8_t col, uint8_t row) {
    static const uint8_t rowOffsets[] = {0x00, 0x40, 0x14, 0x54};
    if (row >= _rows) row = _rows - 1;
    if (col >= _columns) col = _columns - 1;
    command(0x80 | (col + rowOffsets[row]));
  }

  size_t print(const String& text) {
    size_t written = 0;
    for (size_t i = 0; i < text.length(); i++) {
      send((uint8_t)text[i], 0x01);
      written++;
    }
    return written;
  }

 private:
  uint8_t _address;
  uint8_t _columns;
  uint8_t _rows;
  uint8_t _backlight;

  void expanderWrite(uint8_t data) {
    Wire.beginTransmission(_address);
    Wire.write(data | _backlight);
    Wire.endTransmission();
  }

  void pulseEnable(uint8_t data) {
    expanderWrite(data | 0x04);
    delayMicroseconds(1);
    expanderWrite(data & (uint8_t)~0x04);
    delayMicroseconds(50);
  }

  void write4bits(uint8_t value) {
    expanderWrite(value);
    pulseEnable(value);
  }

  void send(uint8_t value, uint8_t mode) {
    uint8_t highNibble = (value & 0xF0) | mode;
    uint8_t lowNibble = ((value << 4) & 0xF0) | mode;
    write4bits(highNibble);
    write4bits(lowNibble);
  }

  void command(uint8_t value) { send(value, 0x00); }
};

BuiltinI2CLCD lcd(LCD_I2C_ADDRESS, LCD_COLUMNS, LCD_ROWS);

enum DisplayMode : uint8_t { MODE_SCROLL, MODE_STATIC, MODE_BLANK };
enum ScrollDirection : uint8_t { DIR_RTL, DIR_LTR };

struct LineConfig {
  String text;
  DisplayMode mode;
  ScrollDirection direction;
  uint16_t speedMs;
  int position;
  unsigned long lastStep;
  String lastFrame;
};

LineConfig line1 = {"HELLO FROM ESP32", MODE_SCROLL, DIR_RTL, 489, 0, 0, ""};
LineConfig line2 = {"EDIT ME IN APP", MODE_SCROLL, DIR_LTR, 387, 0, 0, ""};

BLEServer* bleServer = nullptr;
BLECharacteristic* txCharacteristic = nullptr;
volatile bool deviceConnected = false;
bool previousConnectionState = false;
QueueHandle_t commandQueue = nullptr;
unsigned long lastDistancePublishAt = 0;
unsigned long lastStatusNotifyAt = 0;

struct CommandMessage {
  char data[MAX_COMMAND_LENGTH + 1];
};

// Returns -1 when the sensor has no valid echo. HC-SR04 ECHO is 5V logic,
// so GPIO26 must be protected by a divider: ECHO -- 1k -- GPIO26, then
// GPIO26 -- 2k -- GND. All component grounds must be common.
int measureDistanceCm() {
  digitalWrite(ULTRASONIC_TRIG_PIN, LOW);
  delayMicroseconds(3);
  digitalWrite(ULTRASONIC_TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(ULTRASONIC_TRIG_PIN, LOW);

  const unsigned long duration = pulseIn(
      ULTRASONIC_ECHO_PIN, HIGH, ULTRASONIC_TIMEOUT_US);
  if (duration == 0) return -1;

  const float distance = (duration * 0.0343f) / 2.0f;
  const int cm = (int)(distance + 0.5f);
  if (cm < 2 || cm > 400) return -1;
  return cm;
}

void publishDistance(unsigned long now) {
  if (!deviceConnected || txCharacteristic == nullptr) return;
  // Leave a small gap after command/status messages so the shared TX
  // characteristic does not overwrite an acknowledgement in the same loop.
  if (lastStatusNotifyAt != 0 && (unsigned long)(now - lastStatusNotifyAt) < 80) return;
  if ((unsigned long)(now - lastDistancePublishAt) < DISTANCE_PUBLISH_INTERVAL_MS) return;
  lastDistancePublishAt = now;

  const int distanceCm = measureDistanceCm();
  const String packet = String("DIST|") + String(distanceCm);
  txCharacteristic->setValue(packet.c_str());
  txCharacteristic->notify();
}


String cleanText(const String& input) {
  String result;
  result.reserve(MAX_TEXT_LENGTH);
  for (size_t i = 0; i < input.length() && result.length() < MAX_TEXT_LENGTH; i++) {
    const char c = input[i];
    // HD44780 character set is not UTF-8. Keep printable ASCII only.
    if (c >= 32 && c <= 126) result += c;
  }
  return result;
}

uint16_t speedLevelToIntervalMs(int level) {
  if (level < 1) level = 1;
  if (level > 10) level = 10;
  return (uint16_t)map(level, 1, 10, MAX_SCROLL_SPEED_MS, MIN_SCROLL_SPEED_MS);
}

String spaces(uint8_t count) {
  String result;
  result.reserve(count);
  for (uint8_t i = 0; i < count; i++) result += ' ';
  return result;
}

String makeFrame(const LineConfig& cfg) {
  if (cfg.mode == MODE_BLANK) return spaces(LCD_COLUMNS);

  if (cfg.mode == MODE_STATIC) {
    String frame = cfg.text.substring(0, LCD_COLUMNS);
    while (frame.length() < LCD_COLUMNS) frame += ' ';
    return frame;
  }

  String stream = spaces(LCD_COLUMNS);
  stream += cfg.text;
  stream += spaces(LCD_COLUMNS);
  int maxPosition = (int)stream.length() - LCD_COLUMNS;
  int position = constrain(cfg.position, 0, maxPosition);
  String frame = stream.substring(position, position + LCD_COLUMNS);
  while (frame.length() < LCD_COLUMNS) frame += ' ';
  return frame;
}

void renderLine(LineConfig& cfg, int row) {
  String frame = makeFrame(cfg);
  if (frame != cfg.lastFrame) {
    lcd.setCursor(0, row);
    lcd.print(frame);
    cfg.lastFrame = frame;
  }
}

void resetLine(LineConfig& cfg, int row) {
  int maxPosition = (int)cfg.text.length() + LCD_COLUMNS;
  cfg.position = (cfg.direction == DIR_RTL) ? 0 : maxPosition;
  cfg.lastStep = millis();
  cfg.lastFrame = "";
  renderLine(cfg, row);
}

void animateLine(LineConfig& cfg, int row, unsigned long now) {
  if (cfg.mode != MODE_SCROLL) return;
  if ((unsigned long)(now - cfg.lastStep) < cfg.speedMs) return;
  cfg.lastStep = now;
  int maxPosition = (int)cfg.text.length() + LCD_COLUMNS;

  if (cfg.direction == DIR_RTL) {
    cfg.position++;
    if (cfg.position > maxPosition) cfg.position = 0;
  } else {
    cfg.position--;
    if (cfg.position < 0) cfg.position = maxPosition;
  }
  renderLine(cfg, row);
}

void sendStatus(const String& message) {
  Serial.println(message);
  if (deviceConnected && txCharacteristic != nullptr) {
    txCharacteristic->setValue(message.c_str());
    txCharacteristic->notify();
    lastStatusNotifyAt = millis();
  }
}

bool applyLineCommand(const String& command, int row) {
  // Format: SET1|mode|direction|speed|text\n
  int p1 = command.indexOf('|');
  int p2 = command.indexOf('|', p1 + 1);
  int p3 = command.indexOf('|', p2 + 1);
  int p4 = command.indexOf('|', p3 + 1);
  if (p1 < 0 || p2 < 0 || p3 < 0 || p4 < 0) {
    sendStatus("ERR|BAD_FORMAT");
    return false;
  }

  String modeText = command.substring(p1 + 1, p2);
  String dirText = command.substring(p2 + 1, p3);
  int speedLevel = command.substring(p3 + 1, p4).toInt();
  String textValue = cleanText(command.substring(p4 + 1));

  DisplayMode mode;
  if (modeText == "scroll") mode = MODE_SCROLL;
  else if (modeText == "static") mode = MODE_STATIC;
  else if (modeText == "blank") mode = MODE_BLANK;
  else {
    sendStatus("ERR|BAD_MODE");
    return false;
  }

  ScrollDirection direction;
  if (dirText == "rtl") direction = DIR_RTL;
  else if (dirText == "ltr") direction = DIR_LTR;
  else {
    sendStatus("ERR|BAD_DIRECTION");
    return false;
  }

  if (speedLevel < 1 || speedLevel > 10) {
    sendStatus("ERR|BAD_SPEED");
    return false;
  }

  LineConfig& cfg = (row == 1) ? line1 : line2;
  cfg.text = textValue;
  cfg.mode = mode;
  cfg.direction = direction;
  cfg.speedMs = speedLevelToIntervalMs(speedLevel);
  resetLine(cfg, row - 1);
  sendStatus(row == 1 ? "OK|SET1" : "OK|SET2");
  return true;
}

void processCommand(String command) {
  command.trim();
  if (command.length() == 0) return;

  if (command == "PING") {
    sendStatus("PONG|MotoAlert-ESP32");
    return;
  }
  if (command.startsWith("SET1|")) {
    applyLineCommand(command, 1);
    return;
  }
  if (command.startsWith("SET2|")) {
    applyLineCommand(command, 2);
    return;
  }
  if (command == "CLEAR") {
    line1.mode = MODE_BLANK;
    line2.mode = MODE_BLANK;
    resetLine(line1, 0);
    resetLine(line2, 1);
    sendStatus("OK|CLEAR");
    return;
  }

  sendStatus("ERR|UNKNOWN_COMMAND");
}

class MotoAlertServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    deviceConnected = true;
    Serial.println("BLE client connected");
  }

  void onDisconnect(BLEServer* server) override {
    deviceConnected = false;
    Serial.println("BLE client disconnected");
  }
};

class MotoAlertRxCallbacks : public BLECharacteristicCallbacks {
 public:
  void onWrite(BLECharacteristic* characteristic) override {
    // Commands can arrive in multiple BLE writes. Reassemble until newline.
    String value = characteristic->getValue();
    for (size_t i = 0; i < value.length(); i++) {
      char c = value[i];
      if (c == '\r') continue;
      if (c == '\n') {
        CommandMessage message{};
        memcpy(message.data, _lineBuffer, _lineLength);
        message.data[_lineLength] = '\0';
        if (commandQueue != nullptr && _lineLength > 0) {
          if (xQueueSend(commandQueue, &message, 0) != pdTRUE) {
            Serial.println("Command queue full, command dropped");
          }
        }
        _lineLength = 0;
        _lineBuffer[0] = '\0';
      } else if (_lineLength < MAX_COMMAND_LENGTH) {
        _lineBuffer[_lineLength++] = c;
        _lineBuffer[_lineLength] = '\0';
      } else {
        // Discard an overlong line rather than parsing a partial command.
        _lineLength = 0;
        _lineBuffer[0] = '\0';
      }
    }
  }

 private:
  char _lineBuffer[MAX_COMMAND_LENGTH + 1] = {0};
  size_t _lineLength = 0;
};

void setup() {
  Serial.begin(115200);
  pinMode(ULTRASONIC_TRIG_PIN, OUTPUT);
  pinMode(ULTRASONIC_ECHO_PIN, INPUT);
  digitalWrite(ULTRASONIC_TRIG_PIN, LOW);
  Wire.begin(LCD_SDA_PIN, LCD_SCL_PIN);
  lcd.init();
  lcd.backlight();
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Starting BLE...");

  commandQueue = xQueueCreate(8, sizeof(CommandMessage));
  if (commandQueue == nullptr) {
    lcd.clear();
    lcd.print("Queue failed");
    Serial.println("ERROR: Could not create command queue");
    while (true) delay(1000);
  }

  BLEDevice::init(BLE_DEVICE_NAME);
  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new MotoAlertServerCallbacks());

  BLEService* service = bleServer->createService(SERVICE_UUID);

  txCharacteristic = service->createCharacteristic(
      CHARACTERISTIC_TX,
      BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_READ);
  txCharacteristic->addDescriptor(new BLE2902());
  txCharacteristic->setValue("READY|MotoAlert-ESP32");

  BLECharacteristic* rxCharacteristic = service->createCharacteristic(
      CHARACTERISTIC_RX,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  rxCharacteristic->setCallbacks(new MotoAlertRxCallbacks());

  service->start();
  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();

  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("MotoAlert BLE");
  lcd.setCursor(0, 1);
  lcd.print("Waiting phone...");

  Serial.println();
  Serial.println("MotoAlert BLE + HC-SR04 ready");
  Serial.print("Device name: ");
  Serial.println(BLE_DEVICE_NAME);
  Serial.print("Service UUID: ");
  Serial.println(SERVICE_UUID);
  resetLine(line1, 0);
  resetLine(line2, 1);
}

void loop() {
  bool connectedNow = deviceConnected;
  if (!connectedNow && previousConnectionState) {
    delay(250);
    BLEDevice::startAdvertising();
    Serial.println("BLE advertising restarted");
    previousConnectionState = false;
    resetLine(line1, 0);
    resetLine(line2, 1);
  } else if (connectedNow && !previousConnectionState) {
    previousConnectionState = true;
    resetLine(line1, 0);
    resetLine(line2, 1);
    sendStatus("READY|MotoAlert-ESP32");
  }

  CommandMessage message{};
  while (commandQueue != nullptr && xQueueReceive(commandQueue, &message, 0) == pdTRUE) {
    processCommand(String(message.data));
  }

  const unsigned long now = millis();
  animateLine(line1, 0, now);
  animateLine(line2, 1, now);
  publishDistance(now);
  delay(1);
}
