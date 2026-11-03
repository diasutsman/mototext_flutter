import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/alerts/alert_service.dart';
import '../../core/settings/app_settings.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.settings,
    required this.alertService,
    super.key,
  });

  final AppSettings settings;
  final AlertService alertService;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Row(
                    children: <Widget>[
                      Icon(Icons.social_distance_rounded, color: motoCyan),
                      SizedBox(width: 9),
                      Text(
                        'Ambang jarak',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Peringatan aktif ketika sensor mendeteksi jarak sama dengan atau lebih kecil dari nilai ini.',
                    style: TextStyle(color: Colors.white60, height: 1.4),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: <Widget>[
                      const Expanded(child: Text('Jarak peringatan')),
                      Text(
                        '${settings.thresholdCm} cm',
                        style: const TextStyle(
                          color: motoCyan,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: settings.thresholdCm.toDouble(),
                    min: 30,
                    max: 300,
                    divisions: 27,
                    label: '${settings.thresholdCm} cm',
                    onChanged: (value) =>
                        settings.setThresholdCm(value.round()),
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        '30 cm',
                        style: TextStyle(fontSize: 11, color: Colors.white38),
                      ),
                      Text(
                        '300 cm',
                        style: TextStyle(fontSize: 11, color: Colors.white38),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: <Widget>[
                SwitchListTile.adaptive(
                  value: settings.notificationsEnabled,
                  onChanged: settings.setNotificationsEnabled,
                  secondary: const Icon(
                    Icons.notifications_active_rounded,
                    color: motoCyan,
                  ),
                  title: const Text('Notifikasi Android'),
                  subtitle: const Text(
                    'Tampilkan peringatan di notifikasi HP.',
                  ),
                ),
                const Divider(height: 1, color: motoEdge),
                SwitchListTile.adaptive(
                  value: settings.soundEnabled,
                  onChanged: settings.setSoundEnabled,
                  secondary: const Icon(
                    Icons.volume_up_rounded,
                    color: motoCyan,
                  ),
                  title: const Text('Suara peringatan'),
                  subtitle: const Text('Memainkan bunyi peringatan singkat.'),
                ),
                const Divider(height: 1, color: motoEdge),
                SwitchListTile.adaptive(
                  value: settings.vibrationEnabled,
                  onChanged: settings.setVibrationEnabled,
                  secondary: const Icon(
                    Icons.vibration_rounded,
                    color: motoCyan,
                  ),
                  title: const Text('Getaran HP'),
                  subtitle: const Text(
                    'Pola getaran ketika objek masuk ambang.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Tes setelan',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tekan tombol berikut untuk memastikan izin notifikasi, speaker, dan getaran HP berfungsi.',
                    style: TextStyle(color: Colors.white60, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => unawaited(
                        alertService.test(
                          soundEnabled: settings.soundEnabled,
                          vibrationEnabled: settings.vibrationEnabled,
                          notificationsEnabled: settings.notificationsEnabled,
                        ),
                      ),
                      icon: const Icon(Icons.play_circle_outline_rounded),
                      label: const Text('UJI ALARM SEKARANG'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF172A3A),
              border: Border.all(color: motoEdge),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'Catatan: setelan ini disimpan selama aplikasi berjalan dan kembali ke nilai awal setelah aplikasi ditutup. Pastikan izin notifikasi aktif dan nonaktifkan pembatasan baterai saat melakukan pengujian. Sensor HC-SR04 bukan komponen otomotif tahan cuaca.',
              style: TextStyle(
                color: Colors.white70,
                height: 1.45,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
