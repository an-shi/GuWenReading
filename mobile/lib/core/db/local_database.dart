import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../data/models.dart';

/// Local-first cache and off-device reading state.
///
/// Server responses are cached as JSON; annotations, bookmarks and reading
/// progress are stored locally even when the network is unavailable. Dirty rows
/// can be pushed to the server later by the sync service.
class LocalDatabase {
  LocalDatabase._(this._db);

  final Database _db;

  static Future<LocalDatabase> open() async {
    final path = p.join(await getDatabasesPath(), 'guwenreading.db');
    final db = await openDatabase(
      path,
      version: 1,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) async {
        await database.execute(
          'CREATE TABLE cache (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL)',
        );
        await database.execute(
          'CREATE TABLE annotations ('
          'id TEXT PRIMARY KEY, book_id TEXT NOT NULL, chapter_id TEXT, sentence_id TEXT, '
          'quote TEXT, content TEXT NOT NULL, color TEXT, tags TEXT, created_at TEXT, '
          'updated_at TEXT, dirty INTEGER NOT NULL DEFAULT 0, deleted INTEGER NOT NULL DEFAULT 0)',
        );
        await database.execute(
          'CREATE INDEX idx_annotations_book ON annotations(book_id, chapter_id)',
        );
        await database.execute(
          'CREATE TABLE bookmarks ('
          'id TEXT PRIMARY KEY, book_id TEXT NOT NULL, chapter_id TEXT NOT NULL, '
          'paragraph_id TEXT, sentence_id TEXT, label TEXT, position_ratio REAL NOT NULL DEFAULT 0, '
          'created_at TEXT, updated_at TEXT, dirty INTEGER NOT NULL DEFAULT 0, '
          'deleted INTEGER NOT NULL DEFAULT 0)',
        );
        await database.execute(
          'CREATE INDEX idx_bookmarks_book ON bookmarks(book_id, chapter_id)',
        );
        await database.execute(
          'CREATE TABLE progress ('
          'book_id TEXT PRIMARY KEY, chapter_id TEXT, paragraph_id TEXT, '
          'paragraph_index INTEGER NOT NULL DEFAULT 0, sentence_id TEXT, '
          'position_ratio REAL NOT NULL DEFAULT 0, updated_at TEXT NOT NULL)',
        );
        await database.execute(
          'CREATE TABLE local_translations ('
          'sentence_id TEXT PRIMARY KEY, chapter_id TEXT NOT NULL, text TEXT NOT NULL, '
          'origin TEXT NOT NULL, updated_at TEXT NOT NULL)',
        );
        await database.execute(
          'CREATE TABLE server_ids (local_id TEXT PRIMARY KEY, remote_id TEXT NOT NULL, kind TEXT NOT NULL)',
        );
      },
    );
    return LocalDatabase._(db);
  }

  Future<void> close() => _db.close();

  // ------------------------------------------------------------------ cache
  Future<void> putCache(String key, Object? value) async {
    await _db.insert(
      'cache',
      {'key': key, 'value': jsonEncode(value), 'updated_at': DateTime.now().toUtc().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<dynamic> readCache(String key) async {
    final rows = await _db.query('cache', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    final raw = rows.first['value'] as String?;
    if (raw == null) return null;
    return jsonDecode(raw);
  }

  Future<bool> hasCache(String key) async {
    final rows = await _db.query('cache', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isNotEmpty;
  }

  Future<void> deleteCache(String key) async {
    await _db.delete('cache', where: 'key = ?', whereArgs: [key]);
  }

  Future<void> clearReadingCache() async {
    await _db.delete('cache');
    await _db.delete('local_translations');
  }

  // ------------------------------------------------------------ annotations
  Future<void> upsertAnnotation(Annotation annotation, {bool dirty = false}) async {
    await _db.insert(
      'annotations',
      {
        'id': annotation.id,
        'book_id': annotation.bookId,
        'chapter_id': annotation.chapterId,
        'sentence_id': annotation.sentenceId,
        'quote': annotation.quote,
        'content': annotation.content,
        'color': annotation.color,
        'tags': jsonEncode(annotation.tags),
        'created_at': annotation.createdAt,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'dirty': dirty ? 1 : 0,
        'deleted': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Annotation>> annotations({String? bookId, bool includeDeleted = false}) async {
    final conditions = <String>[
      if (!includeDeleted) 'deleted = 0',
      if (bookId != null) 'book_id = ?',
    ];
    final rows = await _db.query(
      'annotations',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: [if (bookId != null) bookId],
      orderBy: 'created_at DESC',
    );
    return rows.map((row) {
      final tags = (jsonDecode(row['tags'] as String? ?? '[]') as List).map((e) => '$e').toList();
      return Annotation(
        id: row['id'] as String,
        bookId: row['book_id'] as String,
        chapterId: row['chapter_id'] as String?,
        sentenceId: row['sentence_id'] as String?,
        quote: row['quote'] as String?,
        content: row['content'] as String,
        color: row['color'] as String? ?? 'amber',
        tags: tags,
        createdAt: row['created_at'] as String?,
        dirty: (row['dirty'] as int? ?? 0) == 1,
      );
    }).toList();
  }

  Future<void> deleteAnnotationLocal(String id) async {
    await _db.update('annotations', {'deleted': 1, 'dirty': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> removeAnnotationLocal(String id) async {
    await _db.delete('annotations', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markAnnotationClean(String id) async {
    await _db.update('annotations', {'dirty': 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Annotation>> dirtyAnnotations() async {
    final rows = await _db.query('annotations', where: 'dirty = 1');
    return (await annotations(includeDeleted: true))
        .where((a) => rows.any((row) => row['id'] == a.id))
        .toList();
  }

  Future<bool> isAnnotationDeleted(String id) async {
    final rows = await _db.query('annotations', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty && (rows.first['deleted'] as int? ?? 0) == 1;
  }

  Future<void> replaceAnnotations(String bookId, List<Annotation> serverRows) async {
    await _db.delete('annotations', where: 'book_id = ? AND dirty = 0', whereArgs: [bookId]);
    for (final annotation in serverRows) {
      await upsertAnnotation(annotation);
    }
  }

  // --------------------------------------------------------------- bookmarks
  Future<void> upsertBookmark(Bookmark bookmark, {bool dirty = false}) async {
    await _db.insert(
      'bookmarks',
      {
        'id': bookmark.id,
        'book_id': bookmark.bookId,
        'chapter_id': bookmark.chapterId,
        'paragraph_id': bookmark.paragraphId,
        'sentence_id': bookmark.sentenceId,
        'label': bookmark.label,
        'position_ratio': bookmark.positionRatio,
        'created_at': bookmark.createdAt,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'dirty': dirty ? 1 : 0,
        'deleted': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Bookmark>> bookmarks({String? bookId, bool includeDeleted = false}) async {
    final conditions = <String>[
      if (!includeDeleted) 'deleted = 0',
      if (bookId != null) 'book_id = ?',
    ];
    final rows = await _db.query(
      'bookmarks',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: [if (bookId != null) bookId],
      orderBy: 'created_at DESC',
    );
    return rows
        .map((row) => Bookmark(
              id: row['id'] as String,
              bookId: row['book_id'] as String,
              chapterId: row['chapter_id'] as String,
              paragraphId: row['paragraph_id'] as String?,
              sentenceId: row['sentence_id'] as String?,
              label: row['label'] as String?,
              positionRatio: (row['position_ratio'] as num? ?? 0).toDouble(),
              createdAt: row['created_at'] as String?,
              dirty: (row['dirty'] as int? ?? 0) == 1,
            ))
        .toList();
  }

  Future<void> deleteBookmarkLocal(String id) async {
    await _db.update('bookmarks', {'deleted': 1, 'dirty': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> removeBookmarkLocal(String id) async {
    await _db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markBookmarkClean(String id) async {
    await _db.update('bookmarks', {'dirty': 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Bookmark>> dirtyBookmarks() async {
    final rows = await _db.query('bookmarks', where: 'dirty = 1');
    final ids = rows.map((row) => row['id']).toSet();
    return (await bookmarks(includeDeleted: true)).where((b) => ids.contains(b.id)).toList();
  }

  Future<bool> isBookmarkDeleted(String id) async {
    final rows = await _db.query('bookmarks', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty && (rows.first['deleted'] as int? ?? 0) == 1;
  }

  Future<void> replaceBookmarks(String bookId, List<Bookmark> serverRows) async {
    await _db.delete('bookmarks', where: 'book_id = ? AND dirty = 0', whereArgs: [bookId]);
    for (final bookmark in serverRows) {
      await upsertBookmark(bookmark);
    }
  }

  Future<void> clearAnnotations() async {
    await _db.delete('annotations');
    await _db.delete('bookmarks');
  }

  // ---------------------------------------------------------------- progress
  Future<void> saveProgress(ReaderProgress progress) async {
    await _db.insert(
      'progress',
      {
        'book_id': progress.bookId,
        'chapter_id': progress.chapterId,
        'paragraph_id': progress.paragraphId,
        'paragraph_index': progress.paragraphIndex,
        'sentence_id': progress.sentenceId,
        'position_ratio': progress.positionRatio,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ReaderProgress?> progress(String bookId) async {
    final rows = await _db.query('progress', where: 'book_id = ?', whereArgs: [bookId], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return ReaderProgress(
      bookId: row['book_id'] as String,
      chapterId: row['chapter_id'] as String?,
      paragraphId: row['paragraph_id'] as String?,
      paragraphIndex: row['paragraph_index'] as int? ?? 0,
      sentenceId: row['sentence_id'] as String?,
      positionRatio: (row['position_ratio'] as num? ?? 0).toDouble(),
      updatedAt: row['updated_at'] as String?,
    );
  }

  // -------------------------------------------------------- local translations
  Future<void> upsertLocalTranslation({
    required String sentenceId,
    required String chapterId,
    required String text,
    String origin = 'ai_direct',
  }) async {
    await _db.insert(
      'local_translations',
      {
        'sentence_id': sentenceId,
        'chapter_id': chapterId,
        'text': text,
        'origin': origin,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, TranslationRecord>> localTranslations(String chapterId) async {
    final rows = await _db.query(
      'local_translations',
      where: 'chapter_id = ?',
      whereArgs: [chapterId],
    );
    return {
      for (final row in rows)
        row['sentence_id'] as String: TranslationRecord(
          id: 'local-${row['sentence_id']}',
          sentenceId: row['sentence_id'] as String,
          text: row['text'] as String,
          origin: row['origin'] as String? ?? 'ai_direct',
          modelName: '移动端直连',
        ),
    };
  }

  Future<void> deleteLocalTranslation(String sentenceId) async {
    await _db.delete('local_translations', where: 'sentence_id = ?', whereArgs: [sentenceId]);
  }

  Future<int> pendingWriteCount() async {
    final annotations = Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM annotations WHERE dirty = 1'),
        ) ??
        0;
    final bookmarks = Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM bookmarks WHERE dirty = 1'),
        ) ??
        0;
    return annotations + bookmarks;
  }
}
