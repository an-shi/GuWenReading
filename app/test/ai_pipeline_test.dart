import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guwenreader/core/local/ai_service.dart';
import 'package:guwenreader/core/local/ai_scheduler.dart';
import 'package:guwenreader/core/local/app_database.dart';
import 'package:guwenreader/core/local/budget_service.dart';
import 'package:guwenreader/core/local/import_service.dart';
import 'package:guwenreader/core/local/knowledge_service.dart';
import 'package:guwenreader/core/local/local_models.dart';
import 'package:guwenreader/core/local/local_store.dart';
import 'package:guwenreader/core/local/translation_service.dart';
import 'package:guwenreader/data/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'AI pipeline records usage, reuses caches and extracts jointly',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var translationRequests = 0;
      var knowledgeRequests = 0;
      var failKnowledgeAt = -1;
      var failConnectionTest = false;
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final payload = jsonDecode(body) as Map<String, dynamic>;
        final messages = payload['messages'] as List? ?? const [];
        final content = messages.isEmpty
            ? ''
            : '${(messages.first as Map)['content'] ?? ''}';
        if (content.contains('连接成功') && failConnectionTest) {
          request.response.statusCode = 503;
          request.response.write(
            jsonEncode({
              'error': {'message': 'mock connection failure'},
            }),
          );
          await request.response.close();
          return;
        }
        Map<String, dynamic> result;
        if (content.contains('"entities"') || content.contains('实体类型')) {
          knowledgeRequests += 1;
          if (failKnowledgeAt == knowledgeRequests) {
            request.response.statusCode = 400;
            request.response.write(
              jsonEncode({
                'error': {'message': 'mock failure'},
              }),
            );
            await request.response.close();
            return;
          }
          result = {
            'entities': [
              {
                'id': 1,
                'name': '张三',
                'type': 'person',
                'evidence': [1],
              },
              {
                'id': 2,
                'name': '李四',
                'type': 'person',
                'evidence': [2],
              },
            ],
            'relations': [
              {
                'from': 1,
                'to': 2,
                'type': '君臣关系',
                'evidence': [1],
              },
            ],
            'events': [
              {
                'name': '测试事件',
                'type': 'war',
                'participants': [1, 2],
                'evidence': [2],
              },
            ],
          };
        } else {
          translationRequests += 1;
          final ids = RegExp(r'"id":(\d+)')
              .allMatches(content)
              .map((match) => int.parse(match.group(1)!))
              .toSet()
              .toList();
          result = {
            'translations': [
              for (final id in ids) {'id': id, 'text': '译文$id'},
            ],
          };
        }
        final response = {
          'choices': [
            {
              'message': {'content': jsonEncode(result)},
            },
          ],
          'usage': {
            'prompt_tokens': 120,
            'completion_tokens': 40,
            'total_tokens': 160,
          },
        };
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
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
          name: 'Mock Provider',
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
          contextWindow: 2200,
          maxOutputTokens: 500,
          capabilities: const ['translation', 'chat'],
          isDefaultTranslation: true,
          isDefaultChat: true,
          inputPrice: 10,
          outputPrice: 20,
        ),
      );
      final sample = StringBuffer('第一章 测试\n');
      for (var i = 1; i <= 120; i++) {
        sample.writeln('张三与李四议论第$i件事。李四辅佐张三处理政务。');
      }
      final imported = await ImportService(store: store, paths: database.paths)
          .importBytes(
            filename: 'test.txt',
            bytes: utf8.encode(sample.toString()),
          );
      final chapter = (await store.listChapters(imported.id)).first;
      final content = await store.chapterContent(chapter.id);
      expect(content, isNotNull);
      expect(
        content!.paragraphs.expand((p) => p.sentences).length,
        greaterThan(1),
      );

      final translation = TranslationService(
        store: store,
        aiSettings: ai,
        client: AiJsonClient(ai),
      );
      final translationTask = await translation.startChapterTranslation(
        chapter.id,
      );
      final duplicateTranslation = await translation.startChapterTranslation(
        chapter.id,
      );
      expect(duplicateTranslation.id, translationTask.id);
      final translated = await _waitForTask(store, translationTask.id);
      expect(translated.status, anyOf('completed', 'partial'));
      expect(translationRequests, greaterThan(0));
      expect(translated.inputTokens, greaterThan(0));
      expect(translated.outputTokens, greaterThan(0));
      expect(translated.cost, greaterThan(0));
      expect(translated.estimatedUsage, 0);
      final usageRows = await store.db.query(
        'ai_usage',
        where: 'task_type = ?',
        whereArgs: ['translation'],
        limit: 1,
      );
      expect(usageRows.first['token_source'], 'provider_actual');
      expect(usageRows.first['is_estimated'], 0);
      expect(usageRows.first['prompt_version'], isNotNull);
      expect(usageRows.first['schema_version'], isNotNull);
      final translatedCount = await store.db.rawQuery(
        'SELECT COUNT(*) AS n FROM translations',
      );
      expect(translatedCount.first['n'], greaterThan(0));

      final requestsBeforeCache = translationRequests;
      await store.db.delete('translations');
      await store.db.update('sentences', {'translation_state': 'pending'});
      final cachedTask = await translation.startChapterTranslation(chapter.id);
      final cachedResult = await _waitForTask(store, cachedTask.id);
      expect(cachedResult.status, 'completed');
      expect(translationRequests, requestsBeforeCache);

      await store.db.update(
        'tasks',
        {'status': 'running', 'lease_owner': 'previous-process'},
        where: 'id = ?',
        whereArgs: [cachedTask.id],
      );
      final interrupted = await store.recoverStaleTasks(appInstanceId);
      expect(
        interrupted.any(
          (task) => task.id == cachedTask.id && task.status == 'interrupted',
        ),
        isTrue,
      );
      await translation.resumeTask(cachedTask.id);
      final resumed = await _waitForTask(store, cachedTask.id);
      expect(resumed.status, 'completed');
      expect(translationRequests, requestsBeforeCache);

      final firstSentence = content.paragraphs.first.sentences.first;
      await translation.retranslateSentence(firstSentence.id);
      expect(translationRequests, requestsBeforeCache);
      await translation.retranslateSentence(firstSentence.id, useCache: false);
      expect(translationRequests, requestsBeforeCache + 1);

      final knowledge = KnowledgeService(
        store: store,
        aiSettings: ai,
        client: AiJsonClient(ai),
      );
      final knowledgeTask = await knowledge.startExtraction(chapter.id);
      final duplicateKnowledge = await knowledge.startExtraction(chapter.id);
      expect(duplicateKnowledge.id, knowledgeTask.id);
      final extracted = await _waitForTask(store, knowledgeTask.id);
      expect(extracted.status, 'completed');
      expect(knowledgeRequests, greaterThan(1));
      expect(extracted.inputTokens, greaterThan(0));
      expect(extracted.cost, greaterThan(0));
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
      expect(
        (await store.db.rawQuery('SELECT COUNT(*) AS n FROM event_sources'))
            .first['n'],
        greaterThan(1),
      );
      final entityKnowledge = await store.db.rawQuery(
        'SELECT DISTINCT knowledge_type FROM entities',
      );
      expect(
        entityKnowledge.map((row) => row['knowledge_type']),
        everyElement('explicit'),
      );
      final provenance = await store.db.rawQuery(
        'SELECT task_id, provider_id, model_id, prompt_version, schema_version '
        'FROM event_sources LIMIT 1',
      );
      expect(provenance.first['task_id'], knowledgeTask.id);
      expect(provenance.first['provider_id'], isNotNull);
      expect(provenance.first['model_id'], isNotNull);
      expect(provenance.first['prompt_version'], isNotNull);
      expect(provenance.first['schema_version'], isNotNull);
      final quality = await store.qualityReports();
      expect(quality.any((row) => row['scope'] == 'translation_batch'), isTrue);
      expect(quality.any((row) => row['scope'] == 'knowledge_chunk'), isTrue);
      final routes = await store.routingDecisions();
      expect(
        routes.any((row) => row['task_type'] == 'knowledge_extraction'),
        isTrue,
      );

      final requestsBeforeRepeat = knowledgeRequests;
      final repeatedTask = await knowledge.startExtraction(chapter.id);
      final repeated = await _waitForTask(store, repeatedTask.id);
      expect(repeated.status, 'completed');
      expect(knowledgeRequests, requestsBeforeRepeat);

      await store.db.delete('knowledge_extraction_state');
      await store.db.delete('knowledge_chunk_cache');
      failKnowledgeAt = knowledgeRequests + 2;
      final partialTask = await knowledge.startExtraction(chapter.id);
      final partial = await _waitForTask(store, partialTask.id);
      expect(partial.status, 'partial');
      final requestsBeforeRetry = knowledgeRequests;
      failKnowledgeAt = -1;
      final retryTask = await knowledge.startExtraction(chapter.id);
      final retry = await _waitForTask(store, retryTask.id);
      expect(retry.status, 'completed');
      expect(knowledgeRequests - requestsBeforeRetry, 1);

      SharedPreferences.setMockInitialValues({'ai_task_budget': 0.000001});
      await store.db.delete('translations');
      await store.db.delete('translation_sentence_cache');
      await store.db.delete('translation_cache');
      await store.db.update('sentences', {'translation_state': 'pending'});
      await expectLater(
        translation.startChapterTranslation(chapter.id),
        throwsA(isA<BudgetExceededException>()),
      );
      final rejected = await store.getTask(
        (await store.tasks())
            .firstWhere(
              (task) => task.type == 'translation' && task.status == 'failed',
            )
            .id,
      );
      expect(rejected?.error, contains('预算'));

      final summary = await store.aiUsageSummary();
      expect(summary.requests, greaterThan(0));
      expect(
        summary.byType.any((group) => group.label == 'translation'),
        isTrue,
      );
      expect(
        summary.byType.any((group) => group.label == 'knowledge_extraction'),
        isTrue,
      );

      await ai.testProvider(
        (await ai.providers()).first,
        (await ai.models()).first,
      );
      final connectionRows = await store.db.query(
        'ai_usage',
        where: 'task_type = ?',
        whereArgs: ['connection_test'],
      );
      expect(connectionRows, hasLength(1));
      expect(connectionRows.first['status'], 'success');
      expect(connectionRows.first['input_tokens'], greaterThan(0));

      failConnectionTest = true;
      await expectLater(
        ai.testProvider(
          (await ai.providers()).first,
          (await ai.models()).first,
        ),
        throwsA(isA<AiRequestException>()),
      );
      final failedTests = await store.db.query(
        'ai_usage',
        where: 'task_type = ? AND status = ?',
        whereArgs: ['connection_test', 'failed'],
      );
      expect(failedTests, hasLength(1));
      expect(failedTests.first['error'], isNotNull);
      failConnectionTest = false;
      final summaryWithTest = await store.aiUsageSummary();
      expect(
        summaryWithTest.byType.any((group) => group.label == 'connection_test'),
        isTrue,
      );

      await database.close();
      await server.close(force: true);
      if (await database.paths.root.exists()) {
        await database.paths.root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<TaskInfo> _waitForTask(LocalStore store, String taskId) async {
  for (var i = 0; i < 300; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final task = await store.getTask(taskId);
    if (task != null && task.status != 'queued' && task.status != 'running') {
      return task;
    }
  }
  throw StateError('task did not finish: $taskId');
}
