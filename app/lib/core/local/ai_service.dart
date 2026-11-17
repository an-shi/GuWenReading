import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'local_models.dart';
import 'local_store.dart';
import 'prompt_defaults.dart';

class AiNotConfiguredException implements Exception {
  AiNotConfiguredException([this.message = '尚未配置 AI 模型，请先在设置中添加服务商和模型']);
  final String message;
  @override
  String toString() => message;
}

class AiRequestException implements Exception {
  AiRequestException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiSettingsService {
  AiSettingsService({required this.store, FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final LocalStore store;
  final FlutterSecureStorage _storage;

  Future<void> seedPrompts() async {
    final existing = await store.allPrompts();
    final keys = existing.map((prompt) => prompt.key).toSet();
    for (final prompt in defaultPrompts) {
      if (keys.contains(prompt.key)) continue;
      await store.insertPrompt(prompt.toRecord());
    }
  }

  Future<List<AiProviderRecord>> providers() async {
    final rows = await store.listProviders();
    final result = <AiProviderRecord>[];
    for (final provider in rows) {
      final key = await _storage.read(key: _keyName(provider.id)) ?? '';
      result.add(
        AiProviderRecord(
          id: provider.id,
          name: provider.name,
          kind: provider.kind,
          baseUrl: provider.baseUrl,
          notes: provider.notes,
          enabled: provider.enabled,
          apiKey: key,
        ),
      );
    }
    return result;
  }

  Future<void> saveProvider(AiProviderRecord provider) async {
    await store.upsertProvider(provider);
    if (provider.apiKey.trim().isEmpty) {
      await _storage.delete(key: _keyName(provider.id));
    } else {
      await _storage.write(
        key: _keyName(provider.id),
        value: provider.apiKey.trim(),
      );
    }
  }

  Future<void> deleteProvider(String id) async {
    await store.deleteProvider(id);
    await _storage.delete(key: _keyName(id));
  }

  Future<void> saveModel(AiModelRecord model) => store.upsertModel(model);
  Future<void> deleteModel(String id) => store.deleteModel(id);
  Future<List<AiModelRecord>> models() => store.listModels();

  Future<ResolvedAiModel?> resolve({required String purpose}) async {
    final model = await store.defaultModel(purpose);
    if (model == null || !model.enabled) return null;
    final provider = await store.getProvider(model.providerId);
    if (provider == null || !provider.enabled) return null;
    final key = await _storage.read(key: _keyName(provider.id)) ?? '';
    return ResolvedAiModel(model: model, provider: provider, apiKey: key);
  }

  String _keyName(String providerId) => 'guwenreader.ai.$providerId';

  Future<String?> activeTemplate(String key) async {
    final active = await store.activePrompt(key);
    if (active != null) return active.template;
    return defaultPrompts
        .where((prompt) => prompt.key == key)
        .firstOrNull
        ?.template;
  }

  Future<PromptRecord?> activePrompt(String key) async {
    final active = await store.activePrompt(key);
    if (active != null) return active;
    final fallback = await store.promptVersion(key, 1);
    return fallback;
  }

  Future<String> render(String key, Map<String, Object?> variables) async {
    var template = await activeTemplate(key);
    if (template == null) throw AiRequestException('缺少提示词：$key');
    for (final entry in variables.entries) {
      template = template!.replaceAll(
        '{{${entry.key}}}',
        '${entry.value ?? ''}',
      );
    }
    return template!;
  }

  Future<void> testProvider(
    AiProviderRecord provider,
    AiModelRecord model,
  ) async {
    final client = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: Duration(seconds: model.timeoutSeconds),
      ),
    );
    final url = _endpoint(provider, model, stream: false);
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (provider.apiKey.isNotEmpty && provider.kind != 'ollama') {
      headers['Authorization'] = 'Bearer ${provider.apiKey}';
    }
    final body = _body(provider, model, [
      const {'role': 'user', 'content': '请回答“连接成功”，只输出这四个字。'},
    ], jsonMode: false);
    try {
      final response = await client.post<dynamic>(
        url,
        data: body,
        options: Options(headers: headers),
      );
      final text = _extractText(provider, response.data);
      if (text.trim().isEmpty) throw AiRequestException('服务商返回了空响应');
    } on DioException catch (error) {
      throw AiRequestException(_dioMessage(error));
    } finally {
      client.close();
    }
  }

  String _endpoint(
    AiProviderRecord provider,
    AiModelRecord model, {
    required bool stream,
  }) {
    final base = provider.baseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    if (provider.kind == 'ollama') return '$base/api/chat';
    return '$base/chat/completions';
  }

  Map<String, Object?> _body(
    AiProviderRecord provider,
    AiModelRecord model,
    List<Map<String, String>> messages, {
    required bool jsonMode,
    double temperature = 0.2,
  }) {
    if (provider.kind == 'ollama') {
      return {
        'model': model.name,
        'messages': messages,
        'stream': false,
        'options': {
          'temperature': temperature,
          'num_predict': model.maxOutputTokens,
        },
        if (jsonMode) 'format': 'json',
      };
    }
    return {
      'model': model.name,
      'messages': messages,
      'temperature': temperature,
      'max_tokens': model.maxOutputTokens,
      if (jsonMode && model.supportsJson)
        'response_format': {'type': 'json_object'},
    };
  }

  String _extractText(AiProviderRecord provider, dynamic data) {
    if (data is! Map) return '';
    if (provider.kind == 'ollama') {
      final message = data['message'];
      if (message is Map) return '${message['content'] ?? ''}';
      return '';
    }
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final choice = choices.first;
      if (choice is Map) {
        final message = choice['message'];
        if (message is Map) return '${message['content'] ?? ''}';
        return '${choice['text'] ?? ''}';
      }
    }
    return '';
  }

