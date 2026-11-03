# MotoAlert: ESP32 BLE Proximity Warning + LCD Text Controller

MotoAlert is a modular Flutter Android app plus ESP32 firmware. It combines the existing LCD running-text controls with a front-facing HC-SR04 distance sensor. ESP32 sends readings to the phone over Bluetooth Low Energy (BLE). The app displays distance and can play a short sound, vibrate, and post an Android notification when the measured distance enters the configured threshold.

> **Safety:** this is an electronics prototype, not a certified motorcycle collision-warning system. An ordinary HC-SR04 is not weatherproof and can produce false readings due to rain, wind, vibration, angle, soft materials, and road conditions. Test it stationary on a bench first. Do not depend on it as the rider's only warning system or use it as a substitute for safe following distance. For a road-going product, use an automotive-rated waterproof sensor, a protected power supply, sealed enclosure, and extensive stationary testing first.

## Included files

- `lib/main.dart`: Flutter entry point.
- `lib/app.dart`: app shell, bottom navigation, and app-wide proximity alert evaluation.
- `lib/core/ble/ble_service.dart`: Bluetooth scan/connect, command writes, sensor notification parsing.
- `lib/core/ble/ble_constants.dart`: shared BLE UUIDs and protocol constants.
- `lib/core/alerts/alert_service.dart`: sound, vibration, and Android local notifications.
- `lib/core/settings/app_settings.dart`: configurable threshold and alert toggles.
- `lib/features/home/home_page.dart`: connection screen and live sensor distance.
- `lib/features/lcd/lcd_control_page.dart`: two-line LCD editor, scroll mode, direction, speed, clear.
- `lib/features/settings/settings_page.dart`: proximity threshold, sound/vibration/notification settings.
- `firmware/esp32_motoalert/esp32_motoalert.ino`: complete ESP32 BLE + LCD + HC-SR04 firmware.
- `wiring/wiring_diagram.png` and `.svg`: wiring diagram, with a pin table and ECHO voltage divider.
- `assets/audio/proximity_alert.wav`: the alert tone used by the app.

## Hardware assumed

- ESP32 DevKit V1.
- 16x2 character LCD with a PCF8574 I2C backpack.
- HC-SR04 ultrasonic sensor.
- 1 x 1 kΩ resistor and 1 x 2 kΩ resistor for the sensor's ECHO voltage divider.
- Jumper wires and USB power for initial bench testing.
- Android phone that supports Bluetooth LE.

The app-side sound and vibration happen on the phone, so an external buzzer or vibration motor is not needed for this version.

## Wiring

See `wiring/wiring_diagram.png` or open the vector version `wiring/wiring_diagram.svg`.

### LCD 16x2 I2C

| LCD backpack | ESP32 DevKit V1 |
|---|---|
| GND | GND |
| VCC | VIN/5V, if the board supplies 5V and the LCD module supports it |
| SDA | GPIO21 |
| SCL | GPIO22 |

The firmware defaults to I2C address `0x27`. If the LCD backpack uses `0x3F`, change `LCD_I2C_ADDRESS` near the top of the `.ino` file. Some 5V LCD backpacks pull SDA/SCL up to 5V. ESP32 GPIO is 3.3V logic, so verify the backpack pull-up voltage. Add a bidirectional I2C level shifter if the I2C lines are pulled up to 5V.

### HC-SR04 sensor

| HC-SR04 pin | ESP32 connection |
|---|---|
| VCC | VIN/5V |
| GND | GND |
| TRIG | GPIO25 |
| ECHO | GPIO26 through a voltage divider |

**Do not connect HC-SR04 ECHO directly to GPIO26.** Its ECHO signal is nominally 5V. Make a divider: sensor ECHO to a 1 kΩ resistor, resistor's other side to the GPIO26 node, and a 2 kΩ resistor from that node to GND. Connect ESP32 GPIO26 to that same node. This reduces 5V to about 3.3V. All module grounds must be connected together.

No wires are required between the ESP32 and phone for BLE.

## Flash firmware to ESP32

1. Install the Arduino IDE and ESP32 board support from Espressif.
2. Open `firmware/esp32_motoalert/esp32_motoalert.ino`.
3. Select the correct ESP32 DevKit board and serial port.
4. Upload the sketch.
5. Open Serial Monitor at 115200 baud. It should print `MotoAlert BLE + HC-SR04 ready` and advertise as `MotoAlert-ESP32`.
6. Keep the HC-SR04 aimed at a flat test surface while bench testing.

