import 'dart:async';

import 'package:flutter/material.dart';

import 'core/alerts/alert_service.dart';
import 'core/ble/ble_service.dart';
import 'core/settings/app_settings.dart';
import 'core/theme/app_colors.dart';
import 'features/home/home_page.dart';
import 'features/lcd/lcd_control_page.dart';
import 'features/settings/settings_page.dart';

class MotoAlertApp extends StatefulWidget {
  const MotoAlertApp({super.key});

  @override
  State<MotoAlertApp> createState() => _MotoAlertAppState();
}

class _MotoAlertAppState extends State<MotoAlertApp> {
  late final BleService _bleService;
  late final AlertService _alertService;
  late final AppSettings _settings;
  StreamSubscription<int?>? _distanceSubscription;
  int _selectedIndex = 0;
  bool _isNear = false;
  DateTime? _lastAlertAt;

  @override
  void initState() {
    super.initState();
    _bleService = BleService();
    _alertService = AlertService();
    _settings = AppSettings();
    unawaited(
      _alertService.initialize().catchError((Object error) {
        debugPrint('Alert service init failed: $error');
      }),
    );
    _distanceSubscription = _bleService.distanceStream.listen(
      _handleDistanceUpdate,
    );
    _settings.addListener(_reevaluateCurrentDistance);
  }

  void _reevaluateCurrentDistance() {
    _handleDistanceUpdate(_bleService.distanceCm);
  }

  void _handleDistanceUpdate(int? distance) {
    if (!mounted) return;
    final now = DateTime.now();

    if (distance != null && distance <= _settings.thresholdCm) {
      final shouldAlert =
          !_isNear ||
          _lastAlertAt == null ||
          now.difference(_lastAlertAt!) >= const Duration(seconds: 4);
      if (shouldAlert) {
        _lastAlertAt = now;
        unawaited(
          _alertService.triggerProximityAlert(
            distanceCm: distance,
            soundEnabled: _settings.soundEnabled,
            vibrationEnabled: _settings.vibrationEnabled,
            notificationsEnabled: _settings.notificationsEnabled,
          ),
        );
      }
      _isNear = true;
    } else {
      if (_isNear) unawaited(_alertService.clearAlert());
      _isNear = false;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _distanceSubscription?.cancel();
    _settings.removeListener(_reevaluateCurrentDistance);
    _bleService.dispose();
    _settings.dispose();
    unawaited(_alertService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: motoCyan,
        brightness: Brightness.dark,
        surface: motoPanel,
      ),
      scaffoldBackgroundColor: motoBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: motoBackground,
        foregroundColor: Colors.white,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: motoPanel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: motoEdge),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0B1B2B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: motoEdge),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: motoEdge),
        ),
      ),
    );

    final pages = <Widget>[
      HomePage(
        bleService: _bleService,
        alertService: _alertService,
        settings: _settings,
        isNear: _isNear,
      ),
      LcdControlPage(bleService: _bleService),
      SettingsPage(settings: _settings, alertService: _alertService),
    ];

    return MaterialApp(
      title: 'MotoAlert',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        appBar: AppBar(
          title: const Row(
            children: <Widget>[
              Icon(Icons.two_wheeler_rounded, color: motoCyan, size: 27),
              SizedBox(width: 10),
              Text('MotoAlert', style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          actions: <Widget>[
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: AnimatedBuilder(
                  animation: _bleService,
                  builder: (context, _) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _bleService.isConnected
                          ? const Color(0xFF153C37)
                          : const Color(0xFF263544),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      _bleService.isConnected ? 'BLE CONNECTED' : 'BLE OFFLINE',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: IndexedStack(index: _selectedIndex, children: pages),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) =>
              setState(() => _selectedIndex = index),
          destinations: const <NavigationDestination>[
            NavigationDestination(
              icon: Icon(Icons.radar_rounded),
              label: 'Radar',
            ),
            NavigationDestination(
              icon: Icon(Icons.display_settings_rounded),
              label: 'LCD Text',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_rounded),
              label: 'Pengaturan',
            ),
          ],
        ),
      ),
    );
  }
}
