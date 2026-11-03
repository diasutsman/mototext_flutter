import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ble/ble_service.dart';

class LcdControlPage extends StatefulWidget {
  const LcdControlPage({required this.bleService, super.key});

  final BleService bleService;

  @override
  State<LcdControlPage> createState() => _LcdControlPageState();
}

class _LcdControlPageState extends State<LcdControlPage> {
  final TextEditingController _line1Controller = TextEditingController(
    text: 'JAGA JARAK',
  );
  final TextEditingController _line2Controller = TextEditingController(
    text: 'TERIMA KASIH',
  );
  String _mode1 = 'scroll';
  String _mode2 = 'scroll';
  String _direction1 = 'rtl';
  String _direction2 = 'ltr';
  double _speed1 = 6;
  double _speed2 = 7;
  bool _sending = false;
  String _lastResult = '';

  @override
  void dispose() {
    _line1Controller.dispose();
    _line2Controller.dispose();
    super.dispose();
  }

  String _sanitize(String text) {
    final value = text
        .toUpperCase()
        .replaceAll(RegExp(r'[\r\n\t]'), ' ')
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '')
        .trim();
    return value.length > 80 ? value.substring(0, 80) : value;
  }

  Future<void> _apply() async {
    FocusScope.of(context).unfocus();
    if (_sending) return;
    if (!widget.bleService.isConnected) {
      _showMessage('Hubungkan ESP32 di tab Radar terlebih dahulu.');
      return;
    }

    final text1 = _sanitize(_line1Controller.text);
    final text2 = _sanitize(_line2Controller.text);
    if (text1.isEmpty && _mode1 != 'blank') {
      _showMessage('Isi teks baris pertama atau pilih mode Kosong.');
      return;
    }
    if (text2.isEmpty && _mode2 != 'blank') {
      _showMessage('Isi teks baris kedua atau pilih mode Kosong.');
      return;
    }

    setState(() {
      _sending = true;
      _lastResult = 'Mengirim pengaturan ke ESP32...';
    });
    try {
      await widget.bleService.sendCommand(
        'SET1|$_mode1|$_direction1|${_speed1.round()}|$text1\n',
        expectedPrefix: 'OK|SET1',
      );
      await widget.bleService.sendCommand(
        'SET2|$_mode2|$_direction2|${_speed2.round()}|$text2\n',
        expectedPrefix: 'OK|SET2',
      );
      if (!mounted) return;
      setState(() => _lastResult = 'Berhasil mengubah kedua baris LCD.');
      _showMessage('Teks berhasil dikirim ke LCD.');
    } catch (error) {
      if (mounted) {
        setState(() => _lastResult = 'Gagal: $error');
        _showMessage('Pengiriman gagal: $error');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _clear() async {
    if (!widget.bleService.isConnected || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.bleService.sendCommand(
        'CLEAR\n',
        expectedPrefix: 'OK|CLEAR',
      );
      if (mounted) {
        setState(() {
          _mode1 = 'blank';
          _mode2 = 'blank';
          _lastResult = 'LCD dikosongkan.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _lastResult = 'Gagal mengosongkan LCD: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.bleService,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: motoPanel,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: motoEdge),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'LCD 16×2',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.bleService.isConnected
                      ? 'Terhubung dengan ${widget.bleService.deviceName}'
                      : 'Belum terhubung. Hubungkan ESP32 dari tab Radar.',
                  style: const TextStyle(color: Colors.white60, height: 1.4),
                ),
                const SizedBox(height: 15),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF132C1E),
                    border: Border.all(color: const Color(0xFF356849)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      color: Color(0xFF9AFFAE),
                      fontFamily: 'monospace',
                      fontSize: 14,
                      height: 1.8,
                      fontWeight: FontWeight.w700,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(_preview(_line1Controller.text, _mode1)),
                        Text(_preview(_line2Controller.text, _mode2)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _lineCard(
            rowNumber: 1,
            controller: _line1Controller,
            mode: _mode1,
            direction: _direction1,
            speed: _speed1,
            onModeChanged: (value) => setState(() => _mode1 = value),
            onDirectionChanged: (value) => setState(() => _direction1 = value),
            onSpeedChanged: (value) => setState(() => _speed1 = value),
          ),
          const SizedBox(height: 12),
          _lineCard(
            rowNumber: 2,
            controller: _line2Controller,
            mode: _mode2,
            direction: _direction2,
            speed: _speed2,
            onModeChanged: (value) => setState(() => _mode2 = value),
            onDirectionChanged: (value) => setState(() => _direction2 = value),
            onSpeedChanged: (value) => setState(() => _speed2 = value),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: (!widget.bleService.isConnected || _sending)
                  ? null
                  : _apply,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_sending ? 'Mengirim...' : 'KIRIM KE LCD'),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: (!widget.bleService.isConnected || _sending)
                ? null
                : _clear,
            icon: const Icon(Icons.cleaning_services_rounded),
            label: const Text('KOSONGKAN LCD'),
          ),
          if (_lastResult.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _lastResult,
              style: const TextStyle(color: Colors.white60, height: 1.4),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'LCD hanya menampilkan karakter ASCII dasar. Huruf beraksen dan emoji akan dihapus saat dikirim.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  String _preview(String text, String mode) {
    if (mode == 'blank') return '                ';
    final value = _sanitize(text);
    final limited = value.length > 16 ? value.substring(0, 16) : value;
    return limited.padRight(16);
  }

  Widget _lineCard({
    required int rowNumber,
    required TextEditingController controller,
    required String mode,
    required String direction,
    required double speed,
    required ValueChanged<String> onModeChanged,
    required ValueChanged<String> onDirectionChanged,
    required ValueChanged<double> onSpeedChanged,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'BARIS $rowNumber',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
                color: motoCyan,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              maxLength: 80,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Teks',
                hintText: 'Masukkan teks LCD',
                counterText: '',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey<String>('mode_${rowNumber}_$mode'),
              initialValue: mode,
              decoration: const InputDecoration(labelText: 'Mode tampilan'),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'scroll', child: Text('Running text')),
                DropdownMenuItem(value: 'static', child: Text('Teks diam')),
                DropdownMenuItem(
                  value: 'blank',
                  child: Text('Kosongkan baris'),
                ),
              ],
              onChanged: (value) {
                if (value != null) onModeChanged(value);
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey<String>('dir_${rowNumber}_$direction'),
              initialValue: direction,
              decoration: const InputDecoration(labelText: 'Arah running text'),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'rtl', child: Text('Kanan ke kiri')),
                DropdownMenuItem(value: 'ltr', child: Text('Kiri ke kanan')),
              ],
              onChanged: mode == 'scroll'
                  ? (value) {
                      if (value != null) onDirectionChanged(value);
                    }
                  : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Kecepatan scroll',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                Text(
                  '${speed.round()}/10',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            Slider(
              value: speed,
              min: 1,
              max: 10,
              divisions: 9,
              label: speed.round().toString(),
              onChanged: mode == 'scroll' ? onSpeedChanged : null,
            ),
          ],
        ),
      ),
    );
  }
}
