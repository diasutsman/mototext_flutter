import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

/// Plays phone-side sound, vibration and Android notifications for proximity
/// events. This is deliberately separate from BLE transport and UI widgets.
class AlertService {
  AlertService();

  static const int _notificationId = 4812;
  static const String _channelId = 'motoalert_proximity';
  static const String _channelName = 'Peringatan jarak';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _initialized = true;
      return;
    }
    try {
      const initializationSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _notifications.initialize(settings: initializationSettings);

      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Peringatan ketika objek terdeteksi dekat sensor.',
          importance: Importance.max,
          playSound: false,
          enableVibration: false,
        ),
      );
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      _initialized = true;
    } catch (e) {
      // In headless tests or unsupported platforms, continue gracefully.
    }
  }

  Future<void> triggerProximityAlert({
    required int distanceCm,
    required bool soundEnabled,
    required bool vibrationEnabled,
    required bool notificationsEnabled,
  }) async {
    await initialize();
    if (soundEnabled) {
      try {
        await _audioPlayer.stop();
        await _audioPlayer.play(AssetSource('audio/proximity_alert.wav'));
      } catch (_) {
        // Notifications and vibration remain available if audio can't start.
      }
    }

    if (vibrationEnabled) {
      try {
        final hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          await Vibration.vibrate(pattern: <int>[0, 250, 100, 250]);
        }
      } catch (_) {
        // Some Android devices or OEM builds can restrict vibration APIs.
      }
    }

    if (notificationsEnabled) {
      await _notifications.show(
        id: _notificationId,
        title: 'PERINGATAN JARAK DEKAT',
        body: 'Objek terdeteksi sekitar $distanceCm cm di depan sensor.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription:
                'Peringatan ketika objek terdeteksi dekat sensor.',
            importance: Importance.max,
            priority: Priority.high,
            playSound: false,
            enableVibration: false,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
          ),
        ),
      );
    }
  }

  Future<void> test({
    required bool soundEnabled,
    required bool vibrationEnabled,
    required bool notificationsEnabled,
  }) async {
    await triggerProximityAlert(
      distanceCm: 42,
      soundEnabled: soundEnabled,
      vibrationEnabled: vibrationEnabled,
      notificationsEnabled: notificationsEnabled,
    );
  }

  Future<void> clearAlert() async {
    try {
      await _notifications.cancel(id: _notificationId);
    } catch (_) {
      // Ignore notification cancellation errors during app teardown.
    }
  }

  Future<void> dispose() async {
    await _audioPlayer.dispose();
  }
}
