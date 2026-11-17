import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'schema.dart';

String nowIso() => DateTime.now().toUtc().toIso8601String();

class AppPaths {
  const AppPaths({
    required this.root,
    required this.dbPath,
    required this.booksDir,
    required this.coversDir,
    required this.backupsDir,
    required this.tmpDir,
  });

  final Directory root;
  final String dbPath;
  final Directory booksDir;
  final Directory coversDir;
  final Directory backupsDir;
  final Directory tmpDir;

  static Future<AppPaths> resolve({String? overrideRoot}) async {
    final Directory base;
    if (overrideRoot != null && overrideRoot.isNotEmpty) {
      base = Directory(overrideRoot);
    } else {
      base = await getApplicationSupportDirectory();
    }
    final root = Directory(p.join(base.path, '古文阅读器'));
    final books = Directory(p.join(root.path, 'books'));
    final covers = Directory(p.join(root.path, 'covers'));
    final backups = Directory(p.join(root.path, 'backups'));
    final tmp = Directory(p.join(root.path, 'tmp'));
    for (final dir in [root, books, covers, backups, tmp]) {
      if (!await dir.exists()) await dir.create(recursive: true);
    }
    return AppPaths(
      root: root,
      dbPath: p.join(root.path, 'guwen.db'),
      booksDir: books,
      coversDir: covers,
      backupsDir: backups,
      tmpDir: tmp,
    );
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
      await databaseFactory.setDatabasesPath(
        p.join(paths.root.path, 'databases'),
      );
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
    final paths = await AppPaths.resolve(
      overrideRoot: p.join(Directory.systemTemp.path, 'guwenreader-test'),
    );
    return AppDatabase._(db, paths, ftsAvailable: ftsAvailable);
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
