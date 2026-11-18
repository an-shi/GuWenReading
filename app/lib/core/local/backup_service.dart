import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'local_store.dart';

enum BackupMode { full, light }

class BackupInfo {
  const BackupInfo({
    required this.path,
    required this.filename,
    required this.size,
    required this.createdAt,
    this.mode = BackupMode.full,
  });
  final String path;
  final String filename;
  final int size;
  final String createdAt;
  final BackupMode mode;
}

class BackupService {
  BackupService({required this.store, required this.paths});
  final LocalStore store;
  final AppPaths paths;

  /// Bumped when the backup format or restored table set changes.
  static const backupFormatVersion = 2;
  static const schemaVersion = 2;

  static const _cachedTables = <String>[
    'translation_sentence_cache',
    'knowledge_chunk_cache',
    'knowledge_extraction_state',
    'translation_cache',
    'entity_disambiguation_cache',
  ];

  static const _restoreTables = <String>[
    'books',
    'chapters',
    'paragraphs',
    'sentences',
    'translations',
    'translation_versions',
    'translation_reviews',
    'translation_cache',
    'annotations',
    'bookmarks',
    'reading_progress',
    'entities',
    'entity_mentions',
    'entity_relations',
    'relation_sources',
    'historical_events',
    'event_participants',
    'event_sources',
    'tasks',
    'ai_providers',
    'ai_models',
    'ai_usage',
    'prompt_templates',
    'prompt_schemas',
    'assistant_sessions',
    'assistant_messages',
    'app_settings',
    'ai_budget_limits',
    'ai_budget_reservations',
    'ai_quality_reports',
    'entity_disambiguations',
    'entity_disambiguation_cache',
    'knowledge_review_events',
    'translation_sentence_cache',
    'knowledge_chunk_cache',
    'knowledge_extraction_state',
  ];

  Future<BackupInfo> createBackup({BackupMode mode = BackupMode.full}) async {
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[-:T]'), '')
        .split('.')
        .first;
    final suffix = mode == BackupMode.full ? '完整' : '轻量';
    final filename = '古文阅读器备份-$stamp-$suffix.zip';
    final target = File(p.join(paths.backupsDir.path, filename));
    final snapshot = File(p.join(paths.tmpDir.path, 'snapshot-$stamp.db'));
    if (await snapshot.exists()) await snapshot.delete();
    await store.db.execute('VACUUM INTO ?', [snapshot.path]);
    try {
      if (mode == BackupMode.light) {
        await _stripCaches(snapshot.path);
      }
      final archive = Archive();
      archive.addFile(
        ArchiveFile(
          'database/guwen.db',
          await snapshot.length(),
          await snapshot.readAsBytes(),
        ),
      );
      await _addDirectory(archive, paths.booksDir, 'books');
      await _addDirectory(archive, paths.coversDir, 'covers');
      final manifest = jsonEncode({
        'app': '古文阅读器',
        'version': '0.1.0',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'format': 'guwenreader.backup.v2',
        'backup_format_version': backupFormatVersion,
        'schema_version': schemaVersion,
        'mode': mode.name,
        'includes_caches': mode == BackupMode.full,
        'includes_ai_usage': true,
      });
      final manifestBytes = utf8.encode(manifest);
      archive.addFile(
        ArchiveFile('backup.json', manifestBytes.length, manifestBytes),
      );
      final encoded = ZipEncoder().encode(archive);
      await target.writeAsBytes(encoded, flush: true);
      final stat = await target.stat();
      return BackupInfo(
        path: target.path,
        filename: filename,
        size: stat.size,
        createdAt: stat.modified.toUtc().toIso8601String(),
        mode: mode,
      );
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
    }
  }

  Future<void> _stripCaches(String snapshotPath) async {
    await store.db.execute('ATTACH DATABASE ? AS backup_db', [snapshotPath]);
    try {
      for (final table in _cachedTables) {
        try {
          await store.db.execute('DELETE FROM backup_db.$table');
        } catch (_) {
          // Older snapshots may lack a cache table.
        }
      }
    } finally {
      await store.db.execute('DETACH DATABASE backup_db');
    }
  }

