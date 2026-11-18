import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import 'app_database.dart';
import 'local_store.dart';

class BackupInfo {
  const BackupInfo({
    required this.path,
    required this.filename,
    required this.size,
    required this.createdAt,
  });
  final String path;
  final String filename;
  final int size;
  final String createdAt;
}

class BackupService {
  BackupService({required this.store, required this.paths});
  final LocalStore store;
  final AppPaths paths;

  Future<BackupInfo> createBackup() async {
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[-:T]'), '')
        .split('.')
        .first;
    final filename = '古文阅读器备份-$stamp.zip';
    final target = File(p.join(paths.backupsDir.path, filename));
    final snapshot = File(p.join(paths.tmpDir.path, 'snapshot-$stamp.db'));
    if (await snapshot.exists()) await snapshot.delete();
    await store.db.execute('VACUUM INTO ?', [snapshot.path]);
    try {
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
        'format': 'guwenreader.backup.v1',
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
      );
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
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
      result.add(
        BackupInfo(
          path: file.path,
          filename: p.basename(file.path),
          size: stat.size,
          createdAt: stat.modified.toUtc().toIso8601String(),
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
        final tables = <String>[
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
          'prompt_templates',
          'assistant_sessions',
          'assistant_messages',
          'app_settings',
        ];
        await store.db.transaction((txn) async {
          for (final table in tables) {
            await txn.delete(table);
          }
          for (final table in tables) {
            await txn.rawInsert(
              'INSERT INTO main.$table SELECT * FROM restore_db.$table',
            );
          }
        });
        await store.db.execute('DETACH DATABASE restore_db');
      } finally {
        await store.db.execute('PRAGMA foreign_keys = ON');
      }
      await _restoreDirectory(archive, 'books', paths.booksDir);
      await _restoreDirectory(archive, 'covers', paths.coversDir);
      await store.db.delete('translation_sentence_cache');
      await store.db.delete('knowledge_chunk_cache');
      await store.db.delete('knowledge_extraction_state');
      await store.resetSearchIndex();
    } finally {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    }
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

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}
