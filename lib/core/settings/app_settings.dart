import 'package:flutter/foundation.dart';

class AppSettings extends ChangeNotifier {
  int _thresholdCm = 100;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _notificationsEnabled = true;

  int get thresholdCm => _thresholdCm;
  bool get soundEnabled => _soundEnabled;
  bool get vibrationEnabled => _vibrationEnabled;
  bool get notificationsEnabled => _notificationsEnabled;

  void setThresholdCm(int value) {
    final next = value.clamp(30, 300).toInt();
    if (_thresholdCm == next) return;
    _thresholdCm = next;
    notifyListeners();
  }

  void setSoundEnabled(bool value) {
    if (_soundEnabled == value) return;
    _soundEnabled = value;
    notifyListeners();
  }

  void setVibrationEnabled(bool value) {
    if (_vibrationEnabled == value) return;
    _vibrationEnabled = value;
    notifyListeners();
  }

  void setNotificationsEnabled(bool value) {
    if (_notificationsEnabled == value) return;
    _notificationsEnabled = value;
    notifyListeners();
  }
}
