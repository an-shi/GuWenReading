import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/models.dart';
import 'ai_service.dart';
import 'local_models.dart';
import 'local_store.dart';
import 'tokenizer_adapter.dart';

class TranslationService {
  TranslationService({
    required this.store,
    required this.aiSettings,
    required this.client,
  });

  final LocalStore store;
  final AiSettingsService aiSettings;
  final AiJsonClient client;

  static const _cachePolicyVersion = 2;

  Future<TaskInfo> startChapterTranslation(
    String chapterId, {
    bool retranslate = false,
  }) async {
    final active = await store.activeTask(
      type: 'translation',
      chapterId: chapterId,
    );
    if (active != null && active.status != 'paused') return active;
    if (active != null) {
      await store.updateTask(active.id, status: 'running', error: null);
      unawaited(_run(active.id, chapterId, retranslate));
      return (await store.getTask(active.id)) ?? active;
    }
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
    final promptVersion = await aiSettings.activePromptVersion('translation');
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
    final total = targets.length;
    await store.updateTask(taskId, status: 'running', total: total);
    var completed = 0;
    var failed = 0;
    var cached = 0;

    final pending = <Sentence>[];
    final cacheKeys = <String, String>{};
    for (final sentence in targets) {
      final cacheKey = _sentenceCacheKey(
        sentence,
        content,
        resolved.label,
        promptVersion,
      );
      cacheKeys[sentence.id] = cacheKey;
      final cachedText = await store.translationSentenceCache(cacheKey);
      if (cachedText == null || cachedText.trim().isEmpty) {
        pending.add(sentence);
        continue;
      }
      await _saveTranslation(
        content: content,
        sentence: sentence,
        text: cachedText,
        modelLabel: resolved.label,
        promptVersion: promptVersion,
      );
      cached += 1;
      completed += 1;
    }
    if (pending.isEmpty) {
      await store.refreshBookStats(content.bookId);
      await store.updateTask(
        taskId,
        status: 'completed',
        progress: 100,
        completed: completed,
        total: total,
        result: {
          'completed': completed,
          'failed': 0,
          'cached': cached,
          'model': resolved.label,
        },
      );
      return;
    }
    await store.updateTask(
      taskId,
      progress: completed / total * 100,
      completed: completed,
      failedCount: failed,
    );

    final tokenizer = TokenizerRegistry.forModel(resolved.model);
    final batchTokens = _batchTokenBudget(resolved.model);
    var batchStart = 0;
    while (batchStart < pending.length) {
      final task = await store.getTask(taskId);
      if (task == null ||
          task.status == 'cancelled' ||
          task.status == 'paused') {
        return;
      }
      final batch = <Sentence>[];
      var tokens = 0;
      while (batchStart < pending.length &&
          (tokens < batchTokens || batch.isEmpty)) {
        final sentence = pending[batchStart];
        batch.add(sentence);
        tokens += tokenizer.count(sentence.originalText).tokens + 6;
        batchStart += 1;
      }
      try {
        final localById = <int, Sentence>{
          for (var i = 0; i < batch.length; i++) i + 1: batch[i],
        };
        final items = [
          for (final entry in localById.entries)
            {'id': entry.key, 'text': entry.value.originalText},
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
            .convert(
              utf8.encode(
                '${resolved.label}|v$promptVersion|p$_cachePolicyVersion|$prompt',
              ),
            )
            .toString();
        final cachedRows = await store.db.query(
          'translation_cache',
          where: 'cache_key = ?',
          whereArgs: [cacheKey],
          limit: 1,
        );
        Map<String, dynamic> data;
        var fromBatchCache = false;
        if (cachedRows.isNotEmpty) {
          data = jsonDecode(
            cachedRows.first['text'] as String,
          ) as Map<String, dynamic>;
          fromBatchCache = true;
        } else {
          data = await client.chatJson(
            purpose: 'translation',
            prompt: prompt,
            taskId: taskId,
            taskType: 'translation',
          );
          await store.db.insert('translation_cache', {
            'cache_key': cacheKey,
            'text': jsonEncode(data),
            'created_at': DateTime.now().toUtc().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        final translations = jsonList(data['translations']).isNotEmpty
            ? jsonList(data['translations'])
            : jsonList(data['items']);
        final byId = <int, String>{};
        for (final item in translations) {
          final rawId = item['id'] ?? item['i'];
          final index = rawId is int ? rawId : int.tryParse('$rawId'.trim());
          final text = jsonString(item['text'] ?? item['t']);
          if (index == null || text == null || text.trim().isEmpty) continue;
          byId[index] = text.trim();
        }
        if (fromBatchCache) cached += byId.length;
        for (final entry in localById.entries) {
          final sentence = entry.value;
          final text = byId[entry.key];
          if (text == null) {
            failed += 1;
            await store.setSentenceState(
              sentence.id,
              'failed',
              error: 'AI 未返回该句译文',
            );
            continue;
          }
          await _saveTranslation(
            content: content,
            sentence: sentence,
            text: text,
            modelLabel: resolved.label,
            promptVersion: promptVersion,
          );
          final sentenceCacheKey = cacheKeys[sentence.id];
          if (sentenceCacheKey != null) {
            await _putSentenceCache(
              sentence: sentence,
              content: content,
              cacheKey: sentenceCacheKey,
              modelLabel: resolved.label,
              promptVersion: promptVersion,
              text: text,
            );
          }
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
        progress: (completed + failed) / total * 100,
        completed: completed,
        failedCount: failed,
      );
      if (await _pauseIfBudgetExceeded(taskId)) return;
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

  Future<void> _saveTranslation({
    required ChapterContent content,
    required Sentence sentence,
    required String text,
    required String modelLabel,
    required int promptVersion,
  }) async {
    await store.upsertTranslation(
      sentenceId: sentence.id,
      text: text.trim(),
      origin: 'ai',
      modelName: modelLabel,
      promptVersion: promptVersion,
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
      chapterId: content.chapterId,
      text: indexedText,
      docType: 'translation',
    );
  }

  Future<void> _putSentenceCache({
    required Sentence sentence,
    required ChapterContent content,
    required String cacheKey,
    required String modelLabel,
    required int promptVersion,
    required String text,
  }) async {
    await store.putTranslationSentenceCache(
      cacheKey: cacheKey,
      sourceHash: sha256.convert(utf8.encode(sentence.originalText)).toString(),
      contextHash: _contextHash(content, sentence),
      modelLabel: modelLabel,
      promptVersion: promptVersion,
      translatedText: text.trim(),
    );
  }

  String _sentenceCacheKey(
    Sentence sentence,
    ChapterContent content,
    String modelLabel,
    int promptVersion,
  ) {
    final sourceHash = sha256
        .convert(utf8.encode(sentence.originalText))
        .toString();
    return sha256
        .convert(
          utf8.encode(
            '$sourceHash|${_contextHash(content, sentence)}|$modelLabel|'
            'v$promptVersion|p$_cachePolicyVersion',
          ),
        )
        .toString();
  }

  String _contextHash(ChapterContent content, Sentence sentence) {
    final before = _context(content, sentence, before: true);
    final after = _context(content, sentence, before: false);
    return sha256.convert(utf8.encode('$before|$after')).toString();
  }

  Future<bool> _pauseIfBudgetExceeded(String taskId) async {
    final budget = await readAiTaskBudget();
    if (budget <= 0) return false;
    final task = await store.getTask(taskId);
    if (task == null || task.cost < budget) return false;
    await store.updateTask(
      taskId,
      status: 'paused',
      error:
          '已达到单次任务费用上限（${task.cost.toStringAsFixed(4)} / '
          '${budget.toStringAsFixed(4)}）。请提高预算后重新开始任务。',
    );
    return true;
  }

  /// Token budget for one translation batch, excluding the fixed prompt.
  ///
  /// 20% headroom is kept for the system prompt, book/chapter metadata and
  /// context sentences. Output size is bounded by 75% of max output so a
  /// response cannot be truncated by the provider.
  int _batchTokenBudget(AiModelRecord model) {
    final inputBound = math.max(
      400,
      ((model.contextWindow - model.maxOutputTokens - 500) * 0.8).round(),
    );
    final outputBound = math.max(400, (model.maxOutputTokens * 0.75).round());
    return math.max(400, math.min(6000, math.min(outputBound, inputBound)));
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
      final parts = <String>[];
      final needsMore =
          sentence.originalText.length >= 80 ||
          RegExp(r'^[其此是彼故然則而曰蓋夫]').hasMatch(sentence.originalText);
      if (before) {
        if (index > 0) parts.add(paragraph.sentences[index - 1].originalText);
        if (needsMore && i > 0) {
          parts.add(_truncate(paragraphs[i - 1].originalText, 360));
        }
      } else {
        if (index + 1 < paragraph.sentences.length) {
          parts.add(paragraph.sentences[index + 1].originalText);
        }
        if (needsMore &&
            i + 1 < paragraphs.length &&
            paragraphs[i + 1].sentences.isNotEmpty) {
          parts.add(
            _truncate(paragraphs[i + 1].sentences.first.originalText, 360),
          );
        }
      }
      return _truncate(parts.join(), 700);
    }
    return '';
  }

  String _truncate(String text, int maxLength) =>
      text.length <= maxLength ? text : text.substring(0, maxLength);

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

  Future<void> retranslateSentence(
    String sentenceId, {
    bool useCache = true,
  }) async {
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
    final promptVersion = await aiSettings.activePromptVersion('translation');
    final content = await store.chapterContent(row['chapter_id'] as String);
    final sentence = content?.paragraphs
        .expand((paragraph) => paragraph.sentences)
        .where((item) => item.id == sentenceId)
        .firstOrNull;
    if (content != null && sentence != null && useCache) {
      final cacheKey = _sentenceCacheKey(
        sentence,
        content,
        resolved.label,
        promptVersion,
      );
      final cachedText = await store.translationSentenceCache(cacheKey);
      if (cachedText != null && cachedText.trim().isNotEmpty) {
        await _saveTranslation(
          content: content,
          sentence: sentence,
          text: cachedText,
          modelLabel: resolved.label,
          promptVersion: promptVersion,
        );
        await store.refreshBookStats(content.bookId);
        return;
      }
    }
    final prompt = await aiSettings.render('translation', {
      'book_title': row['book_title'] ?? '',
      'author': row['book_author'] ?? '未详',
      'chapter_title': row['chapter_title'] ?? '',
      'context_before': content != null && sentence != null
          ? _context(content, sentence, before: true)
          : '',
      'context_after': content != null && sentence != null
          ? _context(content, sentence, before: false)
          : '',
      'items_json': jsonEncode([
        {'id': 1, 'text': row['original_text'] ?? ''},
      ]),
    });
    final data = await client.chatJson(
      purpose: 'translation',
      prompt: prompt,
      taskType: 'translation',
    );
    final translations = jsonList(data['translations']).isNotEmpty
        ? jsonList(data['translations'])
        : jsonList(data['items']);
    final match = translations
        .where((item) => '${item['id'] ?? item['i']}'.trim() == '1')
        .firstOrNull;
    final text = jsonString(match?['text'] ?? match?['t']);
    if (text == null || text.trim().isEmpty) {
      throw TranslationException('AI 未返回该句译文');
    }
    await store.upsertTranslation(
      sentenceId: sentenceId,
      text: text.trim(),
      origin: 'ai',
      modelName: resolved.label,
      promptVersion: promptVersion,
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
    if (content != null && sentence != null) {
      await _putSentenceCache(
        sentence: sentence,
        content: content,
        cacheKey: _sentenceCacheKey(
          sentence,
          content,
          resolved.label,
          promptVersion,
        ),
        modelLabel: resolved.label,
        promptVersion: promptVersion,
        text: text,
      );
    }
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
