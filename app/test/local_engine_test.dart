import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guwenreader/core/local/ai_service.dart';
import 'package:guwenreader/core/local/app_database.dart';
import 'package:guwenreader/core/local/import_service.dart';
import 'package:guwenreader/core/local/local_engine/engine.dart';
import 'package:guwenreader/core/local/local_engine/local_lexicon_service.dart';
import 'package:guwenreader/core/local/local_store.dart';
import 'package:guwenreader/core/local/translation_service.dart';
import 'package:guwenreader/data/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('local engine recognizes judgment and fixed patterns', () {
    const engine = LocalClassicalEngine();
    final judgment = engine.translate('廉颇者，赵之良将也。');
    expect(judgment.text, contains('是'));
    expect(judgment.rules, contains('判断句：……者，……也'));

    final rhetorical = engine.translate('学而时习之，不亦说乎？');
    expect(rhetorical.rules.any((rule) => rule.contains('不亦')), isTrue);
    expect(rhetorical.text, contains('不也是'));

    final objectFront = engine.translate('何陋之有？');
    expect(objectFront.rules.any((rule) => rule.contains('何……之有')), isTrue);
    expect(objectFront.text, contains('有什么'));

    final analysis = engine.translate('走汤妻子交通');
    expect(analysis.candidates, isNotEmpty);
    expect(analysis.tokens.any((token) => token.word == '妻子'), isTrue);
    expect(analysis.toJson()['engine'], 'local_rule');
  });

  test(
    'custom lexicon adds meanings without changing builtin entries',
    () async {
      final database = await AppDatabase.openInMemory();
      final store = LocalStore(database);
      final lexicon = LocalLexiconService(store);
      await lexicon.upsert(
        word: '考',
        kind: '动词',
        meanings: const ['考察', '考试'],
        source: '测试自定义',
      );
      await lexicon.loadCustom();
      const engine = LocalClassicalEngine();
      final result = engine.translate('考其德行。');
      expect(result.tokens.any((token) => token.word == '考'), isTrue);
      expect(result.text, contains('考察'));
      expect(result.candidates.length, greaterThan(1));
      final exported = await lexicon.exportJson();
      expect(exported, contains('考'));
      await database.close();
    },
  );

  test(
    'local mode translates without any AI provider and caches results',
    () async {
      SharedPreferences.setMockInitialValues({
        'translation_engine_mode': 'local',
      });
      final database = await AppDatabase.openInMemory();
      final store = LocalStore(database);
      final ai = AiSettingsService(store: store);
      final service = TranslationService(
        store: store,
        aiSettings: ai,
        client: AiJsonClient(ai),
      );
      final book = await ImportService(store: store, paths: database.paths)
          .importBytes(
            filename: 'test.txt',
            bytes: utf8.encode('第一章 测试\n学而时习之，不亦说乎？何陋之有？\n'),
          );
      final chapter = (await store.listChapters(book.id)).first;
      final task = await service.startChapterTranslation(chapter.id);
      final result = await _wait(store, task.id);
      expect(result.status, 'completed');
      expect(result.result['ai_count'], 0);
      final rows = await store.db.query('translations');
      expect(rows, isNotEmpty);
      expect(rows.first['origin'], 'local_rule');
      expect(rows.first['local_analysis'], isNotNull);
      expect('${rows.first['model_name']}', contains('本地规则'));
      expect(
        (await store.db.rawQuery(
          'SELECT COUNT(*) AS n FROM local_translation_cache',
        )).first['n'],
        greaterThan(0),
      );
      expect(
        (await store.db.rawQuery('SELECT COUNT(*) AS n FROM ai_usage'))
            .first['n'],
        0,
      );
      await database.close();
    },
  );
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
