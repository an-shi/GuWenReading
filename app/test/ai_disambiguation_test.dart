import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guwenreader/core/local/ai_service.dart';
import 'package:guwenreader/core/local/app_database.dart';
import 'package:guwenreader/core/local/import_service.dart';
import 'package:guwenreader/core/local/knowledge_service.dart';
import 'package:guwenreader/core/local/local_models.dart';
import 'package:guwenreader/core/local/local_store.dart';
import 'package:guwenreader/data/models.dart';

void main() {
  test(
    'ambiguous entities use AI disambiguation and reuse the chosen row',
    () async {
      final env = await _Environment.start(entityChoice: 2);
      final han = 'ent-han';
      final tang = 'ent-tang';
      await env.store.insertEntity(
        id: han,
        canonicalName: '李四',
        kind: 'person',
        aliases: const [],
        dynasty: '汉',
      );
      await env.store.insertEntity(
        id: tang,
        canonicalName: '李四',
        kind: 'person',
        aliases: const [],
        dynasty: '唐',
      );
      final task = await env.knowledge.startExtraction(env.chapterId);
      final result = await _wait(env.store, task.id);
      expect(result.status, 'completed');
      expect(env.resolvedDisambiguationRequests, 1);
      expect(
        (await env.store.db.rawQuery('SELECT COUNT(*) AS n FROM entities'))
            .first['n'],
        2,
      );
      final rows = await env.store.db.query('entity_disambiguations');
      expect(rows, hasLength(1));
      expect(rows.first['status'], 'auto_matched');
      expect(rows.first['chosen_entity_id'], tang);
      expect(rows.first['confidence'], greaterThanOrEqualTo(0.8));
      await env.close();
    },
  );

  test(
    'unresolved entity is created independently and marked for review',
    () async {
      final env = await _Environment.start(entityChoice: null);
      await env.store.insertEntity(
        id: 'ent-a',
        canonicalName: '李四',
        kind: 'person',
        aliases: const [],
        dynasty: '汉',
      );
      await env.store.insertEntity(
        id: 'ent-b',
        canonicalName: '李四',
        kind: 'person',
        aliases: const [],
        dynasty: '唐',
      );
      final task = await env.knowledge.startExtraction(env.chapterId);
      final result = await _wait(env.store, task.id);
      expect(result.status, 'completed');
      expect(
        (await env.store.db.rawQuery('SELECT COUNT(*) AS n FROM entities'))
            .first['n'],
        3,
      );
      final rows = await env.store.db.query('entity_disambiguations');
      expect(rows.first['status'], 'unresolved');
      expect(rows.first['chosen_entity_id'], isNull);
      await env.close();
    },
  );
}

class _Environment {
  _Environment({
    required this.database,
    required this.store,
    required this.service,
    required this.chapterId,
    required this.server,
  });

  final AppDatabase database;
  final LocalStore store;
  final KnowledgeService service;
  final String chapterId;
  final HttpServer server;

  KnowledgeService get knowledge => service;

  static Future<_Environment> start({required int? entityChoice}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final database = await AppDatabase.openInMemory();
    final store = LocalStore(database);
    final ai = AiSettingsService(store: store);
    await ai.seedPrompts();
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
        displayName: 'Mock Model',
        isDefaultChat: true,
      ),
    );
    final book = await ImportService(store: store, paths: database.paths)
        .importBytes(
          filename: 'test.txt',
          bytes: utf8.encode('第一章 测试\n李四在唐朝任官。李四颇有政声。\n'),
        );
    final chapterId = (await store.listChapters(book.id)).first.id;

    var disambiguationRequests = 0;
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      final messages = payload['messages'] as List? ?? const [];
      final content = messages.isEmpty
          ? ''
          : '${(messages.first as Map)['content'] ?? ''}';
      Map<String, dynamic> result;
      if (content.contains('实体消歧')) {
        disambiguationRequests += 1;
        result = {
          'entity': entityChoice,
          'confidence': entityChoice == null ? 0.2 : 0.9,
          'reason': entityChoice == null ? '同名不同人' : '朝代与事迹一致',
          'merge': entityChoice != null,
        };
      } else if (content.contains('实体类型')) {
        result = {
          'entities': [
            {
              'id': 1,
              'name': '李四',
              'type': 'person',
              'dynasty': '唐',
              'evidence': [1],
            },
          ],
          'relations': <Object>[],
          'events': <Object>[],
        };
      } else {
        result = {'translations': <Object>[]};
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {'content': jsonEncode(result)},
            },
          ],
          'usage': {'prompt_tokens': 30, 'completion_tokens': 10},
        }),
      );
      await request.response.close();
    });

    final service = KnowledgeService(
      store: store,
      aiSettings: ai,
      client: AiJsonClient(ai),
    );
    final env = _Environment(
      database: database,
      store: store,
      service: service,
      chapterId: chapterId,
      server: server,
    );
    // The local counter is kept in the mock closure; read it via a getter.
    env._disambiguationCounter = () => disambiguationRequests;
    return env;
  }

  int Function()? _disambiguationCounter;
  int get resolvedDisambiguationRequests => _disambiguationCounter?.call() ?? 0;

  Future<void> close() async {
    await database.close();
    await server.close(force: true);
  }
}

Future<TaskInfo> _wait(LocalStore store, String taskId) async {
  for (var i = 0; i < 300; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final task = await store.getTask(taskId);
    if (task != null && task.status != 'queued' && task.status != 'running') {
      return task;
    }
  }
  throw StateError('task did not finish');
}
