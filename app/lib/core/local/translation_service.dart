import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/models.dart';
import 'ai_scheduler.dart';
import 'ai_service.dart';
import 'budget_service.dart';
import 'local_engine/engine.dart';
import 'local_engine/lexicon.dart';
import 'local_models.dart';
import 'local_store.dart';
import 'quality_service.dart';
import 'tokenizer_adapter.dart';

class TranslationService {
  TranslationService({
    required this.store,
    required this.aiSettings,
    required this.client,
    BudgetService? budgets,
    QualityService? quality,
  }) : budgets = budgets ?? BudgetService(store: store),
       quality = quality ?? const QualityService();

  final LocalStore store;
  final AiSettingsService aiSettings;
  final AiJsonClient client;
  final BudgetService budgets;
  final QualityService quality;
  final LocalClassicalEngine localEngine = const LocalClassicalEngine();

  Future<String> _translationMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('translation_engine_mode') ?? 'ai';
    } catch (_) {
      return 'ai';
    }
  }

  static const _cachePolicyVersion = 2;

  Future<TaskInfo> startChapterTranslation(
    String chapterId, {
    bool retranslate = false,
  }) async {
    final active = await store.activeTask(
      type: 'translation',
      chapterId: chapterId,
    );
    if (active != null &&
        active.status != 'paused' &&
        active.status != 'interrupted') {
      return active;
    }
    if (active != null) {
      await store.claimTask(active.id, appInstanceId, stage: '恢复翻译');
      unawaited(_run(active.id, chapterId, retranslate));
      return (await store.getTask(active.id)) ?? active;
    }
    final content = await store.chapterContent(chapterId);
    if (content == null) throw TranslationException('章节不存在');
    final mode = await _translationMode();
    final resolved = mode == 'local'
        ? null
        : await aiSettings.resolve(purpose: 'translation');
    final estimate = mode == 'local'
        ? 0.0
        : await _estimateCost(content, resolved, retranslate);
    final task = await store.createTask(
      type: 'translation',
      title: mode == 'local'
          ? '本地推测翻译《${content.bookTitle}》· ${content.chapterTitle}'
          : '翻译《${content.bookTitle}》· ${content.chapterTitle}',
      total: content.paragraphs.fold<int>(
        0,
        (sum, paragraph) => sum + paragraph.sentences.length,
      ),
      bookId: content.bookId,
      chapterId: chapterId,
    );
    final reservation = await budgets.reserve(
      taskId: task.id,
      bookId: content.bookId,
      chapterId: chapterId,
      estimatedCost: estimate,
    );
    if (!reservation.allowed) {
      await store.updateTask(
        task.id,
        status: 'failed',
        error: reservation.message,
      );
      throw BudgetExceededException(reservation.message ?? '预算不足');
    }
    if (mode == 'local') {
      unawaited(_runLocal(task.id, chapterId, retranslate));
    } else if (mode == 'local_first') {
      unawaited(_runLocalFirst(task.id, chapterId, retranslate));
    } else if (mode == 'ai_reference') {
      unawaited(_runAiReference(task.id, chapterId, retranslate));
    } else {
      unawaited(_run(task.id, chapterId, retranslate));
    }
    return task;
  }

  Future<double> _estimateCost(
    ChapterContent content,
    ResolvedAiModel? resolved,
    bool retranslate,
  ) async {
    if (resolved == null) return 0;
    final tokenizer = TokenizerRegistry.forModel(resolved.model);
    var tokens = 0;
    for (final paragraph in content.paragraphs) {
      for (final sentence in paragraph.sentences) {
        if (sentence.translation?.isManual ?? false) continue;
        if (!retranslate && sentence.translation != null) continue;
        tokens += tokenizer.count(sentence.originalText).tokens;
      }
    }
    if (tokens == 0) return 0;
    return budgets.estimateCost(
      model: resolved.model,
      inputTokens: (tokens * 1.15).round() + 500,
      outputTokens: (tokens * 1.3).round() + 200,
    );
  }

  /// Resumes an interrupted or paused task without creating a duplicate.
  /// Successfully translated sentences and caches are reused.
  Future<void> resumeTask(String taskId) async {
    final task = await store.getTask(taskId);
    if (task == null ||
        task.type != 'translation' ||
        task.chapterId == null ||
        task.status == 'cancelled' ||
        task.status == 'completed') {
      return;
    }
    await store.claimTask(taskId, appInstanceId, stage: '恢复翻译');
    final mode = await _translationMode();
    if (mode == 'local') {
      unawaited(_runLocal(taskId, task.chapterId!, false));
    } else if (mode == 'local_first') {
      unawaited(_runLocalFirst(taskId, task.chapterId!, false));
    } else if (mode == 'ai_reference') {
      unawaited(_runAiReference(taskId, task.chapterId!, false));
    } else {
      unawaited(_run(taskId, task.chapterId!, false));
    }
  }

  Future<Map<String, LocalTranslationResult>> _localPass(
    String taskId,
    ChapterContent content,
    bool retranslate, {
    required bool save,
    required Set<LocalConfidence> saveLevels,
  }) async {
    final results = <String, LocalTranslationResult>{};
    var completed = 0;
    var high = 0;
    var medium = 0;
    var low = 0;
    final sentences = content.paragraphs
        .expand((paragraph) => paragraph.sentences)
        .toList();
    for (var index = 0; index < sentences.length; index++) {
      final sentence = sentences[index];
      if (sentence.translation?.isManual ?? false) continue;
      if (!retranslate && sentence.translation != null) continue;
      final previous = index > 0 ? sentences[index - 1].originalText : null;
      final next = index + 1 < sentences.length
          ? sentences[index + 1].originalText
          : null;
      final sourceHash = sha256
          .convert(utf8.encode(sentence.originalText))
          .toString();
      final cacheKey = sha256
          .convert(
            utf8.encode(
              '$sourceHash|${previous ?? ''}|${next ?? ''}|'
              '$lexiconVersion|${LocalClassicalEngine.engineVersion}',
            ),
          )
          .toString();
      LocalTranslationResult result;
      final cached = await store.localTranslationCache(cacheKey);
      if (cached != null) {
        try {
          result = LocalTranslationResult.fromJson(
            jsonDecode(cached) as Map<String, dynamic>,
          );
        } catch (_) {
          result = localEngine.translate(
            sentence.originalText,
            previousSentence: previous,
            nextSentence: next,
          );
        }
      } else {
        result = localEngine.translate(
          sentence.originalText,
          previousSentence: previous,
          nextSentence: next,
        );
        await store.putLocalTranslationCache(
          cacheKey: cacheKey,
          sourceHash: sourceHash,
          lexiconVersion: lexiconVersion,
          engineVersion: LocalClassicalEngine.engineVersion,
          resultJson: jsonEncode(result.toJson()),
        );
      }
      results[sentence.id] = result;
      switch (result.confidence) {
        case LocalConfidence.high:
          high += 1;
        case LocalConfidence.medium:
          medium += 1;
        case LocalConfidence.low:
          low += 1;
      }
      if (save && saveLevels.contains(result.confidence)) {
        await _saveLocalTranslation(
          content: content,
          sentence: sentence,
          result: result,
        );
        completed += 1;
      }
      if (index % 20 == 0) {
        await store.touchTask(
          taskId,
          stage: '本地推测 ${index + 1}/${sentences.length}',
          checkpoint: sentence.id,
        );
      }
    }
    await store.updateTask(
      taskId,
      progress: sentences.isEmpty ? 100 : completed / sentences.length * 100,
      completed: completed,
      result: {
        'local_count': results.length,
        'local_high': high,
        'local_medium': medium,
        'local_low': low,
        'local_saved': completed,
        'engine': LocalClassicalEngine.engineVersion,
        'lexicon_version': lexiconVersion,
      },
    );
    return results;
  }

  Future<void> _saveLocalTranslation({
    required ChapterContent content,
    required Sentence sentence,
    required LocalTranslationResult result,
  }) async {
    await store.upsertTranslation(
      sentenceId: sentence.id,
      text: result.text,
      origin: 'local_rule',
      modelName: '本地规则 v1 · ${result.confidenceLabel}',
      localAnalysis: jsonEncode(result.toJson()),
    );
    await store.indexSentence(
      sentenceId: sentence.id,
      bookId: content.bookId,
      chapterId: content.chapterId,
      text: result.text,
      docType: 'translation',
    );
  }

  Future<void> _runLocal(
    String taskId,
    String chapterId,
    bool retranslate,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final content = await store.chapterContent(chapterId);
      if (content == null) {
        await store.updateTask(taskId, status: 'failed', error: '章节不存在');
        return;
      }
      await store.claimTask(taskId, appInstanceId, stage: '本地规则分析');
      final results = await _localPass(
        taskId,
        content,
        retranslate,
        save: true,
        saveLevels: LocalConfidence.values.toSet(),
      );
      stopwatch.stop();
      await store.refreshBookStats(content.bookId);
      await store.updateTask(
        taskId,
        status: 'completed',
        progress: 100,
        completed: results.length,
        result: {
          'local_count': results.length,
          'local_high': results.values
              .where((result) => result.confidence == LocalConfidence.high)
              .length,
          'local_medium': results.values
              .where((result) => result.confidence == LocalConfidence.medium)
              .length,
          'local_low': results.values
              .where((result) => result.confidence == LocalConfidence.low)
              .length,
          'local_saved': results.length,
          'ai_count': 0,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'engine': LocalClassicalEngine.engineVersion,
        },
      );
    } finally {
      await budgets.release(taskId);
    }
  }

  Future<void> _runLocalFirst(
    String taskId,
    String chapterId,
    bool retranslate,
  ) async {
    final content = await store.chapterContent(chapterId);
    if (content == null) {
      await store.updateTask(taskId, status: 'failed', error: '章节不存在');
      await budgets.release(taskId);
      return;
    }
    await store.claimTask(taskId, appInstanceId, stage: '本地优先翻译');
    final results = await _localPass(
      taskId,
      content,
      retranslate,
      save: true,
      saveLevels: const {LocalConfidence.high, LocalConfidence.medium},
    );
    final low = results.values
        .where((result) => result.confidence == LocalConfidence.low)
        .length;
    if (low == 0) {
      await store.refreshBookStats(content.bookId);
      await store.updateTask(
        taskId,
        status: 'completed',
        progress: 100,
        completed: results.length,
        result: {
          'local_count': results.length,
          'local_saved': results.length,
          'ai_count': 0,
          'engine': LocalClassicalEngine.engineVersion,
        },
      );
      await budgets.release(taskId);
      return;
    }
    await _run(taskId, chapterId, retranslate);
  }

  Future<void> _runAiReference(
    String taskId,
    String chapterId,
    bool retranslate,
  ) async {
    final content = await store.chapterContent(chapterId);
    if (content == null) {
      await store.updateTask(taskId, status: 'failed', error: '章节不存在');
      await budgets.release(taskId);
      return;
    }
    final results = await _localPass(
      taskId,
      content,
      retranslate,
      save: false,
      saveLevels: const {},
    );
    await _run(
      taskId,
      chapterId,
      retranslate,
      references: {
        for (final entry in results.entries) entry.key: entry.value.text,
      },
    );
  }

  Future<void> _run(
    String taskId,
    String chapterId,
    bool retranslate, {
    Map<String, String>? references,
  }) async {
    try {
      await _runInner(taskId, chapterId, retranslate, references: references);
    } finally {
      await budgets.release(taskId);
    }
  }

  Future<void> _runInner(
    String taskId,
    String chapterId,
    bool retranslate, {
    Map<String, String>? references,
  }) async {
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
    final schemaVersion = await store.activeSchemaVersion('translation');
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
    await store.claimTask(taskId, appInstanceId, stage: '准备翻译');
    var completed = 0;
    var failed = 0;
    var cached = 0;
    var batchCount = 0;
    var qualityWarnings = 0;
    var qualityReviews = 0;

    final pending = <Sentence>[];
    final cacheKeys = <String, String>{};
    for (final sentence in targets) {
      final cacheKey = _sentenceCacheKey(
        sentence,
        content,
        resolved.label,
        promptVersion,
        schemaVersion,
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
        var prompt = await aiSettings.render('translation', {
          'book_title': content.bookTitle,
          'author': content.bookAuthor ?? '未详',
          'chapter_title': content.chapterTitle,
          'context_before': _context(content, batch.first, before: true),
          'context_after': _context(content, batch.last, before: false),
          'items_json': jsonEncode(items),
        });
        if (references != null) {
          final lines = <String>[];
          for (final entry in localById.entries) {
            final reference = references[entry.value.id];
            if (reference == null) continue;
            lines.add(
              '${entry.key}. ${entry.value.originalText}\n'
              '本地规则参考：$reference',
            );
          }
          if (lines.isNotEmpty) {
            prompt +=
                '\n\n以下是本地规则参考译文，可能有误，仅用于校正，不得直接照抄：\n'
                '${lines.join('\n')}';
          }
        }
        final cacheKey = sha256
            .convert(
              utf8.encode(
                '${resolved.label}|v$promptVersion|s$schemaVersion|'
                'p$_cachePolicyVersion|$prompt',
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
            promptVersion: promptVersion,
            schemaVersion: schemaVersion,
            shouldCancel: () async {
              final current = await store.getTask(taskId);
              return current == null ||
                  current.status == 'cancelled' ||
                  current.status == 'paused';
            },
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
        final report = quality.checkTranslations(
          translations: byId,
          originals: {
            for (final entry in localById.entries)
              entry.key: entry.value.originalText,
          },
        );
        await store.recordQualityReport(
          taskId: taskId,
          scope: 'translation_batch',
          reference: 'batch:$batchCount',
          status: report.level.wireValue,
          issues: report.issues.map((issue) => issue.toJson()).toList(),
        );
        if (report.level == QualityLevel.failed ||
            report.level == QualityLevel.needsReview) {
          qualityReviews += 1;
        } else if (report.level == QualityLevel.warning) {
          qualityWarnings += 1;
        }
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
      batchCount += 1;
      await store.touchTask(
        taskId,
        stage: '翻译批次 $batchCount',
        checkpoint: batch.last.id,
      );
      final current = await store.getTask(taskId);
      if (current != null) await budgets.adjust(taskId, current.cost);
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
        'quality_warnings': qualityWarnings,
        'quality_reviews': qualityReviews,
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
    int schemaVersion,
  ) {
    final sourceHash = sha256
        .convert(utf8.encode(sentence.originalText))
        .toString();
    return sha256
        .convert(
          utf8.encode(
            '$sourceHash|${_contextHash(content, sentence)}|$modelLabel|'
            'v$promptVersion|s$schemaVersion|p$_cachePolicyVersion',
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
    final message = await budgets.checkDuringTask(taskId);
    if (message == null) return false;
    await store.updateTask(
      taskId,
      status: 'paused',
      error: '$message。请提高预算后重新开始任务。',
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
    final beforeRows = await store.db.query(
      'translations',
      where: 'sentence_id = ?',
      whereArgs: [sentenceId],
      limit: 1,
    );
    if (beforeRows.isNotEmpty && beforeRows.first['origin'] == 'local_rule') {
      final sentenceRows = await store.db.query(
        'sentences',
        where: 'id = ?',
        whereArgs: [sentenceId],
        limit: 1,
      );
      await store.recordLocalRevision(
        sentenceId: sentenceId,
        bookId: sentenceRows.isEmpty
            ? null
            : sentenceRows.first['book_id'] as String?,
        chapterId: sentenceRows.isEmpty
            ? null
            : sentenceRows.first['chapter_id'] as String?,
        originalText: sentenceRows.isEmpty
            ? ''
            : '${sentenceRows.first['original_text'] ?? ''}',
        originalCandidate: beforeRows.first['text'] as String?,
        revisedText: text.trim(),
        note: '用户修订本地推测译文',
      );
    }
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
    final schemaVersion = await store.activeSchemaVersion('translation');
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
        schemaVersion,
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
      promptVersion: promptVersion,
      schemaVersion: schemaVersion,
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
          schemaVersion,
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
