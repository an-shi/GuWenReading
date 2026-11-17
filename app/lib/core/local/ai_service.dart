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

class RemoteAiModel {
  const RemoteAiModel({
    required this.id,
    required this.displayName,
    this.contextWindow,
    this.maxOutputTokens,
    this.supportsVision = false,
    this.description,
  });

  final String id;
  final String displayName;
  final int? contextWindow;
  final int? maxOutputTokens;
  final bool supportsVision;
  final String? description;
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
    // Older local databases may still contain the English claim categories.
    // Create a localized prompt version instead of mutating the user's history.
    final prompts = await store.allPrompts();
    final assistant = prompts
        .where((prompt) => prompt.key == 'assistant' && prompt.isActive)
        .firstOrNull;
    if (assistant != null &&
        RegExp(r'\b(explicit|inference|analysis|unverified)\b')
            .hasMatch(assistant.template)) {
      final versions = prompts.where((prompt) => prompt.key == 'assistant');
      var nextVersion = 1;
      for (final version in versions) {
        if (version.version >= nextVersion) nextVersion = version.version + 1;
      }
      final localized = assistant.template
          .replaceAll('explicit', '原文明确')
          .replaceAll('inference', '合理推断')
          .replaceAll('analysis', '分析')
          .replaceAll('unverified', '证据不足');
      await store.insertPrompt(
        PromptRecord(
          id: 'prompt-assistant-v$nextVersion-localized',
          key: 'assistant',
          version: nextVersion,
          name: '${assistant.name}（简体中文）',
          description: assistant.description,
          template: localized,
          variables: assistant.variables,
          isActive: false,
        ),
      );
      await store.activatePrompt('assistant', nextVersion);
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

  /// Reads the provider's model catalog with the configured API key.
  ///
  /// OpenAI-compatible providers expose `GET /models`. Ollama uses
  /// `GET /api/tags`, Anthropic uses `GET /models` with its own headers, and
  /// Gemini is read from its native model list so input modalities and token
  /// limits are available.
  Future<List<RemoteAiModel>> fetchModels(AiProviderRecord provider) async {
    final base = provider.baseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    if (base.isEmpty) throw AiRequestException('请先填写接口基础地址');
    final uri = Uri.tryParse(base);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw AiRequestException('接口地址格式不正确');
    }
    if (provider.kind == 'anthropic' && provider.apiKey.trim().isEmpty) {
      throw AiRequestException('Anthropic 需要 API Key 才能读取模型列表');
    }
    if (_isGeminiHost(uri) && provider.apiKey.trim().isEmpty) {
      throw AiRequestException('Gemini 需要 API Key 才能读取模型列表');
    }
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 40),
      ),
    );
    try {
      if (provider.kind == 'ollama') {
        final response = await dio.get<dynamic>(
          base.endsWith('/api') ? '$base/tags' : '$base/api/tags',
          options: Options(headers: _authHeaders(provider)),
        );
        return _parseOllamaModels(response.data);
      }
      if (provider.kind == 'anthropic') {
        final response = await dio.get<dynamic>(
          '$base/models',
          queryParameters: const {'limit': 1000},
          options: Options(
            headers: {
              ..._authHeaders(provider),
              'anthropic-version': '2023-06-01',
            },
          ),
        );
        return _parseCatalog(response.data);
      }
      if (_isGeminiHost(uri)) {
        final origin = '${uri.scheme}://${uri.authority}';
        final response = await dio.get<dynamic>(
          '$origin/v1beta/models',
          queryParameters: {'key': provider.apiKey.trim(), 'pageSize': 1000},
        );
        return _parseGeminiModels(response.data);
      }
      final url = base.endsWith('/models') ? base : '$base/models';
      final response = await dio.get<dynamic>(
        url,
        options: Options(headers: _authHeaders(provider)),
      );
      return _parseCatalog(response.data);
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        throw AiRequestException('认证失败，请检查 API Key 是否正确、是否有读取模型的权限');
      }
      throw AiRequestException(_dioMessage(error));
    } finally {
      dio.close();
    }
  }

  Map<String, String> _authHeaders(AiProviderRecord provider) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (provider.apiKey.trim().isEmpty) return headers;
    if (provider.kind == 'anthropic') {
      headers['x-api-key'] = provider.apiKey.trim();
    } else {
      headers['Authorization'] = 'Bearer ${provider.apiKey.trim()}';
    }
    return headers;
  }

  bool _isGeminiHost(Uri uri) =>
      uri.host.toLowerCase().contains('generativelanguage.googleapis.com');

  List<RemoteAiModel> _parseCatalog(Object? data) {
    final items = switch (data) {
      List() => data,
      Map() =>
        _listValue(data['data']) ??
            _listValue(data['models']) ??
            _listValue(data['items']),
      _ => null,
    };
    if (items == null) throw AiRequestException('服务商返回的模型列表格式无法识别');
    final result = <RemoteAiModel>[];
    final seen = <String>{};
    for (final item in items) {
      final map = _stringMap(item);
      if (map == null) continue;
      final rawId = _firstString(map, const ['id', 'model', 'name', 'slug']);
      if (rawId == null) continue;
      final id = rawId.startsWith('models/') ? rawId.substring(7) : rawId;
      if (!_looksLikeChatModel(id) || !seen.add(id)) continue;
      final topProvider = _stringMap(map['top_provider']);
      final limits = _stringMap(map['limits']);
      final context = _firstPositiveInt([
        map['context_window'],
        map['context_length'],
        map['max_context_length'],
        map['max_input_tokens'],
        map['inputTokenLimit'],
        map['input_token_limit'],
        topProvider?['context_length'],
        limits?['context_window'],
      ]);
      final maxOutput = _firstPositiveInt([
        map['max_output_tokens'],
        map['max_completion_tokens'],
        map['output_token_limit'],
        map['outputTokenLimit'],
        topProvider?['max_completion_tokens'],
        limits?['max_output_tokens'],
      ]);
      final architectureModalities = _stringMap(map['architecture']);
      result.add(
        RemoteAiModel(
          id: id,
          displayName:
              _firstString(map, const [
                'display_name',
                'displayName',
                'label',
                'name',
              ]) ??
              id,
          contextWindow: context,
          maxOutputTokens: maxOutput,
          supportsVision:
              _detectVision(map) ||
              _detectVision(architectureModalities ?? const {}) ||
              _visionIdHint(id),
          description: _firstString(map, const ['description', 'summary']),
        ),
      );
    }
    return _sorted(result);
  }

  List<RemoteAiModel> _parseOllamaModels(Object? data) {
    final map = _stringMap(data);
    final items = map == null ? null : _listValue(map['models']);
    if (items == null) throw AiRequestException('Ollama 返回的模型列表格式无法识别');
    final result = <RemoteAiModel>[];
    final seen = <String>{};
    for (final item in items) {
      final entry = _stringMap(item);
      if (entry == null) continue;
      final id = _firstString(entry, const ['name', 'model']);
      if (id == null || !seen.add(id) || !_looksLikeChatModel(id)) continue;
      final details = _stringMap(entry['details']);
      result.add(
        RemoteAiModel(
          id: id,
          displayName: id,
          contextWindow: _firstPositiveInt([
            entry['context_length'],
            details?['context_length'],
          ]),
          supportsVision: _detectVision(entry) || _visionIdHint(id),
        ),
      );
    }
    return _sorted(result);
  }

  List<RemoteAiModel> _parseGeminiModels(Object? data) {
    final map = _stringMap(data);
    final items = map == null ? null : _listValue(map['models']);
    if (items == null) throw AiRequestException('Gemini 返回的模型列表格式无法识别');
    final result = <RemoteAiModel>[];
    final seen = <String>{};
    for (final item in items) {
      final entry = _stringMap(item);
      if (entry == null) continue;
      final rawId = _firstString(entry, const ['name', 'id']);
      if (rawId == null) continue;
      final id = rawId.startsWith('models/') ? rawId.substring(7) : rawId;
      final methods = _listValue(entry['supportedGenerationMethods']);
      if (methods != null &&
          !methods.map((method) => '$method').contains('generateContent')) {
        continue;
      }
      if (!seen.add(id) || !_looksLikeChatModel(id)) continue;
      result.add(
        RemoteAiModel(
          id: id,
          displayName:
              _firstString(entry, const [
                'displayName',
                'display_name',
                'name',
              ]) ??
              id,
          contextWindow: _firstPositiveInt([
            entry['inputTokenLimit'],
            entry['input_token_limit'],
          ]),
          maxOutputTokens: _firstPositiveInt([
            entry['outputTokenLimit'],
            entry['output_token_limit'],
          ]),
          supportsVision: _detectVision(entry) || _visionIdHint(id),
          description: _firstString(entry, const ['description']),
        ),
      );
    }
    return _sorted(result);
  }

  List<RemoteAiModel> _sorted(List<RemoteAiModel> models) {
    models.sort((a, b) {
      if (a.supportsVision != b.supportsVision) {
        return a.supportsVision ? -1 : 1;
      }
      return a.id.toLowerCase().compareTo(b.id.toLowerCase());
    });
    return models;
  }

  bool _looksLikeChatModel(String id) {
    final lower = id.toLowerCase();
    const excluded = [
      'embedding',
      'embed-',
      'embed_',
      'bge-',
      'rerank',
      'whisper',
      'transcribe',
      'tts',
      'realtime',
      'audio-preview',
      'dall-e',
      'gpt-image',
      'imagen',
      'sora',
      'veo',
      'stable-diffusion',
      'flux',
      'moderation',
      'image-generation',
      'native-image',
      'aqa',
      'ocr',
      ':batch',
    ];
    return !excluded.any(lower.contains);
  }

  bool _detectVision(Map<String, dynamic> map) {
    final values = <Object?>[
      map['vision'],
      map['supports_vision'],
      map['supportsVision'],
      map['supports_image_input'],
      map['supportsImageInput'],
      map['input_modalities'],
      map['supported_input_modalities'],
      map['inputModalities'],
      map['modalities'],
      map['capabilities'],
      map['features'],
      map['tags'],
      _stringMap(map['architecture'])?['input_modalities'],
      _stringMap(map['architecture'])?['modality'],
    ];
    return values.any(_mentionsImage);
  }

  bool _mentionsImage(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is String) {
      final lower = value.toLowerCase();
      return lower.contains('image') ||
          lower.contains('vision') ||
          lower.contains('multimodal') ||
          lower.contains('多模态');
    }
    if (value is Iterable) return value.any(_mentionsImage);
    if (value is Map) {
      for (final entry in value.entries) {
        final key = '${entry.key}'.toLowerCase();
        if ((key == 'vision' ||
                key == 'image' ||
                key == 'image_input' ||
                key == 'image_url') &&
            entry.value == true) {
          return true;
        }
        if (_mentionsImage(entry.value)) return true;
      }
    }
    return false;
  }

  bool _visionIdHint(String id) {
    final lower = id.toLowerCase();
    const hints = [
      'gpt-4o',
      'gpt-4.1',
      'gpt-4-turbo',
      'gpt-4-vision',
      'gpt-5',
      'chatgpt-4o',
      'claude-3',
      'claude-4',
      'claude-sonnet',
      'claude-opus',
      'gemini',
      'gemma-3',
      'qwen-vl',
      'qwen2-vl',
      'qwen2.5-vl',
      'qwen3-vl',
      'qvq',
      'glm-4v',
      'glm-4.1v',
      'glm-4.5v',
      'glm-5v',
      'doubao-vision',
      'vision',
      'llava',
      'pixtral',
      'llama-3.2-vision',
      'llama-4',
      'mistral-small-3',
      'phi-3-vision',
      'phi-4-multimodal',
      'minicpm-v',
      'internvl',
      'kimi-vl',
      'yi-vision',
      'molmo',
      'idefics',
      'step-1v',
    ];
    return hints.any(lower.contains) ||
        RegExp(r'^o[34](?:-|$)').hasMatch(lower);
  }

  Map<String, dynamic>? _stringMap(Object? value) {
    if (value is! Map) return null;
    return {for (final entry in value.entries) '${entry.key}': entry.value};
  }

  List<Object?>? _listValue(Object? value) =>
      value is List ? value.cast<Object?>() : null;

  String? _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  int? _firstPositiveInt(List<Object?> values) {
    for (final value in values) {
      final parsed = switch (value) {
        int() => value,
        num() => value.toInt(),
        String() => int.tryParse(
          RegExp(r'\d+').firstMatch(value)?.group(0) ?? '',
        ),
        _ => null,
      };
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

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
    final headers = _authHeaders(provider);
    if (provider.kind == 'anthropic') {
      headers['anthropic-version'] = '2023-06-01';
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
    if (provider.kind == 'anthropic') return '$base/messages';
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
    if (provider.kind == 'anthropic') {
      final system = messages
          .where((message) => message['role'] == 'system')
          .map((message) => message['content'] ?? '')
          .where((content) => content.trim().isNotEmpty)
          .join('\n\n');
      final conversation = messages
          .where((message) => message['role'] != 'system')
          .toList();
      return {
        'model': model.name,
        'max_tokens': model.maxOutputTokens,
        'temperature': temperature,
        if (system.isNotEmpty) 'system': system,
        'messages': conversation,
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
    if (provider.kind == 'anthropic') {
      final content = data['content'];
      if (content is List) {
        return content
            .whereType<Map>()
            .where((block) => block['type'] == 'text')
            .map((block) => '${block['text'] ?? ''}')
            .join();
      }
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
    if (resolved.apiKey.isNotEmpty) {
      if (resolved.provider.kind == 'anthropic') {
        headers['x-api-key'] = resolved.apiKey;
        headers['anthropic-version'] = '2023-06-01';
      } else {
        headers['Authorization'] = 'Bearer ${resolved.apiKey}';
      }
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
        : resolved.provider.kind == 'anthropic'
        ? '$base/messages'
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
    if (resolved.provider.kind == 'anthropic') {
      return {
        'model': resolved.model.name,
        'max_tokens': resolved.model.maxOutputTokens,
        'temperature': temperature,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
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
    if (resolved.provider.kind == 'anthropic') {
      final content = data['content'];
      if (content is List) {
        return content
            .whereType<Map>()
            .where((block) => block['type'] == 'text')
            .map((block) => '${block['text'] ?? ''}')
            .join();
      }
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
