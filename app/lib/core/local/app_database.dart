import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'schema.dart';

String nowIso() => DateTime.now().toUtc().toIso8601String();

class AppPaths {
  const AppPaths({
    required this.root,
    required this.libraryDir,
    required this.dbDir,
    required this.dbPath,
    required this.booksDir,
    required this.coversDir,
    required this.backupsDir,
    required this.tmpDir,
  });

  static const dataRootKey = 'data_root';
  static const legacyImportKey = 'legacy_data_imported';

  /// 数据根目录。默认位于安装目录下的 `data/`。
  final Directory root;

  /// 书籍、封面、备份与临时文件目录：`<root>/library`。
  final Directory libraryDir;

  /// SQLite 数据库目录：`<root>/database`。
  final Directory dbDir;
  final String dbPath;
  final Directory booksDir;
  final Directory coversDir;
  final Directory backupsDir;
  final Directory tmpDir;

  static bool get _usesInstallDirectory =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  static Future<Directory> defaultRoot() async {
    final support = await getApplicationSupportDirectory();
    final legacy = Directory(p.join(support.path, '古文阅读器'));
    if (_usesInstallDirectory) {
      final executableDir = File(Platform.resolvedExecutable).parent;
      final installData = Directory(p.join(executableDir.path, 'data'));
      if (await _isWritable(installData)) {
        try {
          await _importLegacyDefault(legacy, installData);
          return installData;
        } catch (_) {
          // If the old data cannot be copied, keep using it rather than
          // starting with an empty library.
          if (await _hasData(legacy)) return legacy;
          return installData;
        }
      }
    }
    return legacy;
  }

