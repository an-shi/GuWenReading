import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guwenreader/core/local/ai_scheduler.dart';
import 'package:guwenreader/core/local/ai_service.dart';
import 'package:guwenreader/core/local/app_database.dart';
import 'package:guwenreader/core/local/local_models.dart';
import 'package:guwenreader/core/local/local_store.dart';

void main() {
  test(
    'Anthropic prompt caching sends cache_control and records cache tokens',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Map<String, dynamic>? captured;
      server.listen((request) async {
        captured = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, dynamic>;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': '连接成功'},
            ],
            'usage': {
              'input_tokens': 12,
              'output_tokens': 4,
              'cache_read_input_tokens': 0,
              'cache_creation_input_tokens': 30,
            },
          }),
        );
        await request.response.close();
      });
      final database = await AppDatabase.openInMemory();
      final store = LocalStore(database);
      final ai = AiSettingsService(store: store);
      final providerId = newLocalId('provider');
      await ai.saveProvider(
        AiProviderRecord(
          id: providerId,
          name: 'Claude Mock',
          kind: 'anthropic',
          baseUrl: 'http://127.0.0.1:${server.port}',
        ),
      );
      final modelId = newLocalId('model');
      await ai.saveModel(
        AiModelRecord(
          id: modelId,
          providerId: providerId,
          name: 'claude-3-5-sonnet',
          displayName: 'Claude Mock',
          isDefaultChat: true,
          promptCaching: true,
          inputPrice: 3,
          outputPrice: 15,
          cacheWritePrice: 3.75,
        ),
      );
      final scheduler = AiScheduler.instance;
      final original = scheduler.config;
      scheduler.setConfig(
        original.copyWith(minRequestIntervalMs: 0, maxRetries: 0),
      );
      final text = await AiJsonClient(
        ai,
      ).chat(purpose: 'chat', prompt: '请回答连接成功', taskType: 'connection_test');
      expect(text, '连接成功');
      final messages = captured!['messages'] as List;
      final content = (messages.first as Map)['content'];
      expect(content, isA<List>());
      expect('$content', contains('ephemeral'));
      final usage = await store.db.query('ai_usage');
      expect(usage.first['cache_write_tokens'], 30);
      expect(usage.first['provider_name'], 'Claude Mock');
      scheduler.setConfig(original);
      await database.close();
      await server.close(force: true);
    },
  );
}