  Future<void> _addDirectory(
    Archive archive,
    Directory directory,
    String prefix,
  ) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: directory.path)
          .replaceAll('\\', '/');
      final bytes = await entity.readAsBytes();
      archive.addFile(ArchiveFile('$prefix/$relative', bytes.length, bytes));
    }
  }

  Future<List<BackupInfo>> listBackups() async {
    if (!await paths.backupsDir.exists()) return const [];
    final files = await paths.backupsDir
        .list()
        .where(
          (entity) =>
              entity is File &&
              entity.path.endsWith('.zip') &&
              p.basename(entity.path).startsWith('古文阅读器备份-'),
        )
        .cast<File>()
        .toList();
    final result = <BackupInfo>[];
    for (final file in files) {
      final stat = await file.stat();
      final name = p.basename(file.path);
      result.add(
        BackupInfo(
          path: file.path,
          filename: name,
          size: stat.size,
          createdAt: stat.modified.toUtc().toIso8601String(),
          mode: name.contains('轻量') ? BackupMode.light : BackupMode.full,
        ),
      );
    }
    result.sort((a, b) => b.filename.compareTo(a.filename));
    return result;
  }

  Future<void> deleteBackup(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<void> restoreBackup(String path) async {
    final file = File(path);
    if (!await file.exists()) throw BackupException('备份文件不存在');
    final archive = ZipDecoder().decodeBytes(
      await file.readAsBytes(),
      verify: false,
    );
    final manifest = _readManifest(archive);
    final databaseEntry = archive.files
        .where((entry) => entry.name == 'database/guwen.db')
        .firstOrNull;
    if (databaseEntry == null) throw BackupException('备份中缺少数据库文件');
    final tempDir = await Directory(
      p.join(
        paths.tmpDir.path,
        'restore-${DateTime.now().microsecondsSinceEpoch}',
      ),
    ).create(recursive: true);
    try {
      final tempDb = File(p.join(tempDir.path, 'restore.db'));
      await tempDb.writeAsBytes(
        databaseEntry.content as List<int>,
        flush: true,
      );
      final backupDb = await store.db.rawQuery('PRAGMA database_list');
      final currentPath =
          backupDb.firstWhere((row) => row['name'] == 'main')['file'] as String;
      final preRestore = File(
        p.join(
          paths.backupsDir.path,
          'restore-before-${DateTime.now().millisecondsSinceEpoch}.db',
        ),
      );
      if (currentPath.isNotEmpty && await File(currentPath).exists()) {
        await File(currentPath).copy(preRestore.path);
      }
      await store.db.execute('PRAGMA foreign_keys = OFF');
      try {
        await store.db.execute('ATTACH DATABASE ? AS restore_db', [
          tempDb.path,
        ]);
        try {
          final available = await _tableNames('restore_db');
          final tables = _restoreTables.where(available.contains).toList();
          for (final required in ['books', 'chapters', 'sentences']) {
            if (!available.contains(required)) {
              throw BackupException('备份数据库缺少核心表：$required');
            }
          }
          await store.db.transaction((txn) async {
            for (final table in tables) {
              await txn.delete(table);
            }
            // Tables missing from an older snapshot must not keep stale rows.
            for (final table in _restoreTables) {
              if (available.contains(table)) continue;
              if (_cachedTables.contains(table) || table == 'ai_usage') {
                await txn.delete(table);
              }
            }
            for (final table in tables) {
              final columns = await _sharedColumns(txn, table);
              if (columns.isEmpty) continue;
              final list = columns.join(', ');
              await txn.rawInsert(
                'INSERT INTO main.$table ($list) '
                'SELECT $list FROM restore_db.$table',
              );
            }
          });
        } finally {
          try {
            await store.db.execute('DETACH DATABASE restore_db');
          } catch (_) {
            // Keep the original restore error if detach also fails.
          }
        }
      } finally {
        await store.db.execute('PRAGMA foreign_keys = ON');
      }
      await _restoreDirectory(archive, 'books', paths.booksDir);
      await _restoreDirectory(archive, 'covers', paths.coversDir);
      await store.resetSearchIndex();
      // Restored snapshot keeps its original cache rows for full backups and
      // empty cache tables for light backups; stale rows were replaced above.
      if (!manifest.includesCaches) {
        for (final table in _cachedTables) {
          await store.db.delete(table);
        }
      }
    } finally {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    }
  }

  _BackupManifest _readManifest(Archive archive) {
    final entry = archive.files
        .where((item) => item.name == 'backup.json')
        .firstOrNull;
    if (entry == null) {
      // Backups created before v2 have no manifest version field.
      return const _BackupManifest(
        format: 'guwenreader.backup.v1',
        schemaVersion: 1,
        mode: 'full',
      );
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(
        utf8.decode(entry.content as List<int>),
      ) as Map<String, dynamic>;
    } catch (_) {
      throw BackupException('备份清单无法解析');
    }
    final format = json['format'] as String? ?? '';
    if (!format.startsWith('guwenreader.backup.')) {
      throw BackupException('不是古文阅读器备份文件');
    }
    final version =
        json['backup_format_version'] as int? ??
        (format.endsWith('.v1') ? 1 : backupFormatVersion);
    if (version > backupFormatVersion) {
      throw BackupException('备份格式版本过新（$version），请升级应用后再恢复');
    }
    final schema = json['schema_version'] as int? ?? 1;
    if (schema > schemaVersion) {
      throw BackupException('备份数据库版本过新（$schema），请升级应用后再恢复');
    }
    return _BackupManifest(
      format: format,
      schemaVersion: schema,
      mode: json['mode'] as String? ?? 'full',
      includesCaches: json['includes_caches'] as bool? ?? true,
    );
  }

  Future<Set<String>> _tableNames(String schema) async {
    final rows = await store.db.rawQuery(
      "SELECT name FROM $schema.sqlite_master WHERE type = 'table'",
    );
    return {for (final row in rows) row['name'] as String};
  }

  Future<List<String>> _sharedColumns(
    DatabaseExecutor executor,
    String table,
  ) async {
    final mainRows = await executor.rawQuery('PRAGMA main.table_info($table)');
    final backupRows = await executor.rawQuery(
      'PRAGMA restore_db.table_info($table)',
    );
    final backupColumns = {for (final row in backupRows) row['name'] as String};
    return [
      for (final row in mainRows)
        if (backupColumns.contains(row['name'] as String))
          row['name'] as String,
    ];
  }

  Future<void> _restoreDirectory(
    Archive archive,
    String prefix,
    Directory target,
  ) async {
    final entries = archive.files
        .where((entry) => entry.name.startsWith('$prefix/'))
        .toList();
    if (entries.isEmpty) return;
    if (await target.exists()) await target.delete(recursive: true);
    await target.create(recursive: true);
    for (final entry in entries) {
      if (entry.isFile) {
        final relative = entry.name.substring(prefix.length + 1);
        final out = File(p.join(target.path, relative));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(entry.content as List<int>, flush: true);
      }
    }
  }
}

class _BackupManifest {
  const _BackupManifest({
    required this.format,
    required this.schemaVersion,
    required this.mode,
    this.includesCaches = true,
  });

  final String format;
  final int schemaVersion;
  final String mode;
  final bool includesCaches;
}

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}
