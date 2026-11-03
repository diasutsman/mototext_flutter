import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble_constants.dart';

/// Owns BLE scan/connect/write/notification handling. UI code never touches
/// FlutterReactiveBle directly, keeping the transport layer modular.
class BleService extends ChangeNotifier {
  BleService({FlutterReactiveBle? ble}) : _ble = ble ?? _createBle() {
    final client = _ble;
    if (client != null) {
      try {
        _bleStatus = client.status;
        _statusSubscription = client.statusStream.listen(
          (status) {
            _bleStatus = status;
            if (status != BleStatus.ready && _connected) {
              _setDisconnected('Bluetooth tidak siap: ${status.name}');
            }
            notifyListeners();
          },
          onError: (Object error) {
            debugPrint('BLE status stream error: $error');
          },
        );
      } catch (e) {
        debugPrint('BLE status initialization skipped: $e');
      }
    }
  }

  static FlutterReactiveBle? _createBle() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }
    try {
      return FlutterReactiveBle();
    } catch (e) {
      debugPrint('FlutterReactiveBle initialization skipped on host: $e');
      return null;
    }
  }

  final FlutterReactiveBle? _ble;
  final Map<String, DiscoveredDevice> _devices = <String, DiscoveredDevice>{};
  final StreamController<int?> _distanceController =
      StreamController<int?>.broadcast();

  StreamSubscription<BleStatus>? _statusSubscription;
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _notificationSubscription;
  Timer? _scanTimer;

  QualifiedCharacteristic? _rxCharacteristic;
  QualifiedCharacteristic? _txCharacteristic;
  Completer<String>? _pendingAck;
  String? _expectedAckPrefix;
  BleStatus _bleStatus = BleStatus.unknown;
  bool _scanning = false;
  bool _connecting = false;
  bool _connected = false;
  bool _manualDisconnect = false;
  int? _distanceCm;
  bool _hasDistancePacket = false;
  String _statusText = 'Belum terhubung';
  String _deviceName = '';
  String _deviceId = '';
  String _lastDeviceMessage = '';

  List<DiscoveredDevice> get devices => _devices.values.toList(growable: false);
  Stream<int?> get distanceStream => _distanceController.stream;
  int? get distanceCm => _distanceCm;
  bool get hasDistancePacket => _hasDistancePacket;
  bool get isScanning => _scanning;
  bool get isConnecting => _connecting;
  bool get isConnected => _connected;
  String get statusText => _statusText;
  String get deviceName => _deviceName;
  String get deviceId => _deviceId;
  String get lastDeviceMessage => _lastDeviceMessage;
  BleStatus get bleStatus => _bleStatus;

  void _setStatus(String value) {
    _statusText = value;
    notifyListeners();
  }

  Future<void> _requestBluetoothPermissions() async {
    if (!Platform.isAndroid) return;

    final android = await DeviceInfoPlugin().androidInfo;
    final Map<Permission, PermissionStatus> results;
    if (android.version.sdkInt >= 31) {
      results = await <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
    } else {
      results = await <Permission>[Permission.locationWhenInUse].request();
    }

    if (results.values.any((status) => !status.isGranted)) {
      throw Exception(
        'Izin Bluetooth ditolak. Aktifkan izin Bluetooth untuk MotoAlert di pengaturan Android.',
      );
    }
  }

  Future<void> scan() async {
    if (_scanning || _connecting || _connected) return;
    _devices.clear();
    _scanning = true;
    _setStatus('Meminta izin dan mencari ESP32...');

    final client = _ble;
    if (client == null) {
      _scanning = false;
      _setStatus('BLE tidak didukung pada platform ini.');
      return;
    }

    try {
      await _requestBluetoothPermissions();
      var currentStatus = client.status;
      if (currentStatus == BleStatus.unknown) {
        currentStatus = await client.statusStream
            .firstWhere((value) => value != BleStatus.unknown)
            .timeout(const Duration(seconds: 6));
      }
      _bleStatus = currentStatus;
      if (currentStatus != BleStatus.ready) {
        throw Exception(
          'Bluetooth belum siap (${currentStatus.name}). Aktifkan Bluetooth HP dan coba lagi.',
        );
      }

      await _scanSubscription?.cancel();
      _scanSubscription = client
          .scanForDevices(
            withServices: <Uuid>[bleServiceUuid],
            scanMode: ScanMode.lowLatency,
          )
          .listen(
            (device) {
              _devices[device.id] = device;
              _statusText = 'Ditemukan ${_devices.length} perangkat';
              notifyListeners();
            },
            onError: (Object error) {
              _scanning = false;
              _statusText = 'Scan gagal: $error';
              notifyListeners();
            },
          );

      _scanTimer?.cancel();
      _scanTimer = Timer(const Duration(seconds: 8), () {
        unawaited(stopScan());
      });
    } catch (error) {
      _scanning = false;
      _statusText = 'Tidak bisa scan: $error';
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _scanning = false;
    if (!_connected) {
      _statusText = _devices.isEmpty
          ? 'ESP32 tidak ditemukan. Pastikan firmware BLE sudah di-upload.'
          : 'Scan selesai. Pilih perangkat untuk terhubung.';
    }
    notifyListeners();
  }

  Future<void> connect(DiscoveredDevice device) async {
    if (_connecting || _connected) return;
    await stopScan();
    _connecting = true;
    _manualDisconnect = false;
    _deviceName = device.name.isEmpty ? bleDeviceName : device.name;
    _deviceId = device.id;
    _setStatus('Menghubungkan ke $_deviceName...');

    final client = _ble;
    if (client == null) {
      _connecting = false;
      _setStatus('BLE tidak didukung pada platform ini.');
      return;
    }

    await _connectionSubscription?.cancel();

    _connectionSubscription = client
        .connectToDevice(
          id: device.id,
          servicesWithCharacteristicsToDiscover: <Uuid, List<Uuid>>{
            bleServiceUuid: <Uuid>[bleRxUuid, bleTxUuid],
          },
          connectionTimeout: const Duration(seconds: 12),
        )
        .listen(
          (update) async {
            if (update.connectionState == DeviceConnectionState.connected) {
              _rxCharacteristic = QualifiedCharacteristic(
                serviceId: bleServiceUuid,
                characteristicId: bleRxUuid,
                deviceId: device.id,
              );
              _txCharacteristic = QualifiedCharacteristic(
                serviceId: bleServiceUuid,
                characteristicId: bleTxUuid,
                deviceId: device.id,
              );
              await _notificationSubscription?.cancel();
              _notificationSubscription = client
                  .subscribeToCharacteristic(_txCharacteristic!)
                  .listen(
                    _handleNotification,
                    onError: (Object error) {
                      _setStatus('Notifikasi BLE gagal: $error');
                    },
                  );
              _connected = true;
              _connecting = false;
              _hasDistancePacket = false;
              _distanceCm = null;
              _setStatus('Terhubung ke $_deviceName. Menunggu data sensor...');
            } else if (update.connectionState ==
                DeviceConnectionState.disconnected) {
              _setDisconnected(
                _manualDisconnect ? 'Terputus' : 'Koneksi ESP32 terputus',
              );
            }
          },
          onError: (Object error) {
            _setDisconnected('Gagal connect: $error');
          },
        );
  }

  void _handleNotification(List<int> bytes) {
    final message = ascii.decode(bytes, allowInvalid: true).trim();
    if (message.isEmpty) return;

    if (message.startsWith('DIST|')) {
      final raw = int.tryParse(message.substring('DIST|'.length).trim());
      _hasDistancePacket = true;
      _distanceCm = (raw != null && raw >= 2 && raw <= 400) ? raw : null;
      _distanceController.add(_distanceCm);
      notifyListeners();
      return;
    }

    _lastDeviceMessage = message;
    if (message.startsWith('ERR|')) {
      _statusText = 'ESP32 menolak perintah: $message';
    } else if (message.startsWith('OK|') || message.startsWith('PONG|')) {
      _statusText = 'ESP32: $message';
    } else {
      _statusText = message;
    }
    notifyListeners();

    final waiter = _pendingAck;
    final expected = _expectedAckPrefix;
    if (waiter != null && !waiter.isCompleted) {
      if (message.startsWith('ERR|') ||
          (expected != null && message.startsWith(expected))) {
        waiter.complete(message);
      }
    }
  }

  Future<String> sendCommand(
    String command, {
    required String expectedPrefix,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final characteristic = _rxCharacteristic;
    if (!_connected || characteristic == null) {
      throw Exception('Hubungkan ke ESP32 lewat Bluetooth terlebih dahulu.');
    }
    if (_pendingAck != null && !_pendingAck!.isCompleted) {
      throw Exception('Perintah sebelumnya belum selesai. Coba lagi sebentar.');
    }

    final client = _ble;
    if (client == null) {
      throw Exception('BLE tidak tersedia pada perangkat/platform ini.');
    }

    final waiter = Completer<String>();
    _pendingAck = waiter;
    _expectedAckPrefix = expectedPrefix;
    try {
      final bytes = ascii.encode(command);
      for (var offset = 0; offset < bytes.length; offset += bleWriteChunkSize) {
        final end = (offset + bleWriteChunkSize < bytes.length)
            ? offset + bleWriteChunkSize
            : bytes.length;
        await client.writeCharacteristicWithResponse(
          characteristic,
          value: bytes.sublist(offset, end),
        );
      }
      final response = await waiter.future.timeout(timeout);
      if (response.startsWith('ERR|')) {
        throw Exception(response);
      }
      return response;
    } finally {
      if (identical(_pendingAck, waiter)) {
        _pendingAck = null;
        _expectedAckPrefix = null;
      }
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _setDisconnected('Terputus');
  }

  void _setDisconnected(String message) {
    _connected = false;
    _connecting = false;
    _rxCharacteristic = null;
    _txCharacteristic = null;
    _distanceCm = null;
    _hasDistancePacket = false;
    _distanceController.add(null);
    final waiter = _pendingAck;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(Exception(message));
    }
    _pendingAck = null;
    _expectedAckPrefix = null;
    _statusText = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    unawaited(_scanSubscription?.cancel());
    unawaited(_notificationSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    unawaited(_statusSubscription?.cancel());
    unawaited(_distanceController.close());
    super.dispose();
  }
}
