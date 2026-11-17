import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  const AppSettings({
    this.themeMode = 'paper',
    this.fontSize = 18,
    this.lineHeight = 1.9,
    this.defaultReadingMode = 'alternating',
    this.autoTranslate = false,
    this.loaded = false,
  });

  final String themeMode;
  final double fontSize;
  final double lineHeight;
  final String defaultReadingMode;
  final bool autoTranslate;
  final bool loaded;

  AppSettings copyWith({
    String? themeMode,
    double? fontSize,
    double? lineHeight,
    String? defaultReadingMode,
    bool? autoTranslate,
    bool? loaded,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      defaultReadingMode: defaultReadingMode ?? this.defaultReadingMode,
      autoTranslate: autoTranslate ?? this.autoTranslate,
      loaded: loaded ?? this.loaded,
    );
  }
}

class SettingsController extends Notifier<AppSettings> {
  static const _keyTheme = 'theme_mode';
  static const _keyFont = 'font_size';
  static const _keyLine = 'line_height';
  static const _keyMode = 'default_reading_mode';
  static const _keyAuto = 'auto_translate';

  @override
  AppSettings build() => const AppSettings();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      themeMode: prefs.getString(_keyTheme) ?? 'paper',
      fontSize: prefs.getDouble(_keyFont) ?? 18,
      lineHeight: prefs.getDouble(_keyLine) ?? 1.9,
      defaultReadingMode: prefs.getString(_keyMode) ?? 'alternating',
      autoTranslate: prefs.getBool(_keyAuto) ?? false,
      loaded: true,
    );
  }

  Future<void> setTheme(String value) async {
    state = state.copyWith(themeMode: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTheme, value);
  }

  Future<void> setFontSize(double value) async {
    final size = value.clamp(14, 32).toDouble();
    state = state.copyWith(fontSize: size);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFont, size);
  }

  Future<void> setLineHeight(double value) async {
    final line = value.clamp(1.4, 2.8).toDouble();
    state = state.copyWith(lineHeight: line);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLine, line);
  }

  Future<void> setDefaultReadingMode(String value) async {
    state = state.copyWith(defaultReadingMode: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, value);
  }

  Future<void> setAutoTranslate(bool value) async {
    state = state.copyWith(autoTranslate: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAuto, value);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
