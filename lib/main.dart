import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() => runApp(const MotoTextWifiApp());

const Color _mint = Color(0xFF75F0A0);
const Color _background = Color(0xFF0D1217);
const Color _panel = Color(0xFF171F27);
const Color _edge = Color(0xFF34414E);

// Nordic UART Service (NUS) UUIDs
final Guid _nordicServiceUuid = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
final Guid _nordicRxUuid = Guid('6E400002-B5A3-F393-E0A9-E50E24DCCA9E');
final Guid _nordicTxUuid = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E');
const String _targetDeviceName = 'MotoText-LCD';

class MotoTextWifiApp extends StatelessWidget {
  const MotoTextWifiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _mint,
      brightness: Brightness.dark,
      surface: _panel,
    );
    return MaterialApp(
      title: 'MotoText LCD',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: _background,
        appBarTheme: const AppBarTheme(
          backgroundColor: _background,
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF10161C),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: _edge),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: _edge),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: _mint, width: 1.5),
          ),
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: _mint,
          thumbColor: _mint,
          inactiveTrackColor: _edge,
        ),
      ),
      home: const ControllerPage(),
    );
  }
}

class ControllerPage extends StatefulWidget {
  const ControllerPage({super.key});

  @override
  State<ControllerPage> createState() => _ControllerPageState();
}

class _ControllerPageState extends State<ControllerPage> {
  final _line1Controller = TextEditingController(text: 'JAGA JARAK');
  final _line2Controller = TextEditingController(text: 'TERIMA KASIH');

  String _mode1 = 'scroll';
  String _mode2 = 'scroll';
  String _direction1 = 'rtl';
  String _direction2 = 'ltr';
  double _speed1 = 6;
  double _speed2 = 7;

  // Bluetooth state
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _rxCharacteristic;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _txSubscription;

  bool _isScanning = false;
  bool _isConnecting = false;
  bool _sending = false;
  String _status = 'Bluetooth siap';
  String _lastSent = '';
  List<ScanResult> _scanResults = [];

  bool get _isConnected => _connectedDevice != null && _rxCharacteristic != null;

  @override
  void initState() {
    super.initState();
    _initBle();
  }