The sketch uses ESP32 Arduino BLE APIs, `Wire`, and FreeRTOS queue functions included with the ESP32 Arduino board package. No separate `LiquidCrystal_I2C` library is required because a small PCF8574 LCD driver is embedded in the sketch.

## Build the Android APK

Requirements: Flutter/Dart SDK, Android SDK, Java supported by your Flutter toolchain, and Python 3 on Linux/macOS/Git Bash. The selected package versions are compatible with a Dart 3.8+ toolchain. Flutter 3.35.2 or newer is recommended.

### Windows PowerShell

From the extracted `motoalert` directory:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\build_android.ps1
```

### Linux/macOS/Git Bash

```bash
./build_android.sh
```

The script creates Android project files if absent using the earlier MotoText Android application ID (`com.mototext.mototext_ble`), so the integrated build can replace the previous MotoText BLE install. It inserts Android BLE/notification/vibration permissions, enables notification-plugin desugaring, downloads Flutter dependencies, formats and analyzes the source, and attempts to build a debug APK. Output path:

`build/app/outputs/flutter-apk/app-debug.apk`

I have not compiled this project against a local Flutter/Android SDK or tested it with physical hardware in this environment. Treat the first build as a verification step and share the full error log if the build fails.

## Use the app

1. Power the ESP32 and the LCD/sensor wiring.
2. Install and open `MotoAlert` on Android.
3. Allow nearby-device/Bluetooth permissions and Android notifications.
4. Open the **Radar** tab and tap **Scan ESP32**.
5. Select `MotoAlert-ESP32` from the results. Wait for distance readings.
6. Put a flat target in front of the sensor at a known distance. Confirm the distance changes.
7. Open **Pengaturan** to choose the alert threshold, sound, vibration, and notification toggles.
8. Press **UJI ALARM SEKARANG** to test the phone alert outputs.
9. Open **LCD Text** to edit two lines, scroll modes, direction, and speed. Tap **KIRIM KE LCD**.

For this v1, keep MotoAlert open in the foreground for the most predictable continuous BLE readings and immediate alert behavior. Android power management can stop background activity or BLE connections, especially on aggressively managed devices. A future road-going version would need a foreground BLE service, connection-loss failsafe behavior, and environmental validation.

## BLE protocol

Both app and firmware use these Nordic-UART-style UUIDs:

- Service: `6e400001-b5a3-f393-e0a9-e50e24dcca9e`
- RX, app writes commands: `6e400002-b5a3-f393-e0a9-e50e24dcca9e`
- TX, ESP32 notifies data/status: `6e400003-b5a3-f393-e0a9-e50e24dcca9e`

Command text is ASCII terminated by newline. The phone sends writes in short packets, and the firmware reassembles until newline.

Examples:

```text
PING
SET1|scroll|rtl|6|JAGA JARAK
SET2|static|ltr|7|TERIMA KASIH
CLEAR
```

Sensor packet every 250 ms while connected:

```text
DIST|123
```

The number is centimeters; `DIST|-1` means the sensor did not get a valid echo. The app won't sound an alarm for invalid or absent distance data. The configured threshold is evaluated in Flutter, so it can be adjusted without reflashing the ESP32.

## Project architecture

- `core/ble`: BLE protocol and device communication only.
- `core/alerts`: Android notification, sound, and haptics only.
- `core/settings`: threshold and alert settings state.
- `features/home`: live sensor and connection UI.
- `features/lcd`: existing LCD text controller feature.
- `features/settings`: alert settings UI.
- `app.dart`: dependency wiring and app-wide monitoring.

## Troubleshooting

- **ESP32 isn't found:** verify it is advertising as `MotoAlert-ESP32`; upload this `.ino`, not the old Wi-Fi sketch. Ensure Android Bluetooth is on and permissions are granted.
- **App connects but shows `--`:** check sensor power, common GND, TRIG GPIO25, ECHO divider to GPIO26, and sensor orientation. A sensor timeout is reported as `DIST|-1`.
- **Distance always looks wrong:** test on a broad flat target about 30–150 cm away. HC-SR04 is not reliable on angled, soft, very narrow, wet, or moving surfaces.
- **LCD doesn't show text:** check SDA GPIO21, SCL GPIO22, I2C voltage compatibility, LCD power, and address `0x27`/`0x3F`.
- **No notification:** check Android notification permission and MotoAlert's notification settings. Press the in-app alarm test button.
- **No sound/vibration:** raise media volume, turn off Do Not Disturb while testing, enable the relevant toggle, and verify the Android notification permission. Check the phone's vibration setting.
- **BLE disconnects with screen off:** disable battery optimization for MotoAlert during bench testing and keep the app in the foreground. This version does not claim a persistent foreground BLE service.
