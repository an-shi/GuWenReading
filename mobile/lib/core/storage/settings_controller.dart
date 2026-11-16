import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';

String platformDefaultApiBase() {
  if (Platform.isAndroid) return 'http://10.0.2.2:8765/api/v1';
  if (Platform.isIOS) return 'http://127.0.0.1:8765/api/v1';
  return 'http://127.0.0.1:8765/api/v1';
}

class AppSettings {
  const AppSettings({
    required this.apiBase,
    required this.deviceId,
    this.token,
    this.username,
    this.themeMode = 'paper',
    this.fontSize = 18,
    this.lineHeight = 1.9,
    this.defaultReadingMode = 'alternating',
    this.translationMode = 'shared',
    this.directBaseUrl = 'https://api.openai.com/v1',
    this.directModel = '',
    this.directApiKey = '',
    this.autoTranslate = false,
    this.loaded = false,
  });

  final String apiBase;
  final String deviceId;
  final String? token;
  final String? username;
  final String themeMode;
  final double fontSize;
  final double lineHeight;
  final String defaultReadingMode;
  final String translationMode;
  final String directBaseUrl;
  final String directModel;
  final String directApiKey;
  final bool autoTranslate;
  final bool loaded;

  bool get authenticated => token != null && token!.isNotEmpty;
  bool get directAiConfigured =>
      directBaseUrl.isNotEmpty && directModel.isNotEmpty && directApiKey.isNotEmpty;
  bool get useDirectTranslation => translationMode == 'direct';
  bool get hybridTranslation => translationMode == 'hybrid';

  AppSettings copyWith({
    String? apiBase,
    String? deviceId,
    String? token,
    String? username,
    String? themeMode,
    double? fontSize,
    double? lineHeight,
    String? defaultReadingMode,
    String? translationMode,
    String? directBaseUrl,
    String? directModel,
    String? directApiKey,
    bool? autoTranslate,
    bool? loaded,
    bool clearToken = false,
  }) {
    return AppSettings(
      apiBase: apiBase ?? this.apiBase,
      deviceId: deviceId ?? this.deviceId,
      token: clearToken ? null : (token ?? this.token),
      username: clearToken ? null : (username ?? this.username),
      themeMode: themeMode ?? this.themeMode,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      defaultReadingMode: defaultReadingMode ?? this.defaultReadingMode,
      translationMode: translationMode ?? this.translationMode,
      directBaseUrl: directBaseUrl ?? this.directBaseUrl,
      directModel: directModel ?? this.directModel,
      directApiKey: directApiKey ?? this.directApiKey,
      autoTranslate: autoTranslate ?? this.autoTranslate,
      loaded: loaded ?? this.loaded,
    );
  }
}

class SettingsController extends Notifier<AppSettings> {
  static const _storage = FlutterSecureStorage();
  static const _keyApiBase = 'api_base';
  static const _keyDeviceId = 'device_id';
  static const _keyToken = 'auth_token';
  static const _keyUsername = 'auth_username';
  static const _keyTheme = 'theme_mode';
  static const _keyFont = 'font_size';
  static const _keyLine = 'line_height';
  static const _keyMode = 'default_reading_mode';
  static const _keyTranslationMode = 'translation_mode';
  static const _keyDirectBase = 'direct_base_url';
  static const _keyDirectModel = 'direct_model';
  static const _keyDirectKey = 'direct_api_key';
  static const _keyAuto = 'auto_translate';

  @override
  AppSettings build() {
    return AppSettings(
      apiBase: platformDefaultApiBase(),
      deviceId: '',
    );
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_keyDeviceId);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = 'mobile-${const Uuid().v4()}';
      await prefs.setString(_keyDeviceId, deviceId);
    }
    final token = await _storage.read(key: _keyToken);
    final username = prefs.getString(_keyUsername);
    final directKey = await _storage.read(key: _keyDirectKey) ?? '';
    state = AppSettings(
      apiBase: prefs.getString(_keyApiBase) ?? platformDefaultApiBase(),
      deviceId: deviceId,
      token: token,
      username: username,
      themeMode: prefs.getString(_keyTheme) ?? 'paper',
      fontSize: prefs.getDouble(_keyFont) ?? 18,
      lineHeight: prefs.getDouble(_keyLine) ?? 1.9,
      defaultReadingMode: prefs.getString(_keyMode) ?? 'alternating',
      translationMode: prefs.getString(_keyTranslationMode) ?? 'shared',
      directBaseUrl: prefs.getString(_keyDirectBase) ?? 'https://api.openai.com/v1',
      directModel: prefs.getString(_keyDirectModel) ?? '',
      directApiKey: directKey,
      autoTranslate: prefs.getBool(_keyAuto) ?? false,
      loaded: true,
    );
  }

  Future<void> setApiBase(String value) async {
    final normalized = value.trim().replaceAll(RegExp(r'/$'), '');
    state = state.copyWith(apiBase: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiBase, normalized);
  }

  Future<void> setTheme(String value) async {
    state = state.copyWith(themeMode: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTheme, value);
  }

  Future<void> setFontSize(double value) async {
    final size = value.clamp(14, 28).toDouble();
    state = state.copyWith(fontSize: size);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFont, size);
  }

  Future<void> setLineHeight(double value) async {
    final line = value.clamp(1.4, 2.6).toDouble();
    state = state.copyWith(lineHeight: line);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLine, line);
  }

  Future<void> setDefaultReadingMode(String value) async {
    state = state.copyWith(defaultReadingMode: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, value);
  }

  Future<void> setTranslationMode(String value) async {
    state = state.copyWith(translationMode: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTranslationMode, value);
  }

  Future<void> setDirectAi({
    required String baseUrl,
    required String model,
    required String apiKey,
  }) async {
    final key = apiKey.trim();
    state = state.copyWith(
      directBaseUrl: baseUrl.trim(),
      directModel: model.trim(),
      directApiKey: key.isNotEmpty ? key : state.directApiKey,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDirectBase, baseUrl.trim());
    await prefs.setString(_keyDirectModel, model.trim());
    if (key.isNotEmpty) {
      await _storage.write(key: _keyDirectKey, value: key);
    }
  }

  Future<void> setAutoTranslate(bool value) async {
    state = state.copyWith(autoTranslate: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAuto, value);
  }

  Future<void> saveAuth({required String token, required String username}) async {
    state = state.copyWith(token: token, username: username);
    await _storage.write(key: _keyToken, value: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, username);
  }

  Future<void> logout() async {
    state = state.copyWith(clearToken: true);
    await _storage.delete(key: _keyToken);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsername);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

final apiClientProvider = Provider<ApiClient>((ref) {
  final settings = ref.watch(settingsProvider);
  return ApiClient(
    baseUrl: settings.apiBase,
    token: settings.token,
    deviceId: settings.deviceId,
  );
});