  String _dioMessage(DioException error) {
    final response = error.response;
    final data = response?.data;
    if (data is Map) {
      final detail = data['error'];
      if (detail is Map) return '${detail['message'] ?? detail}';
      if (detail != null) return '$detail';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'AI 服务连接超时';
    }
    if (response?.statusCode != null) {
      return 'AI 服务请求失败（状态码 ${response!.statusCode}）';
    }
    return 'AI 请求失败：${error.message ?? '未知错误'}';
  }
}

class ResolvedAiModel {
  const ResolvedAiModel({
    required this.model,
    required this.provider,
    required this.apiKey,
  });
  final AiModelRecord model;
  final AiProviderRecord provider;
  final String apiKey;

  String get label => '${provider.name} · ${model.displayName}';
}

class AiJsonClient {
  AiJsonClient(this.settings);
  final AiSettingsService settings;

  Future<String> chat({
    required String purpose,
    required String prompt,
    bool jsonMode = false,
    double temperature = 0.2,
  }) async {
    final resolved = await settings.resolve(purpose: purpose);
    if (resolved == null) throw AiNotConfiguredException();
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: Duration(seconds: resolved.model.timeoutSeconds),
      ),
    );
    final url = _endpoint(resolved);
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (resolved.apiKey.isNotEmpty && resolved.provider.kind != 'ollama') {
      headers['Authorization'] = 'Bearer ${resolved.apiKey}';
    }
    final body = _body(
      resolved,
      prompt,
      jsonMode: jsonMode,
      temperature: temperature,
    );
    try {
      final response = await dio.post<dynamic>(
        url,
        data: body,
        options: Options(headers: headers),
      );
      final text = _extractText(resolved, response.data);
      if (text.trim().isEmpty) throw AiRequestException('AI 服务返回了空响应');
      return text;
    } on DioException catch (error) {
      throw AiRequestException(_dioMessage(error));
    } finally {
      dio.close();
    }
  }

  Future<Map<String, dynamic>> chatJson({
    required String purpose,
    required String prompt,
    double temperature = 0.2,
  }) async {
    final text = await chat(
      purpose: purpose,
      prompt: prompt,
      jsonMode: true,
      temperature: temperature,
    );
    return parseJsonObject(text);
  }

  String _endpoint(ResolvedAiModel resolved) {
    final base = resolved.provider.baseUrl.trim().replaceFirst(
      RegExp(r'/$'),
      '',
    );
    return resolved.provider.kind == 'ollama'
        ? '$base/api/chat'
        : '$base/chat/completions';
  }

  Map<String, Object?> _body(
    ResolvedAiModel resolved,
    String prompt, {
    required bool jsonMode,
    required double temperature,
  }) {
    if (resolved.provider.kind == 'ollama') {
      return {
        'model': resolved.model.name,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'stream': false,
        'options': {
          'temperature': temperature,
          'num_predict': resolved.model.maxOutputTokens,
        },
        if (jsonMode) 'format': 'json',
      };
    }
    return {
      'model': resolved.model.name,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'temperature': temperature,
      'max_tokens': resolved.model.maxOutputTokens,
      if (jsonMode && resolved.model.supportsJson)
        'response_format': {'type': 'json_object'},
    };
  }

  String _extractText(ResolvedAiModel resolved, dynamic data) {
    if (data is! Map) return '';
    if (resolved.provider.kind == 'ollama') {
      final message = data['message'];
      if (message is Map) return '${message['content'] ?? ''}';
      return '';
    }
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final choice = choices.first;
      if (choice is Map) {
        final message = choice['message'];
        if (message is Map) return '${message['content'] ?? ''}';
        return '${choice['text'] ?? ''}';
      }
    }
    return '';
  }

  String _dioMessage(DioException error) {
    final response = error.response;
    final data = response?.data;
    if (data is Map) {
      final detail = data['error'];
      if (detail is Map) return '${detail['message'] ?? detail}';
      if (detail != null) return '$detail';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'AI 服务连接超时';
    }
    if (response?.statusCode != null) {
      return 'AI 服务请求失败（状态码 ${response!.statusCode}）';
    }
    return 'AI 请求失败：${error.message ?? '未知错误'}';
  }
}

Map<String, dynamic> parseJsonObject(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
    text = text.replaceFirst(RegExp(r'\s*```$'), '');
  }
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start >= 0 && end > start) text = text.substring(start, end + 1);
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
  } catch (_) {
    // Fall through to a clear domain error.
  }
  throw AiRequestException('AI 返回的内容不是有效 JSON');
}

List<Map<String, dynamic>> jsonList(Object? value) {
  if (value is List) {
    return [
      for (final item in value)
        if (item is Map) item.cast<String, dynamic>(),
    ];
  }
  return const [];
}

String? jsonString(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty || text == 'null' ? null : text;
}

int? jsonInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final match = RegExp(r'-?\d+').firstMatch(value);
    if (match != null) return int.tryParse(match.group(0)!);
  }
  return null;
}

double jsonDouble(Object? value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}
