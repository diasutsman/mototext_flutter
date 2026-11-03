import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/alerts/alert_service.dart';
import '../../core/ble/ble_service.dart';
import '../../core/settings/app_settings.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    required this.bleService,
    required this.alertService,
    required this.settings,
    required this.isNear,
    super.key,
  });

  final BleService bleService;
  final AlertService alertService;
  final AppSettings settings;
  final bool isNear;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bleService,
      builder: (context, _) {
        final distance = bleService.distanceCm;
        final near = isNear;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: <Widget>[
            _introCard(),
            const SizedBox(height: 14),
            _distanceCard(
              distanceCm: distance,
              isNear: near,
              hasDistancePacket: bleService.hasDistancePacket,
            ),
            const SizedBox(height: 14),
            _connectionCard(context),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Uji alarm',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Tes suara, getaran, dan notifikasi HP tanpa menunggu sensor mendeteksi objek.',
                      style: TextStyle(color: Colors.white60, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => unawaited(
                          alertService.test(
                            soundEnabled: settings.soundEnabled,
                            vibrationEnabled: settings.vibrationEnabled,
                            notificationsEnabled: settings.notificationsEnabled,
                          ),
                        ),
                        icon: const Icon(Icons.notifications_active_rounded),
                        label: const Text('TES SUARA + GETAR + NOTIFIKASI'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF33291B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF76572B)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFFFC66D)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Prototipe eksperimen, bukan alat keselamatan kendaraan. HC-SR04 biasa tidak tahan hujan/getaran dan bisa salah membaca. Jangan jadikan sistem ini satu-satunya patokan saat berkendara.',
                      style: TextStyle(color: Color(0xFFFFE0AF), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _introCard() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: <Color>[Color(0xFF123A51), Color(0xFF102235)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: motoEdge),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.radar_rounded, color: motoCyan, size: 30),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Peringatan jarak dekat',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Text(
          'ESP32 membaca sensor ultrasonik lalu mengirim jarak ke HP melalui Bluetooth Low Energy.',
          style: TextStyle(color: Colors.white70, height: 1.45),
        ),
      ],
    ),
  );

  Widget _distanceCard({
    required int? distanceCm,
    required bool isNear,
    required bool hasDistancePacket,
  }) {
    final Color accent = isNear ? const Color(0xFFFF5D69) : motoCyan;
    final String value = distanceCm == null ? '--' : '$distanceCm';
    final String state;
    final IconData icon;
    if (distanceCm == null) {
      state = hasDistancePacket
          ? 'Tidak ada pantulan valid dari sensor'
          : 'Menunggu data sensor';
      icon = Icons.sensors_off_rounded;
    } else if (isNear) {
      state = 'OBJEK DEKAT. WASPADA';
      icon = Icons.warning_amber_rounded;
    } else {
      state = 'Di luar ambang peringatan';
      icon = Icons.check_circle_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: isNear ? const Color(0xFF3A1F2B) : motoPanel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isNear ? accent : motoEdge,
          width: isNear ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'JARAK TERBACA',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w800,
                    color: Colors.white60,
                  ),
                ),
              ),
              Icon(icon, color: accent),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                value,
                style: TextStyle(
                  fontSize: 58,
                  fontWeight: FontWeight.w900,
                  color: accent,
                  height: 1.15,
                ),
              ),
              const SizedBox(width: 7),
              const Text(
                'cm',
                style: TextStyle(fontSize: 18, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            state,
            textAlign: TextAlign.center,
            style: TextStyle(color: accent, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 13),
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Ambang alarm',
                  style: TextStyle(color: Colors.white60),
                ),
              ),
              Text(
                '${settings.thresholdCm} cm',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _connectionCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.bluetooth_rounded, color: motoCyan),
                SizedBox(width: 9),
                Text(
                  'Koneksi ESP32',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    bleService.isConnected
                        ? bleService.deviceName
                        : 'MotoAlert-ESP32',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                if (bleService.isConnected)
                  OutlinedButton.icon(
                    onPressed: () => unawaited(bleService.disconnect()),
                    icon: const Icon(Icons.link_off_rounded, size: 17),
                    label: const Text('Putuskan'),
                  )
                else
                  FilledButton.icon(
                    onPressed: bleService.isConnecting
                        ? null
                        : bleService.isScanning
                        ? () => unawaited(bleService.stopScan())
                        : () => unawaited(bleService.scan()),
                    icon: bleService.isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.bluetooth_searching_rounded,
                            size: 18,
                          ),
                    label: Text(
                      bleService.isScanning ? 'Stop scan' : 'Scan ESP32',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              bleService.statusText,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            if (bleService.isConnecting) ...<Widget>[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (!bleService.isConnected &&
                bleService.devices.isNotEmpty) ...<Widget>[
              const Divider(height: 24),
              const Text(
                'PERANGKAT DITEMUKAN',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  color: Colors.white54,
                  fontWeight: FontWeight.w800,
                ),
              ),
              ...bleService.devices.map(
                (device) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    child: Icon(Icons.memory_rounded),
                  ),
                  title: Text(
                    device.name.isEmpty ? 'ESP32 tanpa nama' : device.name,
                  ),
                  subtitle: Text(
                    '${device.id}  •  RSSI ${device.rssi} dBm',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: bleService.isConnecting
                      ? null
                      : () => unawaited(bleService.connect(device)),
                ),
              ),
            ],
            if (bleService.deviceId.isNotEmpty) ...<Widget>[
              const SizedBox(height: 5),
              Text(
                'Device ID: ${bleService.deviceId}',
                style: const TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
