import 'dart:async';
import 'package:flutter/material.dart';
import 'package:climate_storyteller/core/storage/secure_storage_service.dart';

enum AppThemeMode {
  light,
  dark,
  system;

  String get key => name;

  static AppThemeMode fromKey(String? key) {
    switch (key) {
      case 'dark':
        return AppThemeMode.dark;
      case 'system':
        return AppThemeMode.system;
      case 'light':
      default:
        return AppThemeMode.light;
    }
  }

  ThemeMode get toFlutterThemeMode {
    switch (this) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }
}

class ThemeService {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  // Default to Light mode per user request
  AppThemeMode _currentMode = AppThemeMode.light;
  final _streamCtrl = StreamController<ThemeMode>.broadcast();

  Stream<ThemeMode> get themeStream => _streamCtrl.stream;
  AppThemeMode get currentAppThemeMode => _currentMode;
  ThemeMode get currentThemeMode => _currentMode.toFlutterThemeMode;

  bool get isDarkMode {
    if (_currentMode == AppThemeMode.dark) return true;
    if (_currentMode == AppThemeMode.light) return false;
    // system mode fallback
    final platformBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return platformBrightness == Brightness.dark;
  }

  Future<void> init() async {
    final savedKey = await SecureStorageService.instance.getThemeMode();
    _currentMode = AppThemeMode.fromKey(savedKey);
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    _currentMode = mode;
    await SecureStorageService.instance.saveThemeMode(mode.key);
    _streamCtrl.add(mode.toFlutterThemeMode);
  }
}
