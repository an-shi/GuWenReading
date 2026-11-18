import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guwenreader/core/local/ai_service.dart';
import 'package:guwenreader/core/local/app_database.dart';
import 'package:guwenreader/core/local/backup_service.dart';
import 'package:guwenreader/core/local/import_service.dart';
import 'package:guwenreader/core/local/local_store.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'full backup keeps usage and caches, light backup omits caches',
    () async {
      final database = await AppDatabase.openInMemory();
      final store = LocalStore(database);
      final importer = ImportService(store: store, paths: database.paths);
      final ai = AiSettingsService(store: store);
      await ai.seedPrompts();
      final book = await importer.importBytes(
        filename: '史记.txt',
        bytes: utf8.encode('第一章 五帝本纪\n黄帝者，少典之子。\n'),
      );
      await store.recordAiUsage(
        taskType: 'translation',
        providerName: 'Mock',
        modelName: 'Mock Model',
        inputTokens: 100,
        outputTokens: 40,
        cost: 0.002,
        durationMs: 120,
        status: 'success',
      );
      await store.putTranslationSentenceCache(
        cacheKey: 'cache-1',
        sourceHash: 'source-1',
        contextHash: 'context-1',
        modelLabel: 'Mock Model',
        promptVersion: 1,
        translatedText: '黄帝是少典的儿子。',
      );

      final service = BackupService(store: store, paths: database.paths);
      final full = await service.createBackup(mode: BackupMode.full);
      final light = await service.createBackup(mode: BackupMode.light);
      expect(full.mode, BackupMode.full);
      expect(light.mode, BackupMode.light);
      expect(full.filename, contains('完整'));
      expect(light.filename, contains('轻量'));
      expect(full.size, greaterThan(0));

      final lightManifest = await _readManifest(light.path);
      expect(lightManifest['includes_caches'], isFalse);
      expect(lightManifest['schema_version'], BackupService.schemaVersion);

      final inspect = await _snapshotCounts(store, light.path);
      expect(inspect['translation_sentence_cache'], 0);
      expect(inspect['ai_usage'], 1);
      expect(inspect['prompt_templates'], greaterThan(0));
      expect(inspect['books'], 1);

      await store.db.delete('translation_sentence_cache');
      await service.restoreBackup(full.path);
      expect(
        (await store.db.rawQuery(
          'SELECT COUNT(*) AS n FROM translation_sentence_cache',
        )).first['n'],
        1,
      );
      expect(
        (await store.db.rawQuery('SELECT COUNT(*) AS n FROM ai_usage'))
            .first['n'],
        1,
      );
      expect(await store.getBook(book.id), isNotNull);

      await store.db.delete('translation_sentence_cache');
      await service.restoreBackup(light.path);
      expect(await store.getBook(book.id), isNotNull);
      expect(
        (await store.db.rawQuery('SELECT COUNT(*) AS n FROM ai_usage'))
            .first['n'],
        1,
      );
      expect(
        (await store.db.rawQuery(
          'SELECT COUNT(*) AS n FROM translation_sentence_cache',
        )).first['n'],
        0,
      );
      expect(
        (await store.db.rawQuery('SELECT COUNT(*) AS n FROM prompt_templates'))
            .first['n'],
        greaterThan(0),
      );

      await database.close();
    },
  );

  test('restore rejects backups from a newer schema', () async {
    final database = await AppDatabase.openInMemory();
    final store = LocalStore(database);
    final service = BackupService(store: store, paths: database.paths);
    final archive = Archive();
    final manifest = utf8.encode(
      jsonEncode({
        'format': 'guwenreader.backup.v2',
        'backup_format_version': 99,
        'schema_version': 99,
      }),
    );
    archive.addFile(ArchiveFile('backup.json', manifest.length, manifest));
    final target = File(
      p.join(database.paths.tmpDir.path, 'future-backup.zip'),
    );
    await target.writeAsBytes(ZipEncoder().encode(archive), flush: true);
    await expectLater(
      service.restoreBackup(target.path),
      throwsA(isA<BackupException>()),
    );
    await target.delete();
    await database.close();
  });
}

Future<Map<String, dynamic>> _readManifest(String path) async {
  final archive = ZipDecoder().decodeBytes(
    await File(path).readAsBytes(),
    verify: false,
  );
  final entry = archive.files.firstWhere((item) => item.name == 'backup.json');
  return jsonDecode(utf8.decode(entry.content as List<int>))
      as Map<String, dynamic>;
}

Future<Map<String, int>> _snapshotCounts(LocalStore store, String path) async {
  final archive = ZipDecoder().decodeBytes(
    await File(path).readAsBytes(),
    verify: false,
  );
  final entry = archive.files.firstWhere(
    (item) => item.name == 'database/guwen.db',
  );
  final temp = File(
    p.join(
      Directory.systemTemp.path,
      'inspect-${DateTime.now().microsecondsSinceEpoch}.db',
    ),
  );
  await temp.writeAsBytes(entry.content as List<int>, flush: true);
  await store.db.execute('ATTACH DATABASE ? AS inspect_db', [temp.path]);
  try {
    final result = <String, int>{};
    for (final table in [
      'translation_sentence_cache',
      'ai_usage',
      'prompt_templates',
      'books',
    ]) {
      final rows = await store.db.rawQuery(
        'SELECT COUNT(*) AS n FROM inspect_db.$table',
      );
      result[table] = rows.first['n'] as int;
    }
    return result;
  } finally {
    await store.db.execute('DETACH DATABASE inspect_db');
    if (await temp.exists()) await temp.delete();
  }
}
