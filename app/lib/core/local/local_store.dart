import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../../data/models.dart';
import 'app_database.dart';
import 'local_models.dart';

class LocalStore {
  LocalStore(this.database);

  final AppDatabase database;
  Database get db => database.db;

  // ------------------------------------------------------------------ books
  Future<List<Book>> listBooks({String? query}) async {
    final value = query?.trim() ?? '';
    final rows = await db.query(
      'books',
      where: value.isEmpty ? 'deleted_at IS NULL' : "deleted_at IS NULL AND (title LIKE ? OR COALESCE(author,'') LIKE ? OR COALESCE(description,'') LIKE ?)",
      whereArgs: value.isEmpty ? null : ['%$value%', '%$value%', '%$value%'],
      orderBy: 'COALESCE(last_read_at, updated_at) DESC',
    );
    return rows.map(_bookFromRow).toList();
  }

  Future<Book?> getBook(String bookId) async {
    final rows = await db.query(
      'books',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [bookId],
      limit: 1,
    );
    return rows.isEmpty ? null : _bookFromRow(rows.first);
  }

  Future<void> updateBook(String bookId, Map<String, Object?> values) async {
    await db.update(
      'books',
      {...values, 'updated_at': nowIso()},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> softDeleteBook(String bookId) async {
    await db.update(
      'books',
      {'deleted_at': nowIso(), 'updated_at': nowIso()},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> setLastRead(String bookId) async {
    await db.update(
      'books',
      {'last_read_at': nowIso(), 'updated_at': nowIso()},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> refreshBookStats(String bookId) async {
    final chapterCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM chapters WHERE book_id = ?', [
            bookId,
          ]),
        ) ??
        0;
    final paragraphCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM paragraphs WHERE book_id = ?',
            [bookId],
          ),
        ) ??
        0;
    final sentenceCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM sentences WHERE book_id = ?',
            [bookId],
          ),
        ) ??
        0;
    final translatedCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM sentences s JOIN translations t ON t.sentence_id = s.id WHERE s.book_id = ?',
            [bookId],
          ),
        ) ??
        0;
    await db.update(
      'books',
      {
        'chapter_count': chapterCount,
        'paragraph_count': paragraphCount,
        'sentence_count': sentenceCount,
        'translated_sentence_count': translatedCount,
        'updated_at': nowIso(),
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Book _bookFromRow(Map<String, Object?> row) {
    final total = row['sentence_count'] as int? ?? 0;
    final translated = row['translated_sentence_count'] as int? ?? 0;
    return Book(
      id: row['id'] as String,
      title: row['title'] as String? ?? '未命名古籍',
      author: row['author'] as String?,
      dynasty: row['dynasty'] as String?,
      category: row['category'] as String?,
      description: row['description'] as String?,
      tags: _decodeStringList(row['tags']),
      sourceFormat: row['source_format'] as String? ?? 'txt',
      coverPath: row['cover_path'] as String?,
      chapterCount: row['chapter_count'] as int? ?? 0,
      sentenceCount: total,
      translatedSentenceCount: translated,
      translationPercent: total == 0 ? 0 : translated / total * 100,
      lastReadAt: row['last_read_at'] as String?,
    );
  }

  // --------------------------------------------------------------- chapters
  Future<List<ChapterSummary>> listChapters(String bookId) async {
    final rows = await db.rawQuery(
      '''
      SELECT c.*,
        (SELECT COUNT(*) FROM paragraphs p WHERE p.chapter_id = c.id) AS paragraph_count,
        (SELECT COUNT(*) FROM sentences s WHERE s.chapter_id = c.id) AS sentence_count,
        (SELECT COUNT(*) FROM sentences s JOIN translations t ON t.sentence_id = s.id WHERE s.chapter_id = c.id) AS translated_count
      FROM chapters c
      WHERE c.book_id = ?
      ORDER BY c.ordinal ASC
      ''',
      [bookId],
    );
    return [
      for (final row in rows)
        ChapterSummary(
          id: row['id'] as String,
          bookId: bookId,
          ordinal: row['ordinal'] as int? ?? 0,
          title: row['title'] as String? ?? '未命名章节',
          paragraphCount: row['paragraph_count'] as int? ?? 0,
          sentenceCount: row['sentence_count'] as int? ?? 0,
          translatedCount: row['translated_count'] as int? ?? 0,
          translationPercent: (row['sentence_count'] as int? ?? 0) == 0
              ? 0
              : (row['translated_count'] as int? ?? 0) /
                    (row['sentence_count'] as int? ?? 1) *
                    100,
        ),
    ];
  }

  Future<ChapterContent?> chapterContent(String chapterId) async {
    final chapterRows = await db.rawQuery(
      '''
      SELECT c.*, b.title AS book_title, b.author AS book_author
      FROM chapters c JOIN books b ON b.id = c.book_id
      WHERE c.id = ? AND b.deleted_at IS NULL
      LIMIT 1
      ''',
      [chapterId],
    );
    if (chapterRows.isEmpty) return null;
    final chapter = chapterRows.first;
    final bookId = chapter['book_id'] as String;
    final paragraphsRows = await db.query(
      'paragraphs',
      where: 'chapter_id = ?',
      whereArgs: [chapterId],
      orderBy: 'ordinal ASC',
    );
    final sentenceRows = await db.rawQuery(
      '''
      SELECT s.*, t.id AS translation_id, t.text AS translation_text, t.origin AS translation_origin,
             t.model_name AS translation_model, t.version AS translation_version,
             r.id AS review_id, r.candidate_text AS review_candidate
      FROM sentences s
      LEFT JOIN translations t ON t.sentence_id = s.id
      LEFT JOIN translation_reviews r ON r.sentence_id = s.id AND r.status = 'pending'
      WHERE s.chapter_id = ?
      ORDER BY s.ordinal ASC
      ''',
      [chapterId],
    );
    final byParagraph = <String, List<Sentence>>{};
    for (final row in sentenceRows) {
      final sentence = _sentenceFromRow(row);
      byParagraph
          .putIfAbsent(row['paragraph_id'] as String, () => [])
          .add(sentence);
    }
    final paragraphs = [
      for (final row in paragraphsRows)
        _paragraphFromRow(row, byParagraph[row['id']] ?? const []),
    ];
    final status = await translationStatus(chapterId);
    final previous = await db.query(
      'chapters',
      where: 'book_id = ? AND ordinal < ?',
      whereArgs: [bookId, chapter['ordinal']],
      orderBy: 'ordinal DESC',
      limit: 1,
    );
    final next = await db.query(
      'chapters',
      where: 'book_id = ? AND ordinal > ?',
      whereArgs: [bookId, chapter['ordinal']],
      orderBy: 'ordinal ASC',
      limit: 1,
    );
    return ChapterContent(
      bookId: bookId,
      bookTitle: chapter['book_title'] as String? ?? '',
      bookAuthor: chapter['book_author'] as String?,
      chapterId: chapterId,
      chapterTitle: chapter['title'] as String? ?? '',
      chapterOrdinal: chapter['ordinal'] as int? ?? 0,
      previousChapterId: previous.isEmpty
          ? null
          : previous.first['id'] as String?,
      nextChapterId: next.isEmpty ? null : next.first['id'] as String?,
      status: status,
      paragraphs: paragraphs,
    );
  }

  Sentence _sentenceFromRow(Map<String, Object?> row) {
    final reviewId = row['review_id'] as String?;
    return Sentence(
      id: row['id'] as String,
      ordinal: row['ordinal'] as int? ?? 0,
      originalText: row['original_text'] as String? ?? '',
      state: row['translation_state'] as String? ?? 'pending',
      translationError: row['translation_error'] as String?,
      translation: row['translation_id'] == null
          ? null
          : TranslationRecord(
              id: row['translation_id'] as String,
              sentenceId: row['id'] as String,
              text: row['translation_text'] as String? ?? '',
              origin: row['translation_origin'] as String? ?? 'ai',
              modelName: row['translation_model'] as String?,
              version: row['translation_version'] as int? ?? 1,
            ),
      pendingReview: reviewId == null
          ? null
          : PendingReview(
              id: reviewId,
              candidateText: row['review_candidate'] as String? ?? '',
            ),
      needsReview: (row['needs_review'] as int? ?? 0) == 1,
    );
  }

  Paragraph _paragraphFromRow(
    Map<String, Object?> row,
    List<Sentence> sentences,
  ) {
    final parts = [
      for (final sentence in sentences)
        if (sentence.translation != null) sentence.translation!.text,
    ];
    return Paragraph(
      id: row['id'] as String,
      ordinal: row['ordinal'] as int? ?? 0,
      originalText: row['original_text'] as String? ?? '',
      sentences: sentences,
      translationText: parts.isEmpty ? null : parts.join(),
      translationComplete:
          sentences.isNotEmpty &&
          sentences.every((sentence) => sentence.translation != null),
    );
  }

  Future<TranslationStatus> translationStatus(String chapterId) async {
    final total =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM sentences WHERE chapter_id = ?',
            [chapterId],
          ),
        ) ??
        0;
    final translated =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM sentences s JOIN translations t ON t.sentence_id = s.id WHERE s.chapter_id = ?',
            [chapterId],
          ),
        ) ??
        0;
    final manual =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM sentences s JOIN translations t ON t.sentence_id = s.id WHERE s.chapter_id = ? AND t.origin = 'manual'",
            [chapterId],
          ),
        ) ??
        0;
    final pendingReviews =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM translation_reviews r JOIN sentences s ON s.id = r.sentence_id WHERE s.chapter_id = ? AND r.status = 'pending'",
            [chapterId],
          ),
        ) ??
        0;
    final stateRows = await db.rawQuery(
      'SELECT translation_state, COUNT(*) AS count FROM sentences WHERE chapter_id = ? GROUP BY translation_state',
      [chapterId],
    );
    final states = {
      for (final row in stateRows)
        row['translation_state'] as String: row['count'] as int? ?? 0,
    };
    return TranslationStatus(
      total: total,
      translated: translated,
      manual: manual,
      pendingReviews: pendingReviews,
      pending: states['pending'] ?? 0,
      queued: states['queued'] ?? 0,
      translating: states['translating'] ?? 0,
      failed: states['failed'] ?? 0,
      percent: total == 0 ? 0 : translated / total * 100,
    );
  }

  Future<List<Sentence>> chapterSentences(
    String chapterId, {
    bool onlyMissing = false,
    bool includeManual = false,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT s.*, t.id AS translation_id, t.text AS translation_text, t.origin AS translation_origin,
             t.model_name AS translation_model, t.version AS translation_version,
             r.id AS review_id, r.candidate_text AS review_candidate
      FROM sentences s
      LEFT JOIN translations t ON t.sentence_id = s.id
      LEFT JOIN translation_reviews r ON r.sentence_id = s.id AND r.status = 'pending'
      WHERE s.chapter_id = ? ${onlyMissing ? 'AND t.id IS NULL' : ''}
      ORDER BY s.ordinal ASC
      ''',
      [chapterId],
    );
    final sentences = rows.map(_sentenceFromRow).toList();
    if (!includeManual) return sentences;
    return sentences;
  }

  Future<void> setSentenceState(
    String sentenceId,
    String state, {
    String? error,
  }) async {
    await db.update(
      'sentences',
      {'translation_state': state, 'translation_error': error},
      where: 'id = ?',
      whereArgs: [sentenceId],
    );
  }

  Future<void> upsertTranslation({
    required String sentenceId,
    required String text,
    required String origin,
    String? modelName,
    int? promptVersion,
    bool manualRetranslate = false,
  }) async {
    final existing = await db.query(
      'translations',
      where: 'sentence_id = ?',
      whereArgs: [sentenceId],
      limit: 1,
    );
    final now = nowIso();
    if (existing.isNotEmpty) {
      final current = existing.first;
      if (manualRetranslate && current['origin'] == 'manual') {
        return;
      }
      if (origin == 'ai' && current['text'] != text) {
        await db.insert('translation_reviews', {
          'id': newLocalId('review'),
          'sentence_id': sentenceId,
          'previous_text': current['text'] as String? ?? '',
          'candidate_text': text,
          'status': 'pending',
          'created_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        return;
      }
      await db.insert('translation_versions', {
        'id': newLocalId('tver'),
        'sentence_id': sentenceId,
        'translation_id': current['id'],
        'text': current['text'],
        'origin': current['origin'],
        'model_name': current['model_name'],
        'prompt_version': current['prompt_version'],
        'created_at': current['created_at'] ?? now,
      });
      await db.update(
        'translations',
        {
          'text': text,
          'origin': origin,
          'model_name': modelName,
          'prompt_version': promptVersion,
          'version': (current['version'] as int? ?? 1) + 1,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [current['id']],
      );
    } else {
      await db.insert('translations', {
        'id': newLocalId('tr'),
        'sentence_id': sentenceId,
        'text': text,
        'origin': origin,
        'model_name': modelName,
        'prompt_version': promptVersion,
        'version': 1,
        'created_at': now,
        'updated_at': now,
      });
    }
    await db.update(
      'sentences',
      {'translation_state': 'completed', 'translation_error': null},
      where: 'id = ?',
      whereArgs: [sentenceId],
    );
  }

  Future<void> resolveReview(String reviewId, bool accept) async {
    final rows = await db.query(
      'translation_reviews',
      where: 'id = ?',
      whereArgs: [reviewId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final review = rows.first;
    final sentenceId = review['sentence_id'] as String;
    if (accept) {
      final now = nowIso();
      final existing = await db.query(
        'translations',
        where: 'sentence_id = ?',
        whereArgs: [sentenceId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final current = existing.first;
        await db.insert('translation_versions', {
          'id': newLocalId('tver'),
          'sentence_id': sentenceId,
          'translation_id': current['id'],
          'text': current['text'],
          'origin': current['origin'],
          'model_name': current['model_name'],
          'prompt_version': current['prompt_version'],
          'created_at': current['created_at'] ?? now,
        });
        await db.update(
          'translations',
          {
            'text': review['candidate_text'],
            'origin': 'ai',
            'status': 'completed',
            'version': (current['version'] as int? ?? 1) + 1,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [current['id']],
        );
      } else {
        await db.insert('translations', {
          'id': newLocalId('tr'),
          'sentence_id': sentenceId,
          'text': review['candidate_text'],
          'origin': 'ai',
          'status': 'completed',
          'version': 1,
          'created_at': now,
          'updated_at': now,
        });
      }
      await db.update(
        'sentences',
        {'translation_state': 'completed', 'translation_error': null},
        where: 'id = ?',
        whereArgs: [sentenceId],
      );
    }
    await db.update(
      'translation_reviews',
      {'status': accept ? 'accepted' : 'rejected', 'resolved_at': nowIso()},
      where: 'id = ?',
      whereArgs: [reviewId],
    );
  }

  Future<List<Map<String, Object?>>> translationVersions(
    String sentenceId,
  ) async {
    return db.query(
      'translation_versions',
      where: 'sentence_id = ?',
      whereArgs: [sentenceId],
      orderBy: 'created_at DESC',
    );
  }

  Future<Map<String, Object?>?> translationDetail(String sentenceId) async {
    final rows = await db.rawQuery(
      '''
      SELECT t.*, r.id AS review_id, r.previous_text, r.candidate_text
      FROM translations t LEFT JOIN translation_reviews r ON r.sentence_id = t.sentence_id AND r.status = 'pending'
      WHERE t.sentence_id = ? LIMIT 1
      ''',
      [sentenceId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  // ------------------------------------------------------------- annotations
  Future<List<Annotation>> annotations({String? bookId}) async {
    final rows = await db.query(
      'annotations',
      where: bookId == null ? null : 'book_id = ?',
      whereArgs: bookId == null ? null : [bookId],
      orderBy: 'created_at DESC',
    );
    return [
      for (final row in rows)
        Annotation(
          id: row['id'] as String,
          bookId: row['book_id'] as String,
          content: row['content'] as String,
          chapterId: row['chapter_id'] as String?,
          paragraphId: row['paragraph_id'] as String?,
          sentenceId: row['sentence_id'] as String?,
          quote: row['quote'] as String?,
          color: row['color'] as String? ?? 'amber',
          tags: _decodeStringList(row['tags']),
          createdAt: row['created_at'] as String?,
        ),
    ];
  }

  Future<Annotation> createAnnotation({
    required String bookId,
    required String content,
    String? chapterId,
    String? paragraphId,
    String? sentenceId,
    String? quote,
    String color = 'amber',
  }) async {
    final now = nowIso();
    final annotation = Annotation(
      id: newLocalId('anno'),
      bookId: bookId,
      content: content,
      chapterId: chapterId,
      paragraphId: paragraphId,
      sentenceId: sentenceId,
      quote: quote,
      color: color,
      createdAt: now,
    );
    await db.insert('annotations', {
      'id': annotation.id,
      'book_id': bookId,
      'chapter_id': chapterId,
      'paragraph_id': paragraphId,
      'sentence_id': sentenceId,
      'quote': quote,
      'content': content,
      'color': color,
      'tags': '[]',
      'created_at': now,
      'updated_at': now,
    });
    return annotation;
  }

  Future<void> deleteAnnotation(String id) async {
    await db.delete('annotations', where: 'id = ?', whereArgs: [id]);
  }

  // --------------------------------------------------------------- bookmarks
  Future<List<Bookmark>> bookmarks({String? bookId}) async {
    final rows = await db.query(
      'bookmarks',
      where: bookId == null ? null : 'book_id = ?',
      whereArgs: bookId == null ? null : [bookId],
      orderBy: 'created_at DESC',
    );
    return [
      for (final row in rows)
        Bookmark(
          id: row['id'] as String,
          bookId: row['book_id'] as String,
          chapterId: row['chapter_id'] as String,
          paragraphId: row['paragraph_id'] as String?,
          sentenceId: row['sentence_id'] as String?,
          label: row['label'] as String?,
          positionRatio: (row['position_ratio'] as num? ?? 0).toDouble(),
          createdAt: row['created_at'] as String?,
        ),
    ];
  }

  Future<Bookmark> createBookmark({
    required String bookId,
    required String chapterId,
    String? paragraphId,
    String? sentenceId,
    String? label,
    double positionRatio = 0,
  }) async {
    final now = nowIso();
    final bookmark = Bookmark(
      id: newLocalId('bm'),
      bookId: bookId,
      chapterId: chapterId,
      paragraphId: paragraphId,
      sentenceId: sentenceId,
      label: label,
      positionRatio: positionRatio,
      createdAt: now,
    );
    await db.insert('bookmarks', {
      'id': bookmark.id,
      'book_id': bookId,
      'chapter_id': chapterId,
      'paragraph_id': paragraphId,
      'sentence_id': sentenceId,
      'label': label,
      'position_ratio': positionRatio,
      'created_at': now,
      'updated_at': now,
    });
    return bookmark;
  }

  Future<void> deleteBookmark(String id) async {
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------- progress
  Future<ReaderProgress?> progress(String bookId) async {
    final rows = await db.query(
      'reading_progress',
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return ReaderProgress(
      bookId: bookId,
      chapterId: row['chapter_id'] as String?,
      paragraphId: row['paragraph_id'] as String?,
      paragraphIndex: row['paragraph_index'] as int? ?? 0,
      sentenceId: row['sentence_id'] as String?,
      positionRatio: (row['position_ratio'] as num? ?? 0).toDouble(),
      updatedAt: row['updated_at'] as String?,
    );
  }

  Future<void> saveProgress(ReaderProgress progress) async {
    final now = nowIso();
    await db.insert('reading_progress', {
      'book_id': progress.bookId,
      'chapter_id': progress.chapterId,
      'paragraph_id': progress.paragraphId,
      'paragraph_index': progress.paragraphIndex,
      'sentence_id': progress.sentenceId,
      'position_ratio': progress.positionRatio,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await setLastRead(progress.bookId);
  }

  // ------------------------------------------------------------------- tasks
  Future<TaskInfo> createTask({
    required String type,
    required String title,
    required int total,
    String? bookId,
    String? chapterId,
    Map<String, Object?> result = const {},
  }) async {
    final now = nowIso();
    final id = newLocalId('task');
    await db.insert('tasks', {
      'id': id,
      'type': type,
      'status': 'queued',
      'title': title,
      'book_id': bookId,
      'chapter_id': chapterId,
      'progress': 0,
      'total': total,
      'completed': 0,
      'failed_count': 0,
      'result': jsonEncode(result),
      'created_at': now,
      'updated_at': now,
    });
    return (await getTask(id))!;
  }

  Future<void> updateTask(
    String id, {
    String? status,
    double? progress,
    int? completed,
    int? failedCount,
    String? error,
    Map<String, Object?>? result,
    int? total,
  }) async {
    final values = <String, Object?>{
      if (status != null) 'status': status,
      if (progress != null) 'progress': progress,
      if (completed != null) 'completed': completed,
      if (failedCount != null) 'failed_count': failedCount,
      if (error != null) 'error': error,
      if (result != null) 'result': jsonEncode(result),
      if (total != null) 'total': total,
      'updated_at': nowIso(),
    };
    await db.update('tasks', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<TaskInfo?> getTask(String id) async {
    final rows = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _taskFromRow(rows.first);
  }

  Future<List<TaskInfo>> tasks() async {
    final rows = await db.query(
      'tasks',
      orderBy: 'created_at DESC',
      limit: 200,
    );
    final active = rows
        .where((row) => row['status'] == 'running' || row['status'] == 'queued')
        .toList();
    final finished = rows
        .where((row) => row['status'] != 'running' && row['status'] != 'queued')
        .toList();
    return [...active, ...finished].map(_taskFromRow).toList();
  }

  TaskInfo _taskFromRow(Map<String, Object?> row) => TaskInfo(
    id: row['id'] as String,
    type: row['type'] as String? ?? '',
    status: row['status'] as String? ?? 'queued',
    title: row['title'] as String? ?? '任务',
    progress: (row['progress'] as num? ?? 0).toDouble(),
    total: row['total'] as int? ?? 0,
    completed: row['completed'] as int? ?? 0,
    failedCount: row['failed_count'] as int? ?? 0,
    error: row['error'] as String?,
    bookId: row['book_id'] as String?,
    chapterId: row['chapter_id'] as String?,
    result: _decodeMap(row['result']),
  );

  Future<void> cancelTask(String id) async {
    await updateTask(id, status: 'cancelled');
  }

  // ---------------------------------------------------------------- AI config
  Future<List<AiProviderRecord>> listProviders() async {
    final rows = await db.query('ai_providers', orderBy: 'created_at ASC');
    return rows.map((row) => AiProviderRecord.fromRow(row)).toList();
  }

  Future<AiProviderRecord?> getProvider(String id) async {
    final rows = await db.query(
      'ai_providers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : AiProviderRecord.fromRow(rows.first);
  }

  Future<void> upsertProvider(AiProviderRecord provider) async {
    final now = nowIso();
    await db.insert('ai_providers', {
      'id': provider.id,
      'name': provider.name,
      'kind': provider.kind,
      'base_url': provider.baseUrl,
      'notes': provider.notes,
      'enabled': provider.enabled ? 1 : 0,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteProvider(String id) async {
    await db.delete('ai_providers', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<AiModelRecord>> listModels() async {
    final rows = await db.query('ai_models', orderBy: 'created_at ASC');
    return rows.map(AiModelRecord.fromRow).toList();
  }

  Future<void> upsertModel(AiModelRecord model) async {
    final now = nowIso();
    await db.transaction((txn) async {
      if (model.isDefaultTranslation) {
        await txn.update('ai_models', {'is_default_translation': 0});
      }
      if (model.isDefaultChat) {
        await txn.update('ai_models', {'is_default_chat': 0});
      }
      await txn.insert('ai_models', {
        'id': model.id,
        'provider_id': model.providerId,
        'name': model.name,
        'display_name': model.displayName,
        'context_window': model.contextWindow,
        'max_output_tokens': model.maxOutputTokens,
        'timeout_seconds': model.timeoutSeconds,
        'capabilities': jsonEncode(model.capabilities),
        'supports_json': model.supportsJson ? 1 : 0,
        'is_default_translation': model.isDefaultTranslation ? 1 : 0,
        'is_default_chat': model.isDefaultChat ? 1 : 0,
        'enabled': model.enabled ? 1 : 0,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> deleteModel(String id) async {
    await db.delete('ai_models', where: 'id = ?', whereArgs: [id]);
  }

  Future<AiModelRecord?> defaultModel(String capability) async {
    final column = capability == 'translation'
        ? 'is_default_translation'
        : 'is_default_chat';
    final rows = await db.query(
      'ai_models',
      where: '$column = 1 AND enabled = 1',
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AiModelRecord.fromRow(rows.first);
  }

  // ------------------------------------------------------------------ prompts
  Future<List<PromptRecord>> allPrompts() async {
    final rows = await db.query(
      'prompt_templates',
      orderBy: 'key ASC, version DESC',
    );
    return rows.map(PromptRecord.fromRow).toList();
  }

  Future<PromptRecord?> activePrompt(String key) async {
    final rows = await db.query(
      'prompt_templates',
      where: 'key = ? AND is_active = 1',
      whereArgs: [key],
      orderBy: 'version DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : PromptRecord.fromRow(rows.first);
  }

  Future<PromptRecord?> promptVersion(String key, int version) async {
    final rows = await db.query(
      'prompt_templates',
      where: 'key = ? AND version = ?',
      whereArgs: [key, version],
      limit: 1,
    );
    return rows.isEmpty ? null : PromptRecord.fromRow(rows.first);
  }

  Future<void> insertPrompt(PromptRecord prompt) async {
    await db.insert('prompt_templates', {
      'id': prompt.id,
      'key': prompt.key,
      'version': prompt.version,
      'name': prompt.name,
      'description': prompt.description,
      'template': prompt.template,
      'variables': jsonEncode(prompt.variables),
      'is_active': prompt.isActive ? 1 : 0,
      'created_at': prompt.createdAt ?? nowIso(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> activatePrompt(String key, int version) async {
    await db.transaction((txn) async {
      await txn.update(
        'prompt_templates',
        {'is_active': 0},
        where: 'key = ?',
        whereArgs: [key],
      );
      await txn.update(
        'prompt_templates',
        {'is_active': 1},
        where: 'key = ? AND version = ?',
        whereArgs: [key, version],
      );
    });
  }

  // --------------------------------------------------------------- settings
  Future<String?> getSetting(String key) async {
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // --------------------------------------------------------------- helpers
  List<String> _decodeStringList(Object? value) {
    if (value is List) return value.map((item) => '$item').toList();
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded.map((item) => '$item').toList();
      } catch (_) {
        return [value];
      }
    }
    return const [];
  }

  Map<String, dynamic> _decodeMap(Object? value) {
    if (value is Map) return value.cast<String, dynamic>();
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {
        return const {};
      }
    }
    return const {};
  }

  Future<int> countAnnotations(String bookId) async {
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM annotations WHERE book_id = ?',
            [bookId],
          ),
        ) ??
        0;
  }

  Future<int> countBookmarks(String bookId) async {
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM bookmarks WHERE book_id = ?',
            [bookId],
          ),
        ) ??
        0;
  }

  Future<double> overallTranslationPercent() async {
    final total =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM sentences'),
        ) ??
        0;
    if (total == 0) return 0;
    final translated =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM translations'),
        ) ??
        0;
    return translated / total * 100;
  }

  Future<int> totalSentences() async {
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM sentences'),
        ) ??
        0;
  }

  Future<List<Map<String, Object?>>> searchFts(
    String query, {
    String? bookId,
    String? scope,
  }) async {
    if (!database.ftsAvailable) return const [];
    final match = _ftsQuery(query);
    if (match.isEmpty) return const [];
    try {
      final where = StringBuffer('search_fts MATCH ?');
      final args = <Object?>[match];
      if (bookId != null && bookId.isNotEmpty) {
        where.write(' AND book_id = ?');
        args.add(bookId);
      }
      if (scope == 'original' || scope == 'translation') {
        where.write(' AND doc_type = ?');
        args.add(scope);
      }
      return await db.rawQuery(
        'SELECT text, book_id, chapter_id, sentence_id, doc_type FROM search_fts WHERE $where LIMIT 100',
        args,
      );
    } catch (_) {
      return const [];
    }
  }

  String _ftsQuery(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'["*:^(){}]'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '"$part"')
        .join(' ');
    return cleaned;
  }

  Future<void> indexSentence({
    required String sentenceId,
    required String bookId,
    required String chapterId,
    required String text,
    required String docType,
  }) async {
    if (!database.ftsAvailable) return;
    try {
      await db.delete(
        'search_fts',
        where: 'sentence_id = ? AND doc_type = ?',
        whereArgs: [sentenceId, docType],
      );
      await db.insert('search_fts', {
        'text': text,
        'book_id': bookId,
        'chapter_id': chapterId,
        'sentence_id': sentenceId,
        'doc_type': docType,
      });
    } catch (_) {
      // Search remains available through the LIKE fallback.
    }
  }

  Future<void> removeSentenceFromIndex(String sentenceId) async {
    if (!database.ftsAvailable) return;
    try {
      await db.delete(
        'search_fts',
        where: 'sentence_id = ?',
        whereArgs: [sentenceId],
      );
    } catch (_) {
      // Ignore.
    }
  }

  Future<void> resetSearchIndex() async {
    if (!database.ftsAvailable) return;
    try {
      await db.delete('search_fts');
      final rows = await db.rawQuery(
        'SELECT s.id, s.book_id, s.chapter_id, s.original_text, t.text AS translation_text FROM sentences s LEFT JOIN translations t ON t.sentence_id = s.id',
      );
      for (final row in rows) {
        await indexSentence(
          sentenceId: row['id'] as String,
          bookId: row['book_id'] as String,
          chapterId: row['chapter_id'] as String,
          text: row['original_text'] as String? ?? '',
          docType: 'original',
        );
        final translation = row['translation_text'] as String?;
        if (translation != null && translation.isNotEmpty) {
          await indexSentence(
            sentenceId: row['id'] as String,
            bookId: row['book_id'] as String,
            chapterId: row['chapter_id'] as String,
            text: translation,
            docType: 'translation',
          );
        }
      }
    } catch (_) {
      // Ignore.
    }
  }

  Future<void> importSentencesSearchIndex(String bookId) async {
    final rows = await db.rawQuery(
      'SELECT s.id, s.chapter_id, s.original_text FROM sentences s WHERE s.book_id = ?',
      [bookId],
    );
    for (final row in rows) {
      await indexSentence(
        sentenceId: row['id'] as String,
        bookId: bookId,
        chapterId: row['chapter_id'] as String,
        text: row['original_text'] as String? ?? '',
        docType: 'original',
      );
    }
  }

  Future<Map<String, String>> bookAndChapterTitles(
    String bookId,
    String chapterId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT b.title AS book_title, c.title AS chapter_title FROM books b LEFT JOIN chapters c ON c.id = ? WHERE b.id = ?',
      [chapterId, bookId],
    );
    if (rows.isEmpty) return const {};
    return {
      'book': rows.first['book_title'] as String? ?? '',
      'chapter': rows.first['chapter_title'] as String? ?? '',
    };
  }

  Future<List<Map<String, Object?>>> searchSentencesLike(
    String query, {
    String? bookId,
    String? scope,
  }) async {
    final where = StringBuffer(
      "(s.original_text LIKE ? OR COALESCE(t.text,'') LIKE ?)",
    );
    final args = <Object?>['%$query%', '%$query%'];
    if (bookId != null && bookId.isNotEmpty) {
      where.write(' AND s.book_id = ?');
      args.add(bookId);
    }
    if (scope == 'original') {
      where.write(' AND s.original_text LIKE ?');
      args.add('%$query%');
    } else if (scope == 'translation') {
      where.write(" AND COALESCE(t.text,'') LIKE ?");
      args.add('%$query%');
    }
    return db.rawQuery('''
      SELECT s.id AS sentence_id, s.book_id, s.chapter_id, s.original_text,
             t.text AS translation_text, b.title AS book_title, c.title AS chapter_title
      FROM sentences s
      JOIN books b ON b.id = s.book_id
      JOIN chapters c ON c.id = s.chapter_id
      LEFT JOIN translations t ON t.sentence_id = s.id
      WHERE $where
      ORDER BY s.book_id, s.chapter_id, s.ordinal
      LIMIT 100
      ''', args);
  }

  Future<void> deleteBooksCache() async {
    // Kept for API compatibility with the previous mobile-only repository.
  }
}

int clampInt(int value, int min, int max) =>
    math.min(math.max(value, min), max);
