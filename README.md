# MotoText BLE Controller & ESP32 16x2 LCD

Aplikasi pengontrol layar LCD 16x2 I2C via **Bluetooth Low Energy (BLE UART)** untuk ESP32 menggunakan Flutter.

---

## Fitur Utama

- **Koneksi BLE Cepat**: Menggunakan Nordic UART Service (NUS) untuk transmisi data yang hemat daya dan instan tanpa perlu pairing manual di Pengaturan Bluetooth HP.
- **Dua Baris Independen**:
  - Konfigurasi baris 1 dan baris 2 secara terpisah.
  - Mode: Running Text (Scroll), Teks Diam (Static), atau Kosongkan Baris (Blank).
  - Arah Scroll: Kanan ke Kiri (RTL) atau Kiri ke Kanan (LTR).
  - Kecepatan: Slider kecepatan 1 s.d. 10.
- **Live Monospace Preview**: Simulasi tampilan LCD 16×2 langsung di layar HP secara real-time.
- **Buzzer Feedback**: Konfirmasi bunyi buzzer saat ESP32 menerima konfigurasi teks baru.

---

## Arsitektur BLE (Nordic UART Service)

- **Device Name**: `MotoText-LCD`
- **Service UUID**: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
- **RX Characteristic UUID**: `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` (HP -> ESP32 Write)
- **TX Characteristic UUID**: `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` (ESP32 -> HP Notify)

Format data yang dikirimkan:
```
APPLY|text1|mode1|dir1|speed1|text2|mode2|dir2|speed2\n
```

---

## Wiring Hardware (ESP32 DevKit V1)

1. **LCD 16x2 I2C Backpack**:
   - `GND` -> `GND`
   - `VCC` -> `VIN` (atau `5V`)
   - `SDA` -> `GPIO 21` (D21)
   - `SCL` -> `GPIO 22` (D22)
   - *Catatan: Default alamat I2C adalah `0x27`. Jika tidak muncul teks, periksa alamat I2C dengan I2C Scanner (misalnya `0x3F`).*

2. **Passive Piezo Buzzer**:
   - `Positif (+)` -> `GPIO 15` (D15)
   - `Negatif (-)` -> `GND`

---

## Cara Flash Firmware ESP32

1. Buka file [firmware/esp32_lcd_i2c/esp32_lcd_i2c.ino](firmware/esp32_lcd_i2c/esp32_lcd_i2c.ino) di Arduino IDE.
2. Pilih Board: **ESP32 Dev Module** (atau board ESP32 Anda).
3. Sambungkan ESP32 melalui kabel USB data.
4. Tekan tombol **Upload**.
5. Setelah selesai, layar LCD akan menampilkan:
   ```
   BLE: MotoText-LCD
   Waiting connect
   ```

---

## Cara Menjalankan Aplikasi Flutter

1. Jalankan dependency get:
   ```bash
   flutter pub get
   ```
2. Build dan install APK ke Android:
   ```bash
   ./build_android.sh
   ```
   atau jalankan langsung di emulator/device:
   ```bash
   flutter run
   ```
3. Di dalam aplikasi, tekan tombol **Cari BLE**. Aplikasi akan otomatis mendeteksi dan menghubungkan ke `MotoText-LCD`.
4. Atur teks dan tekan **KIRIM TEKS KE LCD**.
