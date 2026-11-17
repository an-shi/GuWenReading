import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/models.dart';
import 'ai_service.dart';
import 'local_store.dart';

class TranslationService {
  TranslationService({
    required this.store,
    required this.aiSettings,
    required this.client,
  });

  final LocalStore store;
  final AiSettingsService aiSettings;
  final AiJsonClient client;

  Future<TaskInfo> startChapterTranslation(
    String chapterId, {
    bool retranslate = false,
  }) async {
    final content = await store.chapterContent(chapterId);
    if (content == null) throw TranslationException('章节不存在');
    final task = await store.createTask(
      type: 'translation',
      title: '翻译《${content.bookTitle}》· ${content.chapterTitle}',
      total: content.paragraphs.fold<int>(
        0,
        (sum, paragraph) => sum + paragraph.sentences.length,
      ),
      bookId: content.bookId,
      chapterId: chapterId,
    );
    unawaited(_run(task.id, chapterId, retranslate));
    return task;
  }

  Future<void> _run(String taskId, String chapterId, bool retranslate) async {
    final content = await store.chapterContent(chapterId);
    if (content == null) {
      await store.updateTask(taskId, status: 'failed', error: '章节不存在');
      return;
    }
    final resolved = await aiSettings.resolve(purpose: 'translation');
    if (resolved == null) {
      await store.updateTask(taskId, status: 'failed', error: '尚未配置默认翻译模型');
      return;
    }
    final allSentences = content.paragraphs
        .expand((paragraph) => paragraph.sentences)
        .toList();
    final targets = allSentences.where((sentence) {
      if (sentence.translation?.isManual ?? false) return false;
      if (retranslate) return true;
      return sentence.translation == null;
    }).toList();
    if (targets.isEmpty) {
      await store.updateTask(
        taskId,
        status: 'completed',
        progress: 100,
        completed: 0,
        total: 0,
        result: {'completed': 0, 'failed': 0, 'cached': 0},
      );
      return;
    }
    await store.updateTask(taskId, status: 'running', total: targets.length);
    var completed = 0;
    var failed = 0;
    var cached = 0;
    var batchStart = 0;
    while (batchStart < targets.length) {
      final task = await store.getTask(taskId);
      if (task == null || task.status == 'cancelled') return;
      final batch = <Sentence>[];
      var chars = 0;
      while (batchStart < targets.length && (chars < 2200 || batch.isEmpty)) {
        final sentence = targets[batchStart];
        batch.add(sentence);
        chars += sentence.originalText.length;
        batchStart += 1;
      }
      try {
        final items = [
          for (final sentence in batch)
            {'id': sentence.id, 'text': sentence.originalText},
        ];
        final prompt = await aiSettings.render('translation', {
          'book_title': content.bookTitle,
          'author': content.bookAuthor ?? '未详',
          'chapter_title': content.chapterTitle,
          'context_before': _context(content, batch.first, before: true),
          'context_after': _context(content, batch.last, before: false),
          'items_json': jsonEncode(items),
        });
        final cacheKey = sha256
            .convert(utf8.encode('${resolved.label}|$prompt'))
            .toString();
        final cachedRows = await store.db.query(
          'translation_cache',
          where: 'cache_key = ?',
          whereArgs: [cacheKey],
          limit: 1,
        );
        Map<String, dynamic> data;
        if (cachedRows.isNotEmpty) {
          data = jsonDecode(
            cachedRows.first['text'] as String,
          ) as Map<String, dynamic>;
          cached += batch.length;
        } else {
          data = await client.chatJson(purpose: 'translation', prompt: prompt);
          await store.db.insert('translation_cache', {
            'cache_key': cacheKey,
            'text': jsonEncode(data),
            'created_at': DateTime.now().toUtc().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        final translations = jsonList(data['translations']).isNotEmpty
            ? jsonList(data['translations'])
            : jsonList(data['items']);
        final byId = {
          for (final item in translations)
            if (jsonString(item['id']) != null)
              jsonString(item['id'])!: jsonString(item['text']) ?? '',
        };
        for (final sentence in batch) {
          final text = byId[sentence.id];
          if (text == null || text.trim().isEmpty) {
            failed += 1;
            await store.setSentenceState(
              sentence.id,
              'failed',
              error: 'AI 未返回该句译文',
            );
            continue;
          }
          await store.upsertTranslation(
            sentenceId: sentence.id,
            text: text.trim(),
            origin: 'ai',
            modelName: resolved.label,
            promptVersion: 1,
          );
          final current = await store.db.query(
            'translations',
            where: 'sentence_id = ?',
            whereArgs: [sentence.id],
            limit: 1,
          );
          final indexedText = current.isEmpty
              ? text.trim()
              : current.first['text'] as String? ?? text.trim();
          await store.indexSentence(
            sentenceId: sentence.id,
            bookId: content.bookId,
            chapterId: chapterId,
            text: indexedText,
            docType: 'translation',
          );
          completed += 1;
        }
      } catch (error) {
        failed += batch.length;
        for (final sentence in batch) {
          await store.setSentenceState(sentence.id, 'failed', error: '$error');
        }
      }
      await store.updateTask(
        taskId,
        progress: (completed + failed) / targets.length * 100,
        completed: completed,
        failedCount: failed,
      );
    }
    await store.refreshBookStats(content.bookId);
    await store.updateTask(
      taskId,
      status: failed == 0
          ? 'completed'
          : (completed == 0 ? 'failed' : 'partial'),
      progress: 100,
      completed: completed,
      failedCount: failed,
      result: {
        'completed': completed,
        'failed': failed,
        'cached': cached,
        'model': resolved.label,
      },
    );
  }

  String _context(
    ChapterContent content,
    Sentence sentence, {
    required bool before,
  }) {
    final paragraphs = content.paragraphs;
    for (var i = 0; i < paragraphs.length; i++) {
      final paragraph = paragraphs[i];
      final index = paragraph.sentences.indexWhere(
        (item) => item.id == sentence.id,
      );
      if (index < 0) continue;
      if (before) {
        final parts = <String>[];
        if (index > 1) parts.add(paragraph.sentences[index - 2].originalText);
        if (index > 0) parts.add(paragraph.sentences[index - 1].originalText);
        if (i > 0) parts.add(paragraphs[i - 1].originalText);
        return parts.join();
      }
      final parts = <String>[];
      if (index + 1 < paragraph.sentences.length) {
        parts.add(paragraph.sentences[index + 1].originalText);
      }
      if (index + 2 < paragraph.sentences.length) {
        parts.add(paragraph.sentences[index + 2].originalText);
      }
      if (i + 1 < paragraphs.length) parts.add(paragraphs[i + 1].originalText);
      return parts.join();
    }
    return '';
  }

  Future<void> saveManual(String sentenceId, String text) async {
    await store.upsertTranslation(
      sentenceId: sentenceId,
      text: text.trim(),
      origin: 'manual',
    );
    final rows = await store.db.query(
      'sentences',
      where: 'id = ?',
      whereArgs: [sentenceId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final bookId = rows.first['book_id'] as String;
      final chapterId = rows.first['chapter_id'] as String;
      await store.indexSentence(
        sentenceId: sentenceId,
        bookId: bookId,
        chapterId: chapterId,
        text: text.trim(),
        docType: 'translation',
      );
      await store.refreshBookStats(bookId);
    }
  }

  Future<void> retranslateSentence(String sentenceId) async {
    final rows = await store.db.rawQuery(
      '''
      SELECT s.*, c.title AS chapter_title, b.title AS book_title, b.author AS book_author
      FROM sentences s
      JOIN chapters c ON c.id = s.chapter_id
      JOIN books b ON b.id = s.book_id
      WHERE s.id = ?
      ''',
      [sentenceId],
    );
    if (rows.isEmpty) return;
    final row = rows.first;
    final resolved = await aiSettings.resolve(purpose: 'translation');
    if (resolved == null) throw TranslationException('尚未配置默认翻译模型');
    final prompt = await aiSettings.render('translation', {
      'book_title': row['book_title'] ?? '',
      'author': row['book_author'] ?? '未详',
      'chapter_title': row['chapter_title'] ?? '',
      'context_before': '',
      'context_after': '',
      'items_json': jsonEncode([
        {'id': sentenceId, 'text': row['original_text'] ?? ''},
      ]),
    });
    final data = await client.chatJson(purpose: 'translation', prompt: prompt);
    final translations = jsonList(data['translations']).isNotEmpty
        ? jsonList(data['translations'])
        : jsonList(data['items']);
    final match = translations
        .where((item) => jsonString(item['id']) == sentenceId)
        .firstOrNull;
    final text = jsonString(match?['text']);
    if (text == null || text.trim().isEmpty) {
      throw TranslationException('AI 未返回该句译文');
    }
    await store.upsertTranslation(
      sentenceId: sentenceId,
      text: text.trim(),
      origin: 'ai',
      modelName: resolved.label,
      promptVersion: 1,
    );
    final current = await store.db.query(
      'translations',
      where: 'sentence_id = ?',
      whereArgs: [sentenceId],
      limit: 1,
    );
    await store.indexSentence(
      sentenceId: sentenceId,
      bookId: row['book_id'] as String,
      chapterId: row['chapter_id'] as String,
      text: current.isEmpty
          ? text.trim()
          : current.first['text'] as String? ?? text.trim(),
      docType: 'translation',
    );
    await store.refreshBookStats(row['book_id'] as String);
  }

  Future<void> resolveReview(String reviewId, bool accept) async {
    await store.resolveReview(reviewId, accept);
    final rows = await store.db.query(
      'translation_reviews',
      where: 'id = ?',
      whereArgs: [reviewId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final sentenceRows = await store.db.query(
        'sentences',
        where: 'id = ?',
        whereArgs: [rows.first['sentence_id']],
        limit: 1,
      );
      if (sentenceRows.isNotEmpty) {
        await store.refreshBookStats(sentenceRows.first['book_id'] as String);
      }
    }
  }
}

class TranslationException implements Exception {
  TranslationException(this.message);
  final String message;
  @override
  String toString() => message;
}
