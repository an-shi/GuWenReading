import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guwenreader/core/local/ai_scheduler.dart';
import 'package:guwenreader/core/local/ai_service.dart';
import 'package:guwenreader/core/local/app_database.dart';
import 'package:guwenreader/core/local/local_models.dart';
import 'package:guwenreader/core/local/local_store.dart';

void main() {
  test('global and provider concurrency limits are enforced', () async {
    final scheduler = AiScheduler.instance;
    final original = scheduler.config;
    scheduler.setConfig(
      original.copyWith(
        globalConcurrency: 2,
        providerConcurrency: 1,
        modelConcurrency: 1,
        taskConcurrency: 1,
        minRequestIntervalMs: 0,
      ),
    );
    var running = 0;
    var maxRunning = 0;
    Future<void> job() => scheduler.run<void>(
      providerId: 'p',
      modelId: 'm',
      taskId: 't',
      action: () async {
        running += 1;
        maxRunning = running > maxRunning ? running : maxRunning;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        running -= 1;
      },
    );
    await Future.wait([job(), job(), job(), job()]);
    expect(maxRunning, 1);
    scheduler.setConfig(original);
  });

  test('429 is retried and both attempts are metered', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      requests += 1;
      if (requests == 1) {
        request.response.statusCode = 429;
        request.response.headers.set('retry-after', '0');
        request.response.write(
          jsonEncode({
            'error': {'message': 'rate limited'},
          }),
        );
        await request.response.close();
        return;
      }
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '{"ok":true}'},
            },
          ],
          'usage': {'prompt_tokens': 10, 'completion_tokens': 3},
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
        name: 'Mock',
        kind: 'openai_compatible',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
      ),
    );
    await ai.saveModel(
      AiModelRecord(
        id: newLocalId('model'),
        providerId: providerId,
        name: 'mock-model',
        displayName: 'Mock',
        isDefaultChat: true,
      ),
    );
    final scheduler = AiScheduler.instance;
    final original = scheduler.config;
    await scheduler.saveConfig(
      store,
      original.copyWith(
        minRequestIntervalMs: 0,
        maxRetries: 1,
        baseBackoffMs: 10,
        maxBackoffMs: 50,
      ),
    );
    final client = AiJsonClient(ai);
    final result = await client.chatJson(purpose: 'chat', prompt: '你好');
    expect(result['ok'], true);
    expect(requests, 2);
    final usage = await store.db.query('ai_usage', orderBy: 'created_at ASC');
    expect(usage, hasLength(2));
    expect(usage.first['status'], 'failed');
    expect(usage.last['status'], 'success');
    expect(usage.last['retry_count'], 1);
    await scheduler.saveConfig(store, original);
    await database.close();
    await server.close(force: true);
  });

  test('non-retryable errors are not retried', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests += 1;
      request.response.statusCode = 400;
      request.response.write(
        jsonEncode({
          'error': {'message': 'bad request'},
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
        name: 'Mock',
        kind: 'openai_compatible',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
      ),
    );
    await ai.saveModel(
      AiModelRecord(
        id: newLocalId('model'),
        providerId: providerId,
        name: 'mock-model',
        displayName: 'Mock',
        isDefaultChat: true,
      ),
    );
    final scheduler = AiScheduler.instance;
    final original = scheduler.config;
    await scheduler.saveConfig(
      store,
      original.copyWith(minRequestIntervalMs: 0, maxRetries: 3),
    );
    await expectLater(
      AiJsonClient(ai).chatJson(purpose: 'chat', prompt: '你好'),
      throwsA(isA<AiRequestException>()),
    );
    expect(requests, 1);
    await scheduler.saveConfig(store, original);
    await database.close();
    await server.close(force: true);
  });
}

/// The remaining tests persist scheduler configuration through a real store.