  void _initBle() {
    try {
      FlutterBluePlus.adapterState.listen((state) {
        if (!mounted) return;
        if (state != BluetoothAdapterState.on) {
          setState(() {
            _status = 'Bluetooth mati. Silakan nyalakan Bluetooth.';
          });
        }
      }, onError: (e) {
        debugPrint('BLE adapter listener error: $e');
      });
    } catch (e) {
      debugPrint('BLE not supported in this environment: $e');
    }
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _scanSubscription?.cancel();
    _txSubscription?.cancel();
    _line1Controller.dispose();
    _line2Controller.dispose();
    super.dispose();
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _startScan() async {
    if (_isScanning) return;
    FocusScope.of(context).unfocus();

    // Check adapter state
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      _notify('Harap nyalakan Bluetooth HP terlebih dahulu.');
      return;
    }

    setState(() {
      _isScanning = true;
      _scanResults = [];
      _status = 'Memindai perangkat Bluetooth...';
    });

    try {
      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        if (!mounted) return;
        setState(() {
          _scanResults = results;
        });

        // Auto-connect to target device if found
        for (final r in results) {
          final name = r.device.platformName.isNotEmpty
              ? r.device.platformName
              : r.advertisementData.advName;
          if (name == _targetDeviceName && !_isConnecting && !_isConnected) {
            _connectToDevice(r.device);
            break;
          }
        }
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
        withServices: [_nordicServiceUuid],
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Gagal memindai: $e';
        });
        _notify('Error pemindaian BLE: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
          if (!_isConnected && !_isConnecting) {
            _status = _scanResults.isEmpty
                ? 'Tidak ada perangkat ditemukan. Dekatkan HP ke ESP32.'
                : 'Pilih perangkat Bluetooth di daftar.';
          }
        });
      }
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;
    await FlutterBluePlus.stopScan();

    setState(() {
      _isConnecting = true;
      _status = 'Menghubungkan ke ${device.platformName.isEmpty ? device.remoteId.str : device.platformName}...';
    });

    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        if (!mounted) return;
        if (state == BluetoothConnectionState.disconnected) {
          setState(() {
            _connectedDevice = null;
            _rxCharacteristic = null;
            _status = 'Terputus dari perangkat';
          });
          _notify('Koneksi Bluetooth terputus.');
        }
      });

      // Discover services
      final services = await device.discoverServices();
      BluetoothCharacteristic? rxChar;
      BluetoothCharacteristic? txChar;

      for (final service in services) {
        if (service.uuid == _nordicServiceUuid) {
          for (final char in service.characteristics) {
            if (char.uuid == _nordicRxUuid) {
              rxChar = char;
            } else if (char.uuid == _nordicTxUuid) {
              txChar = char;
            }
          }
        }
      }

      if (rxChar == null) {
        throw Exception('Nordic UART Service tidak ditemukan pada perangkat.');
      }

      // Subscribe to TX notification
      if (txChar != null && txChar.properties.notify) {
        await txChar.setNotifyValue(true);
        _txSubscription?.cancel();
        _txSubscription = txChar.lastValueStream.listen((value) {
          if (!mounted || value.isEmpty) return;
          final msg = utf8.decode(value, allowMalformed: true).trim();
          debugPrint('[BLE TX RX]: $msg');
          if (msg.startsWith('OK|')) {
            setState(() {
              _status = 'ESP32: Pengaturan LCD aktif';
            });
          }
        });
      }

      if (mounted) {
        setState(() {
          _connectedDevice = device;
          _rxCharacteristic = rxChar;
          _status = 'Terhubung ke ${device.platformName.isEmpty ? "MotoText-LCD" : device.platformName}';
        });
        _notify('Berhasil terhubung ke ${device.platformName.isEmpty ? "MotoText-LCD" : device.platformName}!');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectedDevice = null;
          _rxCharacteristic = null;
          _status = 'Gagal terhubung: $e';
        });
        _notify('Koneksi gagal: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> _disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      setState(() {
        _connectedDevice = null;
        _rxCharacteristic = null;
        _status = 'Terputus';
      });
      _notify('Bluetooth diputuskan.');
    }
  }

  Future<void> _applySettings() async {
    FocusScope.of(context).unfocus();
    if (_sending) return;

    if (!_isConnected) {
      _notify('Belum terhubung ke Bluetooth ESP32! Tekan "Cari Bluetooth" terlebih dahulu.');
      return;
    }

    final line1 = _line1Controller.text;
    final line2 = _line2Controller.text;
    if (line1.trim().isEmpty && _mode1 != 'blank') {
      _notify('Isi teks baris 1 atau pilih mode Kosongkan baris.');
      return;
    }
    if (line2.trim().isEmpty && _mode2 != 'blank') {
      _notify('Isi teks baris 2 atau pilih mode Kosongkan baris.');
      return;
    }

    setState(() => _sending = true);
    try {
      final payload = 'APPLY|'
          '${line1.replaceAll("|", " ")}|'
          '$_mode1|'
          '$_direction1|'
          '${_speed1.round()}|'
          '${line2.replaceAll("|", " ")}|'
          '$_mode2|'
          '$_direction2|'
          '${_speed2.round()}\n';

      final bytes = utf8.encode(payload);

      // Write to BLE RX characteristic in chunks of up to 100 bytes
      const chunkSize = 100;
      for (int i = 0; i < bytes.length; i += chunkSize) {
        final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        final chunk = bytes.sublist(i, end);
        await _rxCharacteristic!.write(chunk, withoutResponse: false);
      }

      setState(() {
        _lastSent = '${line1.isEmpty ? "(baris 1 kosong)" : line1} / '
            '${line2.isEmpty ? "(baris 2 kosong)" : line2}';
        _status = 'Teks berhasil dikirim ke LCD!';
      });
      _notify('Pengaturan teks LCD berhasil dikirim via BLE!');
    } catch (e) {
      _notify('Gagal mengirim teks ke ESP32: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showDevicePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Pilih Perangkat Bluetooth',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          onPressed: () {
                            _startScan();
                            setModalState(() {});
                          },
                        ),
                      ],
                    ),
                    const Divider(color: _edge),
                    if (_scanResults.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            _isScanning ? 'Mencari perangkat BLE...' : 'Tidak ada perangkat ditemukan',
                            style: const TextStyle(color: Colors.white60),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _scanResults.length,
                          itemBuilder: (context, index) {
                            final r = _scanResults[index];
                            final name = r.device.platformName.isNotEmpty
                                ? r.device.platformName
                                : (r.advertisementData.advName.isNotEmpty
                                    ? r.advertisementData.advName
                                    : 'Perangkat Tanpa Nama');
                            final isTarget = name == _targetDeviceName;
                            return ListTile(
                              leading: Icon(
                                Icons.bluetooth_rounded,
                                color: isTarget ? _mint : Colors.white60,
                              ),
                              title: Text(
                                name,
                                style: TextStyle(
                                  fontWeight: isTarget ? FontWeight.bold : FontWeight.normal,
                                  color: isTarget ? _mint : Colors.white,
                                ),
                              ),
                              subtitle: Text(
                                '${r.device.remoteId.str}  •  RSSI: ${r.rssi} dBm',
                                style: const TextStyle(fontSize: 11, color: Colors.white54),
                              ),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isTarget ? _mint : Colors.white24,
                                  foregroundColor: isTarget ? Colors.black : Colors.white,
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _connectToDevice(r.device);
                                },
                                child: const Text('Connect'),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.bluetooth_audio_rounded, color: _mint, size: 26),
            SizedBox(width: 10),
            Text('MotoText LCD', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: _isConnected
                      ? const Color(0xFF173326)
                      : (_isScanning ? const Color(0xFF332917) : const Color(0xFF252C33)),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: _isConnected
                          ? _mint
                          : (_isScanning ? Colors.amber : Colors.white38),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isConnected
                          ? 'CONNECTED'
                          : (_isScanning ? 'SCANNING' : 'OFFLINE'),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          children: [
            _buildIntro(),
            const SizedBox(height: 18),
            _sectionTitle('KONEKSI BLUETOOTH BLE', icon: Icons.bluetooth_searching_rounded),
            const SizedBox(height: 10),
            _panelBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isConnected
                                  ? (_connectedDevice?.platformName.isNotEmpty == true
                                      ? _connectedDevice!.platformName
                                      : _targetDeviceName)
                                  : 'Target: $_targetDeviceName',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _status,
                              style: TextStyle(
                                color: _isConnected ? _mint : Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_isConnected)
                        OutlinedButton.icon(
                          onPressed: _disconnect,
                          icon: const Icon(Icons.bluetooth_disabled_rounded, size: 16),
                          label: const Text('Putus'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                          ),
                        )
                      else
                        FilledButton.tonalIcon(
                          onPressed: (_isScanning || _isConnecting) ? null : _startScan,
                          icon: (_isScanning || _isConnecting)
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.bluetooth_searching_rounded, size: 18),
                          label: Text(_isScanning
                              ? 'Scan...'
                              : (_isConnecting ? 'Koneksi...' : 'Cari BLE')),
                        ),
                    ],
                  ),
                  if (_scanResults.isNotEmpty && !_isConnected) ...[
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: _showDevicePicker,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2833),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _edge),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.list_alt_rounded, size: 16, color: _mint),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Ditemukan ${_scanResults.length} perangkat (Ketuk untuk memilih)',
                                style: const TextStyle(fontSize: 12, color: Colors.white70),
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white54),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Divider(color: _edge),
                  const SizedBox(height: 6),
                  const Text(
                    'Aktifkan Bluetooth & Lokasi pada HP. Aplikasi akan memindai BLE Nordic UART secara otomatis tanpa perlu pairing manual di Settings HP.',
                    style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _sectionTitle('PENGATURAN DISPLAY LCD', icon: Icons.display_settings_rounded),
            const SizedBox(height: 10),
            _buildLineCard(
              row: 1,
              controller: _line1Controller,
              mode: _mode1,
              direction: _direction1,
              speed: _speed1,
              onMode: (value) => setState(() => _mode1 = value),
              onDirection: (value) => setState(() => _direction1 = value),
              onSpeed: (value) => setState(() => _speed1 = value),
            ),
            const SizedBox(height: 12),
            _buildLineCard(
              row: 2,
              controller: _line2Controller,
              mode: _mode2,
              direction: _direction2,
              speed: _speed2,
              onMode: (value) => setState(() => _mode2 = value),
              onDirection: (value) => setState(() => _direction2 = value),
              onSpeed: (value) => setState(() => _speed2 = value),
            ),
            const SizedBox(height: 16),
            _buildPreview(),
            const SizedBox(height: 15),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _sending ? null : _applySettings,
                icon: _sending
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _sending ? 'Mengirim via BLE...' : 'KIRIM TEKS KE LCD',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _mint,
                  foregroundColor: const Color(0xFF07150B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
            if (_lastSent.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Pengiriman terakhir: $_lastSent',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              'Firmware memakai Bluetooth Low Energy (BLE UART Service). Cocok dengan firmware esp32_lcd_i2c.ino yang terhubung ke ESP32 16x2 LCD via I2C.',
              style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(21),
        gradient: const LinearGradient(
          colors: [Color(0xFF1D3428), Color(0xFF18232A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFF315140)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ubah tulisan LCD via Bluetooth',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21),
          ),
          SizedBox(height: 7),
          Text(
            'Atur dua baris teks, pilih running text atau teks diam, kemudian kirim langsung ke ESP32 lewat koneksi BLE cepat & stabil.',
            style: TextStyle(color: Colors.white70, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, {required IconData icon}) {
    return Row(
      children: [
        Icon(icon, size: 17, color: _mint),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w800,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _panelBox({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: _edge),
      ),
      child: child,
    );
  }

  Widget _buildLineCard({
    required int row,
    required TextEditingController controller,
    required String mode,
    required String direction,
    required double speed,
    required ValueChanged<String> onMode,
    required ValueChanged<String> onDirection,
    required ValueChanged<double> onSpeed,
  }) {
    return _panelBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF23362A),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$row',
                  style: const TextStyle(color: _mint, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'BARIS $row',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            maxLength: 80,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[ -~]'))],
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Teks LCD',
              hintText: 'Contoh: JAGA JARAK',
              counterText: '',
              prefixIcon: Icon(Icons.text_fields_rounded),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: mode,
            decoration: const InputDecoration(labelText: 'Mode display'),
            items: const [
              DropdownMenuItem(value: 'scroll', child: Text('Running text')),
              DropdownMenuItem(value: 'static', child: Text('Teks diam')),
              DropdownMenuItem(value: 'blank', child: Text('Kosongkan baris')),
            ],
            onChanged: (value) {
              if (value != null) onMode(value);
            },
          ),
          if (mode == 'scroll') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: direction,
              decoration: const InputDecoration(labelText: 'Arah teks'),
              items: const [
                DropdownMenuItem(value: 'rtl', child: Text('Kanan ke kiri')),
                DropdownMenuItem(value: 'ltr', child: Text('Kiri ke kanan')),
              ],
              onChanged: (value) {
                if (value != null) onDirection(value);
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: Text('Kecepatan scroll')),
                Text(
                  '${speed.round()} / 10',
                  style: const TextStyle(color: _mint, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            Slider(
              min: 1,
              max: 10,
              divisions: 9,
              value: speed,
              onChanged: onSpeed,
            ),
            const Text(
              '1 = lambat, 10 = cepat',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreview() {
    String preview(String value, String mode) {
      if (mode == 'blank') return '                ';
      if (value.isEmpty) return '                ';
      return value.toUpperCase().padRight(16).substring(0, 16);
    }

    return _panelBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PREVIEW LCD 16×2',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
            decoration: BoxDecoration(
              color: const Color(0xFF102219),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF375442), width: 3),
            ),
            child: Text(
              '${preview(_line1Controller.text, _mode1)}\n'
              '${preview(_line2Controller.text, _mode2)}',
              style: const TextStyle(
                color: _mint,
                fontSize: 14,
                height: 1.8,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
              softWrap: false,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Preview teks diam. Running text akan bergerak otomatis di LCD fisik.',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
