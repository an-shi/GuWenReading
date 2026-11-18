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
  test('specialized mode calls entity, relation and event prompts', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var entityCalls = 0;
    var relationCalls = 0;
    var eventCalls = 0;
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      final messages = payload['messages'] as List? ?? const [];
      final content = messages.isEmpty
          ? ''
          : '${(messages.first as Map)['content'] ?? ''}';
      Map<String, dynamic> result;
      if (content.contains('古籍实体抽取助手')) {
        entityCalls += 1;
        result = {
          'entities': [
            {
              'name': '张三',
              'type': 'person',
              'aliases': <String>[],
              'evidence': [1],
              'confidence': 0.9,
            },
            {
              'name': '李四',
              'type': 'person',
              'aliases': <String>[],
              'evidence': [2],
              'confidence': 0.9,
            },
          ],
        };
      } else if (content.contains('古籍关系抽取助手')) {
        relationCalls += 1;
        result = {
          'relations': [
            {
              'from': 1,
              'to': 2,
              'type': '君臣关系',
              'description': '君臣',
              'precision': 'unknown',
              'evidence': [1],
              'confidence': 0.8,
            },
          ],
        };
      } else if (content.contains('古籍历史事件抽取助手')) {
        eventCalls += 1;
        result = {
          'events': [
            {
              'name': '测试战役',
              'type': 'war',
              'year': 200,
              'precision': 'year',
              'participants': [1, 2],
              'evidence': [2],
              'confidence': 0.8,
            },
          ],
        };
      } else {
        result = {
          'entities': <Object>[],
          'relations': <Object>[],
          'events': <Object>[],
        };
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {'content': jsonEncode(result)},
            },
          ],
          'usage': {'prompt_tokens': 20, 'completion_tokens': 5},
        }),
      );
      await request.response.close();
    });

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
    final modelId = newLocalId('model');
    await ai.saveModel(
      AiModelRecord(
        id: modelId,
        providerId: providerId,
        name: 'mock-model',
        displayName: 'Mock',
        isDefaultChat: true,
      ),
    );
    await ai.saveKnowledgeRoutingConfig(
      KnowledgeRoutingConfig(
        mode: 'specialized',
        entityModelId: modelId,
        relationModelId: modelId,
        eventModelId: modelId,
      ),
    );
    final book = await ImportService(store: store, paths: database.paths)
        .importBytes(
          filename: 'test.txt',
          bytes: utf8.encode('第一章 测试\n张三为君，李四为臣。二人战于野。\n'),
        );
    final chapter = (await store.listChapters(book.id)).first;
    final service = KnowledgeService(
      store: store,
      aiSettings: ai,
      client: AiJsonClient(ai),
    );
    final task = await service.startExtraction(chapter.id);
    final result = await _wait(store, task.id);
    expect(result.status, 'completed');
    expect(entityCalls, 1);
    expect(relationCalls, 1);
    expect(eventCalls, 1);
    expect(result.result['specialized_calls'], 3);
    expect(
      (await store.db.rawQuery('SELECT COUNT(*) AS n FROM entities'))
          .first['n'],
      2,
    );
    expect(
      (await store.db.rawQuery('SELECT COUNT(*) AS n FROM entity_relations'))
          .first['n'],
      1,
    );
    expect(
      (await store.db.rawQuery('SELECT COUNT(*) AS n FROM historical_events'))
          .first['n'],
      1,
    );
    final routes = await store.routingDecisions();
    expect(
      routes.map((row) => row['task_type']),
      containsAll([
        'entity_extraction',
        'relation_extraction',
        'event_extraction',
      ]),
    );
    await database.close();
    await server.close(force: true);
  });
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