  static Future<Directory?> configuredRoot() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(dataRootKey);
    if (value == null || value.trim().isEmpty) return null;
    return Directory(value);
  }

  static Future<AppPaths> resolve({String? overrideRoot}) async {
    final Directory root;
    if (overrideRoot != null && overrideRoot.isNotEmpty) {
      root = Directory(p.join(overrideRoot, '古文阅读器'));
    } else {
      root = await configuredRoot() ?? await defaultRoot();
    }
    await _upgradeLegacyLayout(root);
    final library = Directory(p.join(root.path, 'library'));
    final database = Directory(p.join(root.path, 'database'));
    final books = Directory(p.join(library.path, 'books'));
    final covers = Directory(p.join(library.path, 'covers'));
    final backups = Directory(p.join(library.path, 'backups'));
    final tmp = Directory(p.join(library.path, 'tmp'));
    for (final dir in [root, library, database, books, covers, backups, tmp]) {
      if (!await dir.exists()) await dir.create(recursive: true);
    }
    return AppPaths(
      root: root,
      libraryDir: library,
      dbDir: database,
      dbPath: p.join(database.path, 'guwen.db'),
      booksDir: books,
      coversDir: covers,
      backupsDir: backups,
      tmpDir: tmp,
    );
  }

  /// Older versions stored `guwen.db`, `books/`, `covers/` directly in the
  /// data root. Move them into `database/` and `library/` before opening.
  static Future<void> _upgradeLegacyLayout(Directory root) async {
    if (!await root.exists()) return;
    final library = Directory(p.join(root.path, 'library'));
    final database = Directory(p.join(root.path, 'database'));
    if (!await library.exists()) await library.create(recursive: true);
    if (!await database.exists()) await database.create(recursive: true);
    for (final name in ['guwen.db', 'guwen.db-wal', 'guwen.db-shm']) {
      final source = File(p.join(root.path, name));
      if (await source.exists()) {
        await _moveFile(source, File(p.join(database.path, name)));
      }
    }
    for (final name in ['books', 'covers', 'backups', 'tmp']) {
      final source = Directory(p.join(root.path, name));
      if (await source.exists()) {
        await _mergeDirectory(source, Directory(p.join(library.path, name)));
      }
    }
  }

  static Future<void> _importLegacyDefault(
    Directory legacy,
    Directory target,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(legacyImportKey) == true) return;
    if (!await legacy.exists()) return;
    if (await _hasData(target)) return;
    await _copyDirectory(legacy, target);
    await _upgradeLegacyLayout(target);
    await prefs.setBool(legacyImportKey, true);
  }

  static Future<bool> _hasData(Directory root) async {
    if (await File(p.join(root.path, 'guwen.db')).exists()) return true;
    if (await File(p.join(root.path, 'database', 'guwen.db')).exists()) {
      return true;
    }
    final library = Directory(p.join(root.path, 'library'));
    if (await _directoryHasFiles(library)) return true;
    for (final name in ['books', 'covers', 'backups']) {
      if (await _directoryHasFiles(Directory(p.join(root.path, name)))) {
        return true;
      }
    }
    return false;
  }

  static Future<bool> _directoryHasFiles(Directory dir) async {
    if (!await dir.exists()) return false;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && !p.basename(entity.path).startsWith('.guwen-')) {
        return true;
      }
    }
    return false;
  }

  static Future<bool> _isWritable(Directory dir) async {
    try {
      await dir.create(recursive: true);
      final probe = File(p.join(dir.path, '.guwen-write-test'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _moveFile(File source, File target) async {
    if (await target.exists()) return;
    await target.parent.create(recursive: true);
    try {
      await source.rename(target.path);
    } catch (_) {
      await source.copy(target.path);
      try {
        await source.delete();
      } catch (_) {
        // A stale copy is harmless.
      }
    }
  }

  static Future<bool> _mergeDirectory(
    Directory source,
    Directory target,
  ) async {
    await target.create(recursive: true);
    var fullyMerged = true;
    await for (final entity in source.list(followLinks: false)) {
      final destination = p.join(target.path, p.basename(entity.path));
      if (entity is Directory) {
        final merged = await _mergeDirectory(entity, Directory(destination));
        if (!merged) fullyMerged = false;
      } else if (entity is File) {
        final file = File(destination);
        if (!await file.exists()) {
          await entity.copy(destination);
        } else {
          fullyMerged = false;
        }
      }
    }
    if (!fullyMerged) return false;
    try {
      await source.delete(recursive: true);
      return true;
    } catch (_) {
      // Keep the old copy if a file is still in use.
      return false;
    }
  }

  static Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = p.relative(entity.path, from: source.path);
      final destination = p.join(target.path, relative);
      if (entity is Directory) {
        await Directory(destination).create(recursive: true);
      } else if (entity is File) {
        await File(destination).parent.create(recursive: true);
        await entity.copy(destination);
      }
    }
  }
}

class AppDatabase {
  AppDatabase._(this.db, this.paths, {required this.ftsAvailable});

  final Database db;
  final AppPaths paths;
  final bool ftsAvailable;

  static bool get _desktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  static Future<AppDatabase> open({String? overrideRoot}) async {
    final paths = await AppPaths.resolve(overrideRoot: overrideRoot);
    if (_desktop) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.setDatabasesPath(paths.dbDir.path);
    }
    final db = await databaseFactory.openDatabase(
      paths.dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
          try {
            await database.execute('PRAGMA journal_mode = WAL');
          } catch (_) {
            // Some platform SQLite builds disallow WAL on app sandboxes.
          }
        },
        onCreate: (database, version) async {
          for (final statement in schemaStatements) {
            await database.execute(statement);
          }
        },
        onOpen: (database) async {
          // Keep forward-compatible with snapshots created before a table was
          // added to the schema list.
          for (final statement in schemaStatements) {
            try {
              await database.execute(statement);
            } catch (_) {
              // CREATE IF NOT EXISTS is expected to succeed; ignore only the
              // rare platform-specific DDL quirk and continue opening.
            }
          }
        },
      ),
    );
    final ftsAvailable = await _ensureFts(db);
    await _migrate(db);
    return AppDatabase._(db, paths, ftsAvailable: ftsAvailable);
  }

  static Future<AppDatabase> openInMemory() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          for (final statement in schemaStatements) {
            await database.execute(statement);
          }
        },
      ),
    );
    final ftsAvailable = await _ensureFts(db);
    await _migrate(db);
    final paths = await AppPaths.resolve(
      overrideRoot: p.join(Directory.systemTemp.path, 'guwenreader-test'),
    );
    return AppDatabase._(db, paths, ftsAvailable: ftsAvailable);
  }

  static Future<void> _migrate(Database db) async {
    const additions = <String, Map<String, String>>{
      'tasks': {
        'input_tokens': 'INTEGER NOT NULL DEFAULT 0',
        'output_tokens': 'INTEGER NOT NULL DEFAULT 0',
        'cache_read_tokens': 'INTEGER NOT NULL DEFAULT 0',
        'cache_write_tokens': 'INTEGER NOT NULL DEFAULT 0',
        'cost': 'REAL NOT NULL DEFAULT 0',
        'requests': 'INTEGER NOT NULL DEFAULT 0',
      },
      'ai_models': {
        'is_default_extraction': 'INTEGER NOT NULL DEFAULT 0',
        'input_price': 'REAL NOT NULL DEFAULT 0',
        'output_price': 'REAL NOT NULL DEFAULT 0',
        'cache_read_price': 'REAL NOT NULL DEFAULT 0',
        'cache_write_price': 'REAL NOT NULL DEFAULT 0',
      },
      'historical_events': {'fingerprint': 'TEXT'},
    };
    for (final entry in additions.entries) {
      final info = await db.rawQuery('PRAGMA table_info(${entry.key})');
      final existing = {for (final row in info) row['name'] as String?};
      for (final column in entry.value.entries) {
        if (existing.contains(column.key)) continue;
        try {
          await db.execute(
            'ALTER TABLE ${entry.key} ADD COLUMN ${column.key} ${column.value}',
          );
        } catch (_) {
          // Keep opening old snapshots even if a platform DDL quirk occurs.
        }
      }
    }
    try {
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_events_fingerprint '
        'ON historical_events(fingerprint) WHERE fingerprint IS NOT NULL',
      );
    } catch (_) {
      // Existing duplicate fingerprints must not prevent startup.
    }
  }

  static Future<bool> _ensureFts(Database db) async {
    try {
      await db.execute(
        'CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5('
        'text, book_id UNINDEXED, chapter_id UNINDEXED, '
        'sentence_id UNINDEXED, doc_type UNINDEXED)',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> close() => db.close();
}

String newLocalId(String prefix) => '$prefix-${const Uuid().v4()}';
