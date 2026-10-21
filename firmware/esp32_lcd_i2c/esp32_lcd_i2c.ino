#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Wire.h>
#include <math.h>

// ============================================================
// ESP32 DevKit V1 + 16x2 I2C LCD + Passive Buzzer
// Controller interface: Bluetooth Low Energy (BLE UART)
// Nordic UART Service (NUS):
//   Service UUID:        6E400001-B5A3-F393-E0A9-E50E24DCCA9E
//   RX Characteristic:   6E400002-B5A3-F393-E0A9-E50E24DCCA9E (Phone -> ESP32 Write)
//   TX Characteristic:   6E400003-B5A3-F393-E0A9-E50E24DCCA9E (ESP32 -> Phone Notify)
//
// Wiring:
//   LCD I2C: GND -> GND, VCC -> 5V/VIN, SDA -> GPIO21, SCL -> GPIO22
//   Passive Buzzer: Positive -> GPIO15 (D15), Negative -> GND
// ============================================================

#define BLE_DEVICE_NAME        "MotoText-LCD"
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

// LCD Configuration
#define LCD_I2C_ADDRESS 0x27  // Ganti ke 0x3F jika modul I2C Anda menggunakan alamat 0x3F
#define LCD_COLUMNS 16
#define LCD_ROWS 2

#define BUZZER_PIN 15

// Built-in I2C LCD driver for PCF8574
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
    write4bits(0x20);  // Switch to 4-bit mode
    command(0x28);     // 4-bit, 2 lines, 5x8 font
    command(0x08);     // Display off
    clear();
    command(0x06);     // Increment cursor, no display shift
    command(0x0C);     // Display on, cursor off, blink off
  }

  void backlight() {
    _backlight = 0x08;
    expanderWrite(0x00);
  }

  void noBacklight() {
    _backlight = 0x00;
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

  size_t print(const char* text) {
    if (!text) return 0;
    size_t written = 0;
    while (*text) {
      send((uint8_t)*text++, 0x01);
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

  void command(uint8_t value) {
    send(value, 0x00);
  }
};

BuiltinI2CLCD lcd(LCD_I2C_ADDRESS, LCD_COLUMNS, LCD_ROWS);

const uint16_t MIN_SCROLL_SPEED_MS = 80;
const uint16_t MAX_SCROLL_SPEED_MS = 1000;
const size_t MAX_TEXT_LENGTH = 80;
const int MAX_MELODY_NOTES = 240;

enum DisplayMode : uint8_t {
  MODE_SCROLL,
  MODE_STATIC,
  MODE_BLANK
};

enum ScrollDirection : uint8_t {
  DIR_RTL,
  DIR_LTR
};

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
LineConfig line2 = {"BLUETOOTH CONNECTED", MODE_SCROLL, DIR_LTR, 387, 0, 0, ""};

// Buzzer queue
uint16_t melody[MAX_MELODY_NOTES];
uint16_t durations[MAX_MELODY_NOTES];
int melodyCount = 0;
int melodyIndex = 0;
bool melodyPlaying = false;
unsigned long melodyNoteStartedAt = 0;

// BLE Server variables
BLEServer* pServer = nullptr;
BLECharacteristic* pTxCharacteristic = nullptr;
bool deviceConnected = false;
bool oldDeviceConnected = false;
String rxBuffer = "";
bool hasNewSettings = false;

// Forward declarations
void processCommand(const String& cmd);
void notifyClient(const String& message);

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    deviceConnected = true;
    Serial.println("[BLE] Device connected.");
  }

  void onDisconnect(BLEServer* server) override {
    deviceConnected = false;
    Serial.println("[BLE] Device disconnected.");
  }
};

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) override {
    String rxValue = pChar->getValue();
    if (rxValue.length() > 0) {
      for (size_t i = 0; i < rxValue.length(); i++) {
        char c = rxValue[i];
        if (c == '\n' || c == '\r') {
          if (rxBuffer.length() > 0) {
            processCommand(rxBuffer);
            rxBuffer = "";
          }
        } else {
          rxBuffer += c;
        }
      }
    }
  }
};

// ---------------- Helper functions ----------------
String cleanText(String input) {
  String result;
  result.reserve(MAX_TEXT_LENGTH);
  for (size_t i = 0; i < input.length() && result.length() < MAX_TEXT_LENGTH; i++) {
    const char c = input[i];
    if (c >= 32 && c <= 126) result += c;
  }
  return result;
}

uint16_t speedLevelToIntervalMs(int level) {
  if (level < 1) level = 1;
  if (level > 10) level = 10;
  return (uint16_t)map(level, 1, 10, MAX_SCROLL_SPEED_MS, MIN_SCROLL_SPEED_MS);
}

