import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// Nordic-UART-style BLE UUIDs shared by the Flutter app and ESP32 firmware.
const String bleDeviceName = 'MotoAlert-ESP32';
final Uuid bleServiceUuid = Uuid.parse('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
final Uuid bleRxUuid = Uuid.parse('6e400002-b5a3-f393-e0a9-e50e24dcca9e');
final Uuid bleTxUuid = Uuid.parse('6e400003-b5a3-f393-e0a9-e50e24dcca9e');
const int bleWriteChunkSize = 20;