String makeFrame(const LineConfig& cfg) {
  if (cfg.mode == MODE_BLANK) return "                ";

  if (cfg.mode == MODE_STATIC) {
    String frame = cfg.text.substring(0, LCD_COLUMNS);
    while (frame.length() < LCD_COLUMNS) frame += ' ';
    return frame;
  }

  String stream = "                ";
  stream += cfg.text;
  stream += "                ";
  int maxPosition = (int)stream.length() - LCD_COLUMNS;
  int position = cfg.position;
  if (position < 0) position = 0;
  if (position > maxPosition) position = maxPosition;
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

uint16_t midiToFrequency(uint8_t midiNote) {
  if (midiNote == 0) return 0;
  return (uint16_t)lroundf(440.0f * powf(2.0f, ((int)midiNote - 69) / 12.0f));
}

void stopMelody() {
  noTone(BUZZER_PIN);
  melodyPlaying = false;
  melodyCount = 0;
  melodyIndex = 0;
}

void startCurrentNote(unsigned long now) {
  if (melodyIndex >= melodyCount) {
    stopMelody();
    return;
  }
  melodyNoteStartedAt = now;
  const uint16_t frequency = melody[melodyIndex];
  if (frequency == 0) {
    noTone(BUZZER_PIN);
  } else {
    tone(BUZZER_PIN, frequency);
  }
}

void serviceMelody(unsigned long now) {
  if (!melodyPlaying || melodyIndex >= melodyCount) return;

  if ((unsigned long)(now - melodyNoteStartedAt) >= durations[melodyIndex]) {
    noTone(BUZZER_PIN);
    melodyIndex++;
    if (melodyIndex >= melodyCount) {
      stopMelody();
      return;
    }
    startCurrentNote(now);
  }
}

void notifyClient(const String& message) {
  if (deviceConnected && pTxCharacteristic != nullptr) {
    pTxCharacteristic->setValue((uint8_t*)message.c_str(), message.length());
    pTxCharacteristic->notify();
  }
}

// Format command:
// APPLY|text1|mode1|dir1|speed1|text2|mode2|dir2|speed2
// PING
// STOP
void processCommand(const String& rawCmd) {
  String cmd = rawCmd;
  cmd.trim();
  Serial.print("[BLE RX] ");
  Serial.println(cmd);

  if (cmd.startsWith("APPLY|")) {
    // Parsing pipe-delimited parameters
    // Index: 1=text1, 2=mode1, 3=dir1, 4=speed1, 5=text2, 6=mode2, 7=dir2, 8=speed2
    int partsCount = 0;
    String parts[10];
    int start = 0;
    while (start < (int)cmd.length() && partsCount < 10) {
      int pipeIdx = cmd.indexOf('|', start);
      if (pipeIdx < 0) {
        parts[partsCount++] = cmd.substring(start);
        break;
      }
      parts[partsCount++] = cmd.substring(start, pipeIdx);
      start = pipeIdx + 1;
    }

    if (partsCount >= 9) {
      line1.text = cleanText(parts[1]);
      if (parts[2] == "static") line1.mode = MODE_STATIC;
      else if (parts[2] == "blank") line1.mode = MODE_BLANK;
      else line1.mode = MODE_SCROLL;
      line1.direction = (parts[3] == "ltr") ? DIR_LTR : DIR_RTL;
      line1.speedMs = speedLevelToIntervalMs(parts[4].toInt());

      line2.text = cleanText(parts[5]);
      if (parts[6] == "static") line2.mode = MODE_STATIC;
      else if (parts[6] == "blank") line2.mode = MODE_BLANK;
      else line2.mode = MODE_SCROLL;
      line2.direction = (parts[7] == "ltr") ? DIR_LTR : DIR_RTL;
      line2.speedMs = speedLevelToIntervalMs(parts[8].toInt());

      resetLine(line1, 0);
      resetLine(line2, 1);
      hasNewSettings = true;

      // Beep notification to confirm reception
      tone(BUZZER_PIN, 1800, 100);

      notifyClient("OK|SETTINGS_APPLIED\n");
    } else {
      notifyClient("ERR|INVALID_FORMAT\n");
    }
  } else if (cmd == "PING") {
    notifyClient("PONG\n");
  } else if (cmd == "STOP") {
    stopMelody();
    notifyClient("OK|STOPPED\n");
  } else {
    notifyClient("ERR|UNKNOWN_COMMAND\n");
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(BUZZER_PIN, OUTPUT);
  noTone(BUZZER_PIN);

  Wire.begin(21, 22); // SDA=GPIO21, SCL=GPIO22
  lcd.init();
  lcd.backlight();
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("BLE: " BLE_DEVICE_NAME);
  lcd.setCursor(0, 1);
  lcd.print("Waiting connect");

  // Init BLE
  Serial.println("[BLE] Initializing " BLE_DEVICE_NAME "...");
  BLEDevice::init(BLE_DEVICE_NAME);

  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  pTxCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_TX,
      BLECharacteristic::PROPERTY_NOTIFY
  );
  pTxCharacteristic->addDescriptor(new BLE2902());

  BLECharacteristic* pRxCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_RX,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pRxCharacteristic->setCallbacks(new RxCallbacks());

  pService->start();

  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06); // Functions that help with iPhone connections issue
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("[BLE] Ready and advertising. Waiting for client to connect...");

  // Initial beeps
  tone(BUZZER_PIN, 1000, 80);
  delay(120);
  tone(BUZZER_PIN, 1500, 80);
}

void loop() {
  const unsigned long now = millis();

  // Handle connection state changes
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = true;
    Serial.println("[BLE] Client connected. Showing text lines.");
    resetLine(line1, 0);
    resetLine(line2, 1);
  }

  if (!deviceConnected && oldDeviceConnected) {
    delay(500); // Give Bluetooth stack time
    pServer->startAdvertising(); // Restart advertising so clients can reconnect
    Serial.println("[BLE] Restarted advertising after disconnect.");
    oldDeviceConnected = false;
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("BLE: " BLE_DEVICE_NAME);
    lcd.setCursor(0, 1);
    lcd.print("Waiting connect");
  }

  if (deviceConnected) {
    animateLine(line1, 0, now);
    animateLine(line2, 1, now);
  }

  serviceMelody(now);
  delay(5);
}
