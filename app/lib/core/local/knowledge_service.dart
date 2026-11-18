import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/models.dart';
import 'ai_scheduler.dart';
import 'ai_service.dart';
import 'app_database.dart';
import 'budget_service.dart';
import 'local_models.dart';
import 'local_store.dart';
import 'quality_service.dart';
import 'tokenizer_adapter.dart';

class KnowledgeService {
  KnowledgeService({
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

  static const _extractionPromptKey = 'knowledge_extract';

  Future<TaskInfo> startExtraction(String chapterId) async {
    final active = await store.activeTask(
      type: 'knowledge_extraction',
      chapterId: chapterId,
    );
    if (active != null &&
        active.status != 'paused' &&
        active.status != 'interrupted') {
      return active;
    }
    if (active != null) {
      await store.claimTask(active.id, appInstanceId, stage: '恢复知识抽取');
      unawaited(_runExtraction(active.id, chapterId));
      return (await store.getTask(active.id)) ?? active;
    }
    final content = await store.chapterContent(chapterId);
    if (content == null) throw KnowledgeException('章节不存在');
    final task = await store.createTask(
      type: 'knowledge_extraction',
      title: '抽取知识《${content.bookTitle}》· ${content.chapterTitle}',
      total: 1,
      bookId: content.bookId,
      chapterId: chapterId,
    );
    final resolved = await aiSettings.resolve(purpose: 'extraction');
    final estimate = resolved == null
        ? 0.0
        : _estimateCost(content, resolved.model);
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
    unawaited(_runExtraction(task.id, chapterId));
    return task;
  }

  double _estimateCost(ChapterContent content, AiModelRecord model) {
    final tokenizer = TokenizerRegistry.forModel(model);
    var tokens = 0;
    for (final paragraph in content.paragraphs) {
      for (final sentence in paragraph.sentences) {
        tokens += tokenizer.count(sentence.originalText).tokens;
      }
    }
    if (tokens == 0) return 0;
    return budgets.estimateCost(
      model: model,
      inputTokens: (tokens * 1.15).round() + 600,
      outputTokens: (tokens * 0.35).round() + 300,
    );
  }

  /// Resumes an interrupted or paused extraction task. Cached chunks are
  /// reused, so only unfinished chunks are requested again.
  Future<void> resumeTask(String taskId) async {
    final task = await store.getTask(taskId);
    if (task == null ||
        task.type != 'knowledge_extraction' ||
        task.chapterId == null ||
        task.status == 'cancelled' ||
        task.status == 'completed') {
      return;
    }
    await store.claimTask(taskId, appInstanceId, stage: '恢复知识抽取');
    unawaited(_runExtraction(taskId, task.chapterId!));
  }

  Future<void> _runExtraction(String taskId, String chapterId) async {
    try {
      await _runExtractionInner(taskId, chapterId);
    } finally {
      await budgets.release(taskId);
    }
  }

  Future<void> _runExtractionInner(String taskId, String chapterId) async {
    final content = await store.chapterContent(chapterId);
    if (content == null) {
      await store.updateTask(taskId, status: 'failed', error: '章节不存在');
      return;
    }
    final resolved = await aiSettings.resolve(purpose: 'extraction');
    if (resolved == null) {
      await store.updateTask(taskId, status: 'failed', error: '尚未配置默认知识抽取模型');
      return;
    }
    final promptVersion = await aiSettings.activePromptVersion(
      _extractionPromptKey,
    );
    final schemaVersion = await store.activeSchemaVersion(_extractionPromptKey);
    final routing = await aiSettings.knowledgeRoutingConfig();
    await store.recordRoutingDecision(
      taskId: taskId,
      taskType: 'knowledge_extraction',
      routedModelId: resolved.model.id,
      providerId: resolved.provider.id,
      mode: routing.mode,
      reason: '联合抽取使用知识抽取默认模型',
    );
    final chunks = _buildChunks(content, resolved.model);
    if (chunks.isEmpty) {
      await store.updateTask(
        taskId,
        status: 'completed',
        progress: 100,
        total: 0,
        completed: 0,
        result: {'cached': true, 'chunks': 0},
      );
      return;
    }
    final chapterHash = _chapterHash(content);
    final cachedState = await store.knowledgeExtractionState(chapterId);
    if (cachedState != null &&
        cachedState['status'] == 'completed' &&
        cachedState['content_hash'] == chapterHash &&
        cachedState['model_label'] == resolved.label &&
        cachedState['prompt_version'] == promptVersion &&
        cachedState['schema_version'] == schemaVersion) {
      await store.updateTask(
        taskId,
        status: 'completed',
        progress: 100,
        total: chunks.length,
        completed: chunks.length,
        result: {
          'cached_chunks': chunks.length,
          'chunks': chunks.length,
          'model': resolved.label,
        },
      );
      return;
    }
    await store.updateTask(
      taskId,
      status: 'running',
      total: chunks.length,
      progress: 0,
    );
    await store.claimTask(taskId, appInstanceId, stage: '准备知识抽取');
    var completedChunks = 0;
    var failedChunks = 0;
    var cachedChunks = 0;
    var createdEntities = 0;
    var matchedEntities = 0;
    var createdRelations = 0;
    var matchedRelations = 0;
    var createdEvents = 0;
    var matchedEvents = 0;
    var qualityWarnings = 0;
    var qualityReviews = 0;
    var disambiguated = 0;
    var pendingReviews = 0;
    for (var index = 0; index < chunks.length; index++) {
      final currentTask = await store.getTask(taskId);
      if (currentTask == null ||
          currentTask.status == 'cancelled' ||
          currentTask.status == 'paused') {
        return;
      }
      final chunk = chunks[index];
      try {
        final cachedJson = await store.knowledgeChunkCache(
          chapterId: chapterId,
          chunkIndex: chunk.index,
          contentHash: chunk.contentHash,
          modelLabel: resolved.label,
          promptVersion: promptVersion,
          schemaVersion: schemaVersion,
        );
        Map<String, dynamic> data;
        if (cachedJson != null) {
          data = jsonDecode(cachedJson) as Map<String, dynamic>;
          cachedChunks += 1;
        } else {
          final items = [
            for (var i = 0; i < chunk.sentences.length; i++)
              {'i': i + 1, 't': chunk.sentences[i].originalText},
          ];
          final prompt = await aiSettings.render('knowledge_extract', {
            'book_title': content.bookTitle,
            'chapter_title': content.chapterTitle,
            'items_json': jsonEncode(items),
          });
          data = await client.chatJson(
            purpose: 'extraction',
            prompt: prompt,
            temperature: 0.1,
            taskId: taskId,
            taskType: 'knowledge_extraction',
            promptVersion: promptVersion,
            schemaVersion: schemaVersion,
            shouldCancel: () async {
              final current = await store.getTask(taskId);
              return current == null ||
                  current.status == 'cancelled' ||
                  current.status == 'paused';
            },
          );
          await store.putKnowledgeChunkCache(
            chapterId: chapterId,
            chunkIndex: chunk.index,
            contentHash: chunk.contentHash,
            modelLabel: resolved.label,
            promptVersion: promptVersion,
            schemaVersion: schemaVersion,
            resultJson: jsonEncode(data),
          );
        }
        final report = quality.checkKnowledge(data);
        await store.recordQualityReport(
          taskId: taskId,
          scope: 'knowledge_chunk',
          reference: 'chunk:${chunk.index}',
          status: report.level.wireValue,
          issues: report.issues.map((issue) => issue.toJson()).toList(),
        );
        if (report.level == QualityLevel.failed ||
            report.level == QualityLevel.needsReview) {
          qualityReviews += 1;
        } else if (report.level == QualityLevel.warning) {
          qualityWarnings += 1;
        }
        final decisions = await _resolveEntityDecisions(
          chunk: chunk,
          data: data,
          resolved: resolved,
          taskId: taskId,
        );
        disambiguated += decisions.values
            .where((decision) => decision.record)
            .length;
        pendingReviews += decisions.values
            .where(
              (decision) =>
                  decision.status == 'pending_review' ||
                  decision.status == 'unresolved',
            )
            .length;
        final stats = await _applyChunk(
          content,
          chunk,
          data,
          _ExtractionContext(
            taskId: taskId,
            providerId: resolved.provider.id,
            modelId: resolved.model.id,
            promptVersion: promptVersion,
            schemaVersion: schemaVersion,
            chunkIndex: chunk.index,
          ),
          decisions: decisions,
        );
        createdEntities += stats.createdEntities;
        matchedEntities += stats.matchedEntities;
        createdRelations += stats.createdRelations;
        matchedRelations += stats.matchedRelations;
        createdEvents += stats.createdEvents;
        matchedEvents += stats.matchedEvents;
        completedChunks += 1;
      } catch (error) {
        failedChunks += 1;
        await store.updateTask(
          taskId,
          error: '第 ${index + 1}/${chunks.length} 块抽取失败：$error',
        );
      }
      await store.updateTask(
        taskId,
        progress: (completedChunks + failedChunks) / chunks.length * 100,
        completed: completedChunks,
        failedCount: failedChunks,
      );
      await store.touchTask(
        taskId,
        stage: '知识抽取 ${index + 1}/${chunks.length} 块',
        checkpoint: 'chunk:$index',
      );
      final current = await store.getTask(taskId);
      if (current != null) await budgets.adjust(taskId, current.cost);
      if (await _pauseIfBudgetExceeded(taskId)) return;
    }
    final status = failedChunks == 0
        ? 'completed'
        : (completedChunks == 0 ? 'failed' : 'partial');
    await store.putKnowledgeExtractionState(
      chapterId: chapterId,
      contentHash: chapterHash,
      modelLabel: resolved.label,
      promptVersion: promptVersion,
      schemaVersion: schemaVersion,
      status: status == 'completed' ? 'completed' : 'partial',
    );
    await store.updateTask(
      taskId,
      status: status,
      progress: 100,
      completed: completedChunks,
      failedCount: failedChunks,
      result: {
        'entities_created': createdEntities,
        'entities_matched': matchedEntities,
        'relations_created': createdRelations,
        'relations_matched': matchedRelations,
        'events_created': createdEvents,
        'events_matched': matchedEvents,
        'cached_chunks': cachedChunks,
        'chunks': chunks.length,
        'quality_warnings': qualityWarnings,
        'quality_reviews': qualityReviews,
        'disambiguated': disambiguated,
        'pending_review': pendingReviews,
        'model': resolved.label,
      },
    );
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

  Future<Map<int, _EntityDecision>> _resolveEntityDecisions({
    required _KnowledgeChunk chunk,
    required Map<String, dynamic> data,
    required ResolvedAiModel resolved,
    required String taskId,
  }) async {
    final decisions = <int, _EntityDecision>{};
    final routing = await aiSettings.knowledgeRoutingConfig();
    final sentenceByIndex = <int, Sentence>{
      for (var i = 0; i < chunk.sentences.length; i++)
        i + 1: chunk.sentences[i],
    };
    for (final item in jsonList(data['entities'])) {
      final localId = jsonInt(item['id']);
      final name = jsonString(item['name']);
      if (localId == null || name == null || name.trim().isEmpty) continue;
      final kind = _normalizeEntityKind(jsonString(item['type']) ?? 'other');
      final dynasty = jsonString(item['dynasty']);
      final aliases = _jsonStringList(item['aliases']);
      final candidates = await _entityCandidates(
        name: name,
        aliases: aliases,
        kind: kind,
      );
      if (candidates.isEmpty) continue;
      final top = candidates.first;
      if (top.score >= 0.9) {
        final ambiguous = candidates.length > 1 && candidates[1].score >= 0.88;
        if (!ambiguous) {
          decisions[localId] = _EntityDecision(
            entityId: top.id,
            isNew: false,
            status: 'auto_matched',
            confidence: top.score,
            reason: '本地名称/别名匹配',
            candidates: candidates,
            name: name,
            kind: kind,
            dynasty: dynasty,
            record: false,
          );
          continue;
        }
      }
      final quoteSentences = _evidenceSentences(
        item['evidence'],
        sentenceByIndex,
      );
      final quote = quoteSentences.isEmpty
          ? null
          : quoteSentences.first.originalText;
      final promptVersion = await aiSettings.activePromptVersion(
        'entity_disambiguation',
      );
      final schemaVersion = await store.activeSchemaVersion(
        'entity_disambiguation',
      );
      final candidateKey = candidates.map((item) => item.id).join(',');
      final cacheKey = sha256
          .convert(
            utf8.encode(
              '${name.trim()}|$kind|${dynasty ?? ''}|$candidateKey|'
              '${resolved.label}|v$promptVersion|s$schemaVersion',
            ),
          )
          .toString();
      Map<String, dynamic>? result;
      final cached = await store.entityDisambiguationCache(cacheKey);
      if (cached != null) {
        try {
          result = jsonDecode(cached) as Map<String, dynamic>;
        } catch (_) {
          result = null;
        }
      }
      if (result == null) {
        try {
          final candidatesJson = [
            for (var i = 0; i < candidates.length; i++)
              {
                'id': i + 1,
                'name': candidates[i].name,
                'kind': candidates[i].kind,
                'dynasty': candidates[i].dynasty,
                'status': candidates[i].status,
              },
          ];
          final prompt = await aiSettings.render('entity_disambiguation', {
            'name': name,
            'kind': kind,
            'dynasty': dynasty ?? '未知',
            'quote': _truncateText(quote ?? '', 300),
            'candidates_json': jsonEncode(candidatesJson),
          });
          await store.recordRoutingDecision(
            taskId: taskId,
            taskType: 'entity_disambiguation',
            requestedModelId: resolved.model.id,
            routedModelId: routing.disambiguationModelId ?? resolved.model.id,
            providerId: resolved.provider.id,
            mode: routing.mode,
            reason: '多候选实体冲突',
            specialized: routing.disambiguationModelId != null,
            triggerReason: '本地匹配出现多个高分候选',
          );
          result = await client.chatJson(
            purpose: 'extraction',
            prompt: prompt,
            temperature: 0,
            taskId: taskId,
            taskType: 'entity_disambiguation',
            promptVersion: promptVersion,
            schemaVersion: schemaVersion,
            modelId: routing.disambiguationModelId,
            shouldCancel: () async {
              final current = await store.getTask(taskId);
              return current == null ||
                  current.status == 'cancelled' ||
                  current.status == 'paused';
            },
          );
          await store.putEntityDisambiguationCache(
            cacheKey: cacheKey,
            resultJson: jsonEncode(result),
          );
        } catch (_) {
          // Disambiguation failure must not lose the extracted entity.
          result = null;
        }
      }
      final chosenIndex = jsonInt(result?['entity']);
      final confidence =
          (result?['confidence'] is num
                  ? (result!['confidence'] as num).toDouble()
                  : 0.0)
              .clamp(0.0, 1.0);
      final reason = jsonString(result?['reason']);
      final chosen =
          chosenIndex != null &&
              chosenIndex >= 1 &&
              chosenIndex <= candidates.length
          ? candidates[chosenIndex - 1]
          : null;
      if (chosen != null && confidence >= 0.8) {
        decisions[localId] = _EntityDecision(
          entityId: chosen.id,
          isNew: false,
          status: 'auto_matched',
          confidence: confidence,
          reason: reason,
          candidates: candidates,
          name: name,
          kind: kind,
          dynasty: dynasty,
          record: true,
        );
      } else {
        decisions[localId] = _EntityDecision(
          entityId: newLocalId('ent'),
          isNew: true,
          status: chosen != null ? 'pending_review' : 'unresolved',
          confidence: confidence,
          reason: reason ?? '无法可靠匹配候选',
          candidates: candidates,
          name: name,
          kind: kind,
          dynasty: dynasty,
          record: true,
        );
      }
    }
    return decisions;
  }

  Future<List<_EntityCandidate>> _entityCandidates({
    required String name,
    required List<String> aliases,
    required String kind,
  }) async {
    final normalizedName = _normalizeEntityName(name);
    final rows = await store.db.query(
      'entities',
      where:
          "canonical_name = ? OR canonical_name LIKE ? OR aliases LIKE ? "
          "OR (? <> '' AND aliases LIKE ?)",
      whereArgs: [
        name,
        '%$normalizedName%',
        '%$name%',
        aliases.isEmpty ? '' : aliases.first,
        aliases.isEmpty ? '' : '%${aliases.first}%',
      ],
      limit: 40,
    );
    final candidates = <_EntityCandidate>[];
    for (final row in rows) {
      final canonical = row['canonical_name'] as String? ?? '';
      final values = _decodeStringList(row['aliases']);
      final rowKind = row['kind'] as String? ?? 'other';
      var score = 0.0;
      if (canonical == name) {
        score = 1.0;
      } else if (values.contains(name)) {
        score = 0.96;
      } else if (_normalizeEntityName(canonical) == normalizedName) {
        score = 0.92;
      } else if (aliases.any(values.contains)) {
        score = 0.9;
      } else if (rowKind == kind &&
          normalizedName.length >= 2 &&
          (_normalizeEntityName(canonical).contains(normalizedName) ||
              normalizedName.contains(_normalizeEntityName(canonical)))) {
        score = 0.6;
      } else if (rowKind == kind &&
          aliases.any(
            (alias) =>
                alias.length >= 2 &&
                _normalizeEntityName(canonical)
                    .contains(_normalizeEntityName(alias)),
          )) {
        score = 0.55;
      }
      if (score <= 0) continue;
      candidates.add(
        _EntityCandidate(
          id: row['id'] as String,
          name: canonical,
          kind: rowKind,
          dynasty: row['dynasty'] as String?,
          status: row['status'] as String? ?? 'pending',
          score: score,
        ),
      );
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(5).toList();
  }

  String _normalizeEntityName(String value) =>
      value.replaceAll(RegExp(r'[\s·・（）()\[\]【】]'), '').trim();

  String _truncateText(String value, int maxLength) =>
      value.length <= maxLength ? value : value.substring(0, maxLength);

  List<_KnowledgeChunk> _buildChunks(
    ChapterContent content,
    AiModelRecord model,
  ) {
    final budget = _chunkTokenBudget(model);
    final tokenizer = TokenizerRegistry.forModel(model);
    final chunks = <_KnowledgeChunk>[];
    var current = <Sentence>[];
    var tokens = 0;

    void flush() {
      if (current.isEmpty) return;
      chunks.add(
        _KnowledgeChunk(
          index: chunks.length,
          sentences: current,
          contentHash: _chunkHash(current),
        ),
      );
      current = <Sentence>[];
      tokens = 0;
    }

    for (final paragraph in content.paragraphs) {
      final paragraphTokens = paragraph.sentences.fold<int>(
        0,
        (sum, sentence) =>
            sum + tokenizer.count(sentence.originalText).tokens + 8,
      );
      if (current.isNotEmpty && tokens + paragraphTokens > budget) {
        flush();
      }
      if (paragraphTokens > budget) {
        for (final sentence in paragraph.sentences) {
          final sentenceTokens =
              tokenizer.count(sentence.originalText).tokens + 8;
          if (current.isNotEmpty && tokens + sentenceTokens > budget) {
            flush();
          }
          current.add(sentence);
          tokens += sentenceTokens;
        }
      } else {
        current.addAll(paragraph.sentences);
        tokens += paragraphTokens;
      }
    }
    flush();
    return chunks;
  }

  int _chunkTokenBudget(AiModelRecord model) {
    final inputBound = math.max(
      900,
      model.contextWindow - model.maxOutputTokens - 1200,
    );
    final outputBound = math.max(900, model.maxOutputTokens * 2);
    return math.max(900, math.min(5000, math.min(inputBound, outputBound)));
  }

  String _chapterHash(ChapterContent content) {
    final buffer = StringBuffer();
    for (final paragraph in content.paragraphs) {
      for (final sentence in paragraph.sentences) {
        buffer
          ..write(sentence.id)
          ..write('\u0001')
          ..write(sentence.originalText)
          ..write('\u0002');
      }
    }
    return sha256.convert(utf8.encode(buffer.toString())).toString();
  }

  String _chunkHash(List<Sentence> sentences) {
    final buffer = StringBuffer();
    for (final sentence in sentences) {
      buffer
        ..write(sentence.id)
        ..write('\u0001')
        ..write(sentence.originalText)
        ..write('\u0002');
    }
    return sha256.convert(utf8.encode(buffer.toString())).toString();
  }

  Future<_ChunkApplyStats> _applyChunk(
    ChapterContent content,
    _KnowledgeChunk chunk,
    Map<String, dynamic> data,
    _ExtractionContext context, {
    Map<int, _EntityDecision> decisions = const {},
  }) async {
    final sentenceByIndex = <int, Sentence>{
      for (var i = 0; i < chunk.sentences.length; i++)
        i + 1: chunk.sentences[i],
    };
    return store.db.transaction<_ChunkApplyStats>((txn) async {
      var createdEntities = 0;
      var matchedEntities = 0;
      var createdRelations = 0;
      var matchedRelations = 0;
      var createdEvents = 0;
      var matchedEvents = 0;
      final entityIds = <int, String>{};
      final entityNames = <String, String>{};

      for (final item in jsonList(data['entities'])) {
        final localId = jsonInt(item['id']);
        final name = jsonString(item['name']);
        if (localId == null || name == null || name.isEmpty) continue;
        final aliases = _jsonStringList(item['aliases']);
        final kind = _normalizeEntityKind(jsonString(item['type']) ?? 'other');
        final dynasty = jsonString(item['dynasty']);
        final entityEvidence = _evidenceSentences(
          item['evidence'],
          sentenceByIndex,
        );
        final now = nowIso();
        final decision = decisions[localId];
        String entityId;
        if (decision != null) {
          entityId = decision.entityId;
          if (decision.isNew) {
            await txn.insert('entities', {
              'id': entityId,
              'canonical_name': name,
              'kind': kind,
              'aliases': jsonEncode(aliases),
              'dynasty': dynasty,
              'status': 'pending',
              'knowledge_type': entityEvidence.isEmpty
                  ? 'inferred'
                  : 'explicit',
              'created_at': now,
              'updated_at': now,
            });
            createdEntities += 1;
          } else {
            matchedEntities += 1;
            final existing = await txn.query(
              'entities',
              where: 'id = ?',
              whereArgs: [entityId],
              limit: 1,
            );
            if (existing.isNotEmpty) {
              final mergedAliases = {
                ..._decodeStringList(existing.first['aliases']),
                ...aliases,
              }..remove(name);
              final updates = <String, Object?>{'updated_at': now};
              if (mergedAliases.isNotEmpty) {
                updates['aliases'] = jsonEncode(mergedAliases.toList());
              }
              if ((existing.first['dynasty'] as String?) == null &&
                  dynasty != null) {
                updates['dynasty'] = dynasty;
              }
              await txn.update(
                'entities',
                updates,
                where: 'id = ?',
                whereArgs: [entityId],
              );
            }
          }
          await txn.insert('entity_disambiguations', {
            'id': newLocalId('disamb'),
            'task_id': context.taskId,
            'extracted_name': name,
            'kind': kind,
            'dynasty': dynasty,
            'candidate_ids': jsonEncode(
              decision.candidates.map((candidate) => candidate.id).toList(),
            ),
            'chosen_entity_id': decision.isNew ? null : entityId,
            'status': decision.status,
            'confidence': decision.confidence,
            'reason': decision.reason,
            'model_id': context.modelId,
            'created_at': now,
          });
        } else {
          final existing = await _findEntityRecord(txn, name, aliases);
          if (existing == null) {
            entityId = newLocalId('ent');
            await txn.insert('entities', {
              'id': entityId,
              'canonical_name': name,
              'kind': kind,
              'aliases': jsonEncode(aliases),
              'dynasty': dynasty,
              'status': 'pending',
              'knowledge_type': entityEvidence.isEmpty
                  ? 'inferred'
                  : 'explicit',
              'created_at': now,
              'updated_at': now,
            });
            createdEntities += 1;
          } else {
            entityId = existing['id'] as String;
            matchedEntities += 1;
            final mergedAliases = {
              ..._decodeStringList(existing['aliases']),
              ...aliases,
            }..remove(name);
            final updates = <String, Object?>{'updated_at': now};
            if (mergedAliases.isNotEmpty) {
              updates['aliases'] = jsonEncode(mergedAliases.toList());
            }
            if ((existing['dynasty'] as String?) == null && dynasty != null) {
              updates['dynasty'] = dynasty;
            }
            final knowledgeType = existing['knowledge_type'] as String?;
            if (knowledgeType != 'human_verified' &&
                entityEvidence.isNotEmpty &&
                knowledgeType != 'explicit') {
              updates['knowledge_type'] = 'explicit';
            }
            await txn.update(
              'entities',
              updates,
              where: 'id = ?',
              whereArgs: [entityId],
            );
          }
        }
        entityIds[localId] = entityId;
        entityNames[entityId] = name;
        for (final sentence in entityEvidence) {
          await _insertMentionIfMissing(
            txn,
            entityId: entityId,
            content: content,
            sentence: sentence,
            quote: sentence.originalText,
            context: context,
          );
        }
      }

      for (final item in jsonList(data['relations'])) {
        final from = _entityRef(item['from'], entityIds);
        final to = _entityRef(item['to'], entityIds);
        final type = jsonString(item['type']) ?? '其他';
        if (from == null || to == null || from == to) continue;
        final evidence = _evidenceSentences(item['evidence'], sentenceByIndex);
        if (evidence.isEmpty) continue;
        final existing = await txn.query(
          'entity_relations',
          where:
              'from_entity_id = ? AND to_entity_id = ? AND relation_type = ?',
          whereArgs: [from, to, type],
          limit: 1,
        );
        final now = nowIso();
        String relationId;
        if (existing.isEmpty) {
          relationId = newLocalId('rel');
          await txn.insert('entity_relations', {
            'id': relationId,
            'from_entity_id': from,
            'to_entity_id': to,
            'relation_type': type,
            'label': type,
            'description': null,
            'status': 'inferred',
            'knowledge_type': 'inferred',
            'confidence': 0.65,
            'created_at': now,
            'updated_at': now,
          });
          createdRelations += 1;
        } else {
          relationId = existing.first['id'] as String;
          matchedRelations += 1;
        }
        for (final sentence in evidence) {
          await _insertRelationSourceIfMissing(
            txn,
            relationId: relationId,
            content: content,
            sentence: sentence,
            quote: sentence.originalText,
            context: context,
          );
        }
        final sourceCount = await txn.rawQuery(
          'SELECT COUNT(DISTINCT book_id) AS n FROM relation_sources '
          'WHERE relation_id = ? AND book_id IS NOT NULL',
          [relationId],
        );
        if ((sourceCount.first['n'] as int? ?? 0) >= 2) {
          await txn.rawUpdate(
            "UPDATE entity_relations SET knowledge_type = 'cross_source_supported' "
            "WHERE id = ? AND knowledge_type <> 'human_verified'",
            [relationId],
          );
        }
      }

      for (final item in jsonList(data['events'])) {
        final name = jsonString(item['name']);
        final evidence = _evidenceSentences(item['evidence'], sentenceByIndex);
        if (name == null || name.isEmpty || evidence.isEmpty) continue;
        final type = jsonString(item['type']) ?? '其他';
        final time = jsonString(item['time']);
        final year = jsonInt(item['year']);
        final precision = jsonString(item['precision']) ?? 'unknown';
        final participantIds = <int>[];
        for (final value in (item['participants'] as List? ?? const [])) {
          final id = value is num ? value.toInt() : int.tryParse('$value');
          if (id != null) participantIds.add(id);
        }
        final participantNames = <String>[];
        final participantEntityIds = <String, String?>{};
        for (final id in participantIds) {
          final entityId = entityIds[id];
          final name = entityId == null ? null : entityNames[entityId];
          if (name == null) continue;
          participantNames.add(name);
          participantEntityIds[name] = entityId;
        }
        final fingerprint = _eventFingerprint(
          name: name,
          type: type,
          time: time,
          year: year,
          participants: participantNames,
          firstQuote: evidence.first.originalText,
        );
        final existing = await _findEventRecord(
          txn,
          fingerprint: fingerprint,
          name: name,
          type: type,
          time: time,
          year: year,
        );
        final now = nowIso();
        String eventId;
        if (existing == null) {
          eventId = newLocalId('event');
          await txn.insert('historical_events', {
            'id': eventId,
            'name': name,
            'event_type': type,
            'description': null,
            'dynasty': null,
            'time_raw': time,
            'time_start_year': year,
            'time_end_year': year,
            'time_precision': precision,
            'time_note': null,
            'status': 'extracted',
            'knowledge_type': 'inferred',
            'fingerprint': fingerprint,
            'created_at': now,
            'updated_at': now,
          });
          createdEvents += 1;
        } else {
          eventId = existing['id'] as String;
          matchedEvents += 1;
          final updates = <String, Object?>{'updated_at': now};
          if (existing['fingerprint'] == null) {
            updates['fingerprint'] = fingerprint;
          }
          if (existing['time_raw'] == null && time != null && time.isNotEmpty) {
            updates['time_raw'] = time;
          }
          if (existing['time_start_year'] == null && year != null) {
            updates['time_start_year'] = year;
            updates['time_end_year'] = year;
          }
          if ((existing['time_precision'] as String? ?? 'unknown') ==
                  'unknown' &&
              precision != 'unknown') {
            updates['time_precision'] = precision;
          }
          await txn.update(
            'historical_events',
            updates,
            where: 'id = ?',
            whereArgs: [eventId],
          );
        }
        for (final name in participantNames) {
          final entityId = participantEntityIds[name];
          final existingParticipant = await txn.query(
            'event_participants',
            where: 'event_id = ? AND name = ?',
            whereArgs: [eventId, name],
            limit: 1,
          );
          if (existingParticipant.isEmpty) {
            await txn.insert('event_participants', {
              'id': newLocalId('ep'),
              'event_id': eventId,
              'entity_id': entityId,
              'name': name,
            });
          } else if (existingParticipant.first['entity_id'] == null &&
              entityId != null) {
            await txn.update(
              'event_participants',
              {'entity_id': entityId},
              where: 'id = ?',
              whereArgs: [existingParticipant.first['id']],
            );
          }
        }
        for (final sentence in evidence) {
          await _insertEventSourceIfMissing(
            txn,
            eventId: eventId,
            content: content,
            sentence: sentence,
            quote: sentence.originalText,
            context: context,
          );
        }
        final sourceCount = await txn.rawQuery(
          'SELECT COUNT(DISTINCT book_id) AS n FROM event_sources '
          'WHERE event_id = ? AND book_id IS NOT NULL',
          [eventId],
        );
        if ((sourceCount.first['n'] as int? ?? 0) >= 2) {
          await txn.rawUpdate(
            "UPDATE historical_events SET knowledge_type = 'cross_source_supported' "
            "WHERE id = ? AND knowledge_type <> 'human_verified'",
            [eventId],
          );
        }
      }

      return _ChunkApplyStats(
        createdEntities: createdEntities,
        matchedEntities: matchedEntities,
        createdRelations: createdRelations,
        matchedRelations: matchedRelations,
        createdEvents: createdEvents,
        matchedEvents: matchedEvents,
      );
    });
  }

  Future<Map<String, Object?>?> _findEntityRecord(
    DatabaseExecutor txn,
    String name,
    List<String> aliases,
  ) async {
    final exact = await txn.query(
      'entities',
      where: 'canonical_name = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (exact.isNotEmpty) return exact.first;
    final candidates = await txn.query(
      'entities',
      where: 'aliases LIKE ?',
      whereArgs: ['%$name%'],
      limit: 20,
    );
    for (final row in candidates) {
      final values = _decodeStringList(row['aliases']);
      if (values.contains(name)) return row;
    }
    for (final alias in aliases) {
      if (alias == name) continue;
      final aliasExact = await txn.query(
        'entities',
        where: 'aliases LIKE ?',
        whereArgs: ['%$alias%'],
        limit: 1,
      );
      if (aliasExact.isNotEmpty) return aliasExact.first;
    }
    return null;
  }

  List<Sentence> _evidenceSentences(
    Object? value,
    Map<int, Sentence> sentenceByIndex,
  ) {
    if (value is! List) return const [];
    final seen = <int>{};
    final result = <Sentence>[];
    for (final raw in value) {
      final index = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (index == null || !seen.add(index)) continue;
      final sentence = sentenceByIndex[index];
      if (sentence != null) result.add(sentence);
    }
    return result;
  }

  String? _entityRef(Object? value, Map<int, String> entityIds) {
    final id = value is num ? value.toInt() : int.tryParse('$value');
    return id == null ? null : entityIds[id];
  }

  Future<void> _insertMentionIfMissing(
    DatabaseExecutor txn, {
    required String entityId,
    required ChapterContent content,
    required Sentence sentence,
    required String quote,
    required _ExtractionContext context,
  }) async {
    final existing = await txn.query(
      'entity_mentions',
      where: 'entity_id = ? AND book_id = ? AND chapter_id = ? AND quote = ?',
      whereArgs: [entityId, content.bookId, content.chapterId, quote],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    await txn.insert('entity_mentions', {
      'id': newLocalId('mention'),
      'entity_id': entityId,
      'book_id': content.bookId,
      'chapter_id': content.chapterId,
      'sentence_id': sentence.id,
      'quote': quote,
      'status': 'pending',
      'chunk_index': context.chunkIndex,
      'task_id': context.taskId,
      'provider_id': context.providerId,
      'model_id': context.modelId,
      'prompt_version': context.promptVersion,
      'schema_version': context.schemaVersion,
      'extracted_at': nowIso(),
      'created_at': nowIso(),
    });
  }

  Future<void> _insertRelationSourceIfMissing(
    DatabaseExecutor txn, {
    required String relationId,
    required ChapterContent content,
    required Sentence sentence,
    required String quote,
    required _ExtractionContext context,
  }) async {
    final existing = await txn.query(
      'relation_sources',
      where:
          'relation_id = ? AND COALESCE(sentence_id, \'\') = ? AND quote = ?',
      whereArgs: [relationId, sentence.id, quote],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    await txn.insert('relation_sources', {
      'id': newLocalId('relsrc'),
      'relation_id': relationId,
      'sentence_id': sentence.id,
      'book_id': content.bookId,
      'chapter_id': content.chapterId,
      'quote': quote,
      'chunk_index': context.chunkIndex,
      'task_id': context.taskId,
      'provider_id': context.providerId,
      'model_id': context.modelId,
      'prompt_version': context.promptVersion,
      'schema_version': context.schemaVersion,
      'extracted_at': nowIso(),
    });
  }

  Future<void> _insertEventSourceIfMissing(
    DatabaseExecutor txn, {
    required String eventId,
    required ChapterContent content,
    required Sentence sentence,
    required String quote,
    required _ExtractionContext context,
  }) async {
    final existing = await txn.query(
      'event_sources',
      where: 'event_id = ? AND COALESCE(sentence_id, \'\') = ? AND quote = ?',
      whereArgs: [eventId, sentence.id, quote],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    await txn.insert('event_sources', {
      'id': newLocalId('esrc'),
      'event_id': eventId,
      'sentence_id': sentence.id,
      'book_id': content.bookId,
      'chapter_id': content.chapterId,
      'quote': quote,
      'chunk_index': context.chunkIndex,
      'task_id': context.taskId,
      'provider_id': context.providerId,
      'model_id': context.modelId,
      'prompt_version': context.promptVersion,
      'schema_version': context.schemaVersion,
      'extracted_at': nowIso(),
    });
  }

  Future<Map<String, Object?>?> _findEventRecord(
    DatabaseExecutor txn, {
    required String fingerprint,
    required String name,
    required String type,
    required String? time,
    required int? year,
  }) async {
    final direct = await txn.query(
      'historical_events',
      where: 'fingerprint = ?',
      whereArgs: [fingerprint],
      limit: 1,
    );
    if (direct.isNotEmpty) return direct.first;
    if (year == null && (time == null || time.isEmpty)) return null;
    final fallback = await txn.query(
      'historical_events',
      where: 'name = ? AND event_type = ? AND COALESCE(time_start_year, -999999) = ? AND COALESCE(time_raw, \'\') = ?',
      whereArgs: [name, type, year ?? -999999, time ?? ''],
      limit: 1,
    );
    return fallback.isEmpty ? null : fallback.first;
  }

  String _eventFingerprint({
    required String name,
    required String type,
    required String? time,
    required int? year,
    required List<String> participants,
    required String firstQuote,
  }) {
    final normalizedParticipants = [...participants]..sort();
    final normalizedName = name.replaceAll(RegExp(r'\s+'), '').trim();
    final base = StringBuffer()
      ..write(normalizedName)
      ..write('|')
      ..write(type)
      ..write('|')
      ..write(year ?? '')
      ..write('|')
      ..write((time ?? '').replaceAll(RegExp(r'\s+'), ''))
      ..write('|')
      ..write(normalizedParticipants.join(','));
    if (year == null &&
        (time == null || time.isEmpty) &&
        participants.isEmpty) {
      base
        ..write('|')
        ..write(sha256.convert(utf8.encode(firstQuote)).toString());
    }
    return sha256.convert(utf8.encode(base.toString())).toString();
  }

  String _normalizeEntityKind(String kind) {
    const allowed = {
      'person',
      'place',
      'office',
      'institution',
      'dynasty',
      'work',
      'other',
    };
    final value = kind.trim().toLowerCase();
    return allowed.contains(value) ? value : 'other';
  }

  List<String> _jsonStringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  Future<List<HistoricalEntity>> listEntities({
    String? query,
    String? kind,
    String? status,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];
    if (query != null && query.trim().isNotEmpty) {
      conditions.add('(canonical_name LIKE ? OR aliases LIKE ?)');
      args.addAll(['%${query.trim()}%', '%${query.trim()}%']);
    }
    if (kind != null && kind.isNotEmpty) {
      conditions.add('kind = ?');
      args.add(kind);
    }
    if (status != null && status.isNotEmpty) {
      conditions.add('status = ?');
      args.add(status);
    }
    final rows = await store.db.query(
      'entities',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'updated_at DESC',
      limit: 300,
    );
    return [
      for (final row in rows)
        HistoricalEntity(
          id: row['id'] as String,
          name: row['canonical_name'] as String,
          kind: row['kind'] as String? ?? 'person',
          dynasty: row['dynasty'] as String?,
          identity: row['identity'] as String?,
          summary: row['summary'] as String?,
          aliases: _decodeStringList(row['aliases']),
          status: row['status'] as String? ?? 'pending',
          knowledgeType: row['knowledge_type'] as String? ?? 'explicit',
        ),
    ];
  }

  Future<HistoricalEntity?> entity(String id) async {
    final rows = await store.db.query(
      'entities',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final mentionRows = await store.db.rawQuery(
      '''
      SELECT m.*, b.title AS book_title, c.title AS chapter_title
      FROM entity_mentions m LEFT JOIN books b ON b.id = m.book_id
      LEFT JOIN chapters c ON c.id = m.chapter_id
      WHERE m.entity_id = ? ORDER BY m.created_at DESC LIMIT 200
      ''',
      [id],
    );
    final relationRows = await store.db.rawQuery(
      '''
      SELECT r.*, e.canonical_name AS other_entity_name, e.id AS other_entity_id
      FROM entity_relations r JOIN entities e
        ON e.id = CASE WHEN r.from_entity_id = ? THEN r.to_entity_id ELSE r.from_entity_id END
      WHERE r.from_entity_id = ? OR r.to_entity_id = ?
      ORDER BY r.created_at DESC
      ''',
      [id, id, id],
    );
    final relations = <EntityRelation>[];
    for (final relation in relationRows) {
      final sources = await store.db.rawQuery(
        '''
        SELECT s.*, b.title AS book_title, c.title AS chapter_title
        FROM relation_sources s
        LEFT JOIN books b ON b.id = s.book_id
        LEFT JOIN chapters c ON c.id = s.chapter_id
        WHERE s.relation_id = ?
        ORDER BY s.created_at ASC, s.id ASC
        ''',
        [relation['id']],
      );
      relations.add(
        EntityRelation(
          id: relation['id'] as String,
          relationType: relation['relation_type'] as String? ?? '其他',
          otherName: relation['other_entity_name'] as String?,
          otherId: relation['other_entity_id'] as String?,
          description: relation['description'] as String?,
          status: relation['status'] as String? ?? 'inferred',
          knowledgeType: relation['knowledge_type'] as String? ?? 'inferred',
          confidence: (relation['confidence'] as num? ?? 0.5).toDouble(),
          validFromRaw: relation['valid_from_raw'] as String?,
          validFromYear: relation['valid_from_year'] as int?,
          validToRaw: relation['valid_to_raw'] as String?,
          validToYear: relation['valid_to_year'] as int?,
          timePrecision: relation['time_precision'] as String? ?? 'unknown',
          sourceKind: relation['source_kind'] as String? ?? 'ai',
          sources: [
            for (final source in sources)
              RelationSource(
                id: source['id'] as String?,
                quote: source['quote'] as String?,
                bookId: source['book_id'] as String?,
                chapterId: source['chapter_id'] as String?,
                sentenceId: source['sentence_id'] as String?,
                paragraphId: source['paragraph_id'] as String?,
                bookTitle: source['book_title'] as String?,
                chapterTitle: source['chapter_title'] as String?,
                evidenceType:
                    source['evidence_type'] as String? ?? 'supporting',
                sourceKind: source['source_kind'] as String? ?? 'ai',
                note: source['note'] as String?,
                reviewStatus: source['review_status'] as String? ?? 'pending',
                createdAt: source['created_at'] as String?,
              ),
          ],
        ),
      );
    }
    return HistoricalEntity(
      id: id,
      name: row['canonical_name'] as String,
      kind: row['kind'] as String? ?? 'person',
      dynasty: row['dynasty'] as String?,
      identity: row['identity'] as String?,
      summary: row['summary'] as String?,
      aliases: _decodeStringList(row['aliases']),
      status: row['status'] as String? ?? 'pending',
      knowledgeType: row['knowledge_type'] as String? ?? 'explicit',
      mentions: [
        for (final mention in mentionRows)
          EntityMention(
            id: mention['id'] as String,
            quote: mention['quote'] as String? ?? '',
            sentenceId: mention['sentence_id'] as String?,
            bookId: mention['book_id'] as String?,
            bookTitle: mention['book_title'] as String?,
            chapterId: mention['chapter_id'] as String?,
            chapterTitle: mention['chapter_title'] as String?,
          ),
      ],
      relations: relations,
    );
  }

  Future<void> setEntityStatus(String id, String status) => _setReviewStatus(
    table: 'entities',
    targetType: 'entity',
    id: id,
    status: status,
    knowledgeType: status == 'confirmed'
        ? 'human_verified'
        : status == 'rejected'
        ? 'disputed'
        : null,
  );

  Future<void> setRelationStatus(String id, String status) => _setReviewStatus(
    table: 'entity_relations',
    targetType: 'relation',
    id: id,
    status: status,
    knowledgeType: status == 'confirmed'
        ? 'human_verified'
        : status == 'rejected'
        ? 'disputed'
        : null,
  );

  Future<void> setEventStatus(String id, String status) => _setReviewStatus(
    table: 'historical_events',
    targetType: 'event',
    id: id,
    status: status,
    knowledgeType: status == 'confirmed'
        ? 'human_verified'
        : status == 'rejected'
        ? 'disputed'
        : null,
  );

  Future<void> _setReviewStatus({
    required String table,
    required String targetType,
    required String id,
    required String status,
    String? knowledgeType,
  }) async {
    await store.db.transaction((txn) async {
      final before = await txn.query(
        table,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final updates = <String, Object?>{
        'status': status,
        'updated_at': nowIso(),
        if (knowledgeType != null) 'knowledge_type': knowledgeType,
      };
      await txn.update(table, updates, where: 'id = ?', whereArgs: [id]);
      await _audit(
        txn,
        targetType: targetType,
        targetId: id,
        action: 'status_$status',
        before: before.isEmpty ? null : before.first,
        after: updates,
      );
    });
  }

  Future<void> updateEntity(
    String id, {
    String? name,
    String? kind,
    List<String>? aliases,
    String? dynasty,
    String? status,
  }) async {
    final updates = <String, Object?>{
      if (name != null && name.trim().isNotEmpty) 'canonical_name': name.trim(),
      if (kind != null) 'kind': _normalizeEntityKind(kind),
      if (aliases != null) 'aliases': jsonEncode(aliases),
      if (dynasty != null) 'dynasty': dynasty,
      if (status != null) 'status': status,
      'updated_at': nowIso(),
    };
    await store.db.transaction((txn) async {
      final before = await txn.query(
        'entities',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      await txn.update('entities', updates, where: 'id = ?', whereArgs: [id]);
      await _audit(
        txn,
        targetType: 'entity',
        targetId: id,
        action: 'update',
        before: before.isEmpty ? null : before.first,
        after: updates,
      );
    });
  }

  Future<void> updateRelation(
    String id, {
    String? type,
    String? description,
    String? status,
    String? validFromRaw,
    int? validFromYear,
    String? validToRaw,
    int? validToYear,
    String? timePrecision,
    double? confidence,
  }) async {
    final updates = <String, Object?>{
      if (type != null && type.trim().isNotEmpty) 'relation_type': type.trim(),
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (validFromRaw != null) 'valid_from_raw': validFromRaw,
      if (validFromYear != null) 'valid_from_year': validFromYear,
      if (validToRaw != null) 'valid_to_raw': validToRaw,
      if (validToYear != null) 'valid_to_year': validToYear,
      if (timePrecision != null) 'time_precision': timePrecision,
      if (confidence != null) 'confidence': confidence.clamp(0.0, 1.0),
      'source_kind': 'manual',
      'updated_by': 'human',
      'updated_at': nowIso(),
    };
    await store.db.transaction((txn) async {
      final before = await txn.query(
        'entity_relations',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      await txn.update(
        'entity_relations',
        updates,
        where: 'id = ?',
        whereArgs: [id],
      );
      await _audit(
        txn,
        targetType: 'relation',
        targetId: id,
        action: 'update',
        before: before.isEmpty ? null : before.first,
        after: updates,
      );
    });
  }

  Future<String> createRelation({
    required String fromEntityId,
    required String toEntityId,
    required String type,
    String? description,
    String? validFromRaw,
    int? validFromYear,
    String? validToRaw,
    int? validToYear,
    String timePrecision = 'unknown',
    double confidence = 1.0,
    String status = 'pending',
  }) async {
    final id = newLocalId('rel');
    final now = nowIso();
    await store.db.transaction((txn) async {
      await txn.insert('entity_relations', {
        'id': id,
        'from_entity_id': fromEntityId,
        'to_entity_id': toEntityId,
        'relation_type': type,
        'label': type,
        'description': description,
        'status': status,
        'knowledge_type': 'human_verified',
        'confidence': confidence.clamp(0.0, 1.0),
        'valid_from_raw': validFromRaw,
        'valid_from_year': validFromYear,
        'valid_to_raw': validToRaw,
        'valid_to_year': validToYear,
        'time_precision': timePrecision,
        'source_kind': 'manual',
        'updated_by': 'human',
        'created_at': now,
        'updated_at': now,
      });
      await _audit(
        txn,
        targetType: 'relation',
        targetId: id,
        action: 'create',
        after: {
          'from_entity_id': fromEntityId,
          'to_entity_id': toEntityId,
          'relation_type': type,
        },
      );
    });
    return id;
  }

  Future<void> deleteRelation(String id) async {
    await store.db.transaction((txn) async {
      final before = await txn.query(
        'entity_relations',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (before.isEmpty) return;
      await txn.delete(
        'relation_sources',
        where: 'relation_id = ?',
        whereArgs: [id],
      );
      await txn.delete('entity_relations', where: 'id = ?', whereArgs: [id]);
      await _audit(
        txn,
        targetType: 'relation',
        targetId: id,
        action: 'delete',
        before: before.first,
      );
    });
  }

  Future<String> addRelationEvidence(
    String relationId, {
    String? sentenceId,
    String? bookId,
    String? chapterId,
    String? paragraphId,
    required String quote,
    String evidenceType = 'supporting',
    String? note,
    String sourceKind = 'manual',
    String reviewStatus = 'pending',
  }) async {
    final id = newLocalId('relsrc');
    final now = nowIso();
    await store.db.transaction((txn) async {
      await txn.insert('relation_sources', {
        'id': id,
        'relation_id': relationId,
        'sentence_id': sentenceId,
        'book_id': bookId,
        'chapter_id': chapterId,
        'paragraph_id': paragraphId,
        'quote': quote,
        'evidence_type': evidenceType,
        'source_kind': sourceKind,
        'note': note,
        'review_status': reviewStatus,
        'created_at': now,
        'extracted_at': now,
      });
      await _audit(
        txn,
        targetType: 'relation_evidence',
        targetId: id,
        action: 'add',
        after: {
          'relation_id': relationId,
          'quote': quote,
          'evidence_type': evidenceType,
        },
      );
    });
    return id;
  }

  Future<void> deleteRelationEvidence(String evidenceId) async {
    await store.db.transaction((txn) async {
      final before = await txn.query(
        'relation_sources',
        where: 'id = ?',
        whereArgs: [evidenceId],
        limit: 1,
      );
      if (before.isEmpty) return;
      await txn.delete(
        'relation_sources',
        where: 'id = ?',
        whereArgs: [evidenceId],
      );
      await _audit(
        txn,
        targetType: 'relation_evidence',
        targetId: evidenceId,
        action: 'delete',
        before: before.first,
      );
    });
  }

  Future<void> updateEvent(
    String id, {
    String? name,
    String? type,
    String? description,
    String? timeRaw,
    int? year,
    String? timeEndRaw,
    int? endYear,
    String? location,
    String? precision,
    String? status,
    bool markTimeReviewed = false,
  }) async {
    final updates = <String, Object?>{
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (type != null && type.trim().isNotEmpty) 'event_type': type.trim(),
      if (description != null) 'description': description,
      if (timeRaw != null) 'time_raw': timeRaw,
      if (year != null) 'time_start_year': year,
      if (timeEndRaw != null) 'time_end_raw': timeEndRaw,
      if (endYear != null) 'time_end_year': endYear,
      if (location != null) 'location': location,
      if (precision != null) 'time_precision': precision,
      if (status != null) 'status': status,
      'source_kind': 'manual',
      'updated_by': 'human',
      'updated_at': nowIso(),
    };
    if (markTimeReviewed) {
      updates['time_precision'] = precision ?? 'estimated';
    }
    await store.db.transaction((txn) async {
      final before = await txn.query(
        'historical_events',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      await txn.update(
        'historical_events',
        updates,
        where: 'id = ?',
        whereArgs: [id],
      );
      await _audit(
        txn,
        targetType: 'event',
        targetId: id,
        action: markTimeReviewed ? 'time_reviewed' : 'update',
        before: before.isEmpty ? null : before.first,
        after: updates,
      );
    });
  }

  Future<String> createEvent({
    required String name,
    String type = '其他',
    String? description,
    String? timeRaw,
    int? year,
    String? timeEndRaw,
    int? endYear,
    String? location,
    String timePrecision = 'unknown',
    String status = 'pending',
  }) async {
    final id = newLocalId('event');
    final now = nowIso();
    await store.db.transaction((txn) async {
      await txn.insert('historical_events', {
        'id': id,
        'name': name,
        'event_type': type,
        'description': description,
        'dynasty': null,
        'time_raw': timeRaw,
        'time_start_year': year,
        'time_end_raw': timeEndRaw,
        'time_end_year': endYear,
        'location': location,
        'time_precision': timePrecision,
        'time_note': null,
        'status': status,
        'knowledge_type': 'human_verified',
        'source_kind': 'manual',
        'updated_by': 'human',
        'created_at': now,
        'updated_at': now,
      });
      await _audit(
        txn,
        targetType: 'event',
        targetId: id,
        action: 'create',
        after: {'name': name, 'event_type': type},
      );
    });
    return id;
  }

  Future<void> deleteEvent(String id) async {
    await store.db.transaction((txn) async {
      final before = await txn.query(
        'historical_events',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (before.isEmpty) return;
      await txn.delete('event_sources', where: 'event_id = ?', whereArgs: [id]);
      await txn.delete(
        'event_participants',
        where: 'event_id = ?',
        whereArgs: [id],
      );
      await txn.delete('historical_events', where: 'id = ?', whereArgs: [id]);
      await _audit(
        txn,
        targetType: 'event',
        targetId: id,
        action: 'delete',
        before: before.first,
      );
    });
  }

  Future<String> addEventEvidence(
    String eventId, {
    String? sentenceId,
    String? bookId,
    String? chapterId,
    String? paragraphId,
    required String quote,
    String evidenceType = 'supporting',
    String? note,
    String sourceKind = 'manual',
    String reviewStatus = 'pending',
  }) async {
    final id = newLocalId('esrc');
    final now = nowIso();
    await store.db.transaction((txn) async {
      await txn.insert('event_sources', {
        'id': id,
        'event_id': eventId,
        'sentence_id': sentenceId,
        'book_id': bookId,
        'chapter_id': chapterId,
        'paragraph_id': paragraphId,
        'quote': quote,
        'evidence_type': evidenceType,
        'source_kind': sourceKind,
        'note': note,
        'review_status': reviewStatus,
        'created_at': now,
        'extracted_at': now,
      });
      await _audit(
        txn,
        targetType: 'event_evidence',
        targetId: id,
        action: 'add',
        after: {
          'event_id': eventId,
          'quote': quote,
          'evidence_type': evidenceType,
        },
      );
    });
    return id;
  }

  Future<void> deleteEventEvidence(String evidenceId) async {
    await store.db.transaction((txn) async {
      final before = await txn.query(
        'event_sources',
        where: 'id = ?',
        whereArgs: [evidenceId],
        limit: 1,
      );
      if (before.isEmpty) return;
      await txn.delete(
        'event_sources',
        where: 'id = ?',
        whereArgs: [evidenceId],
      );
      await _audit(
        txn,
        targetType: 'event_evidence',
        targetId: evidenceId,
        action: 'delete',
        before: before.first,
      );
    });
  }

  Future<void> mergeEvents(String primaryId, List<String> otherIds) async {
    if (otherIds.isEmpty) return;
    await store.db.transaction((txn) async {
      for (final otherId in otherIds) {
        if (otherId == primaryId) continue;
        final other = await txn.query(
          'historical_events',
          where: 'id = ?',
          whereArgs: [otherId],
          limit: 1,
        );
        if (other.isEmpty) continue;
        await txn.update(
          'event_sources',
          {'event_id': primaryId},
          where: 'event_id = ?',
          whereArgs: [otherId],
        );
        await txn.update(
          'event_participants',
          {'event_id': primaryId},
          where: 'event_id = ?',
          whereArgs: [otherId],
        );
        await txn.delete(
          'historical_events',
          where: 'id = ?',
          whereArgs: [otherId],
        );
        await _audit(
          txn,
          targetType: 'event',
          targetId: otherId,
          action: 'merge_into:$primaryId',
          before: other.first,
          after: {'merged_into': primaryId},
        );
      }
      await _dedupeParticipants(txn);
      await _dedupeEventSources(txn);
    });
  }

  Future<void> _dedupeEventSources(DatabaseExecutor txn) async {
    final groups = await txn.rawQuery('''
      SELECT event_id, COALESCE(sentence_id, '') AS sid, quote,
             GROUP_CONCAT(id) AS ids
      FROM event_sources GROUP BY event_id, sid, quote HAVING COUNT(*) > 1
      ''');
    for (final group in groups) {
      final ids = '${group['ids']}'
          .split(',')
          .where((id) => id.isNotEmpty)
          .toList();
      for (final duplicate in ids.skip(1)) {
        await txn.delete(
          'event_sources',
          where: 'id = ?',
          whereArgs: [duplicate],
        );
      }
    }
  }

  Future<List<Map<String, Object?>>> relationEvidence(String relationId) async {
    return store.db.rawQuery(
      '''
      SELECT s.*, b.title AS book_title, c.title AS chapter_title,
             se.original_text AS sentence_text
      FROM relation_sources s
      LEFT JOIN books b ON b.id = s.book_id
      LEFT JOIN chapters c ON c.id = s.chapter_id
      LEFT JOIN sentences se ON se.id = s.sentence_id
      WHERE s.relation_id = ?
      ORDER BY s.created_at ASC, s.id ASC
      ''',
      [relationId],
    );
  }

  Future<List<Map<String, Object?>>> eventEvidence(String eventId) async {
    return store.db.rawQuery(
      '''
      SELECT s.*, b.title AS book_title, c.title AS chapter_title,
             se.original_text AS sentence_text
      FROM event_sources s
      LEFT JOIN books b ON b.id = s.book_id
      LEFT JOIN chapters c ON c.id = s.chapter_id
      LEFT JOIN sentences se ON se.id = s.sentence_id
      WHERE s.event_id = ?
      ORDER BY s.created_at ASC, s.id ASC
      ''',
      [eventId],
    );
  }

  Future<void> _audit(
    DatabaseExecutor db, {
    required String targetType,
    required String targetId,
    required String action,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
    String source = 'human',
    String? taskId,
  }) async {
    await db.insert('knowledge_review_events', {
      'id': newLocalId('review'),
      'target_type': targetType,
      'target_id': targetId,
      'action': action,
      'before_json': before == null ? null : jsonEncode(before),
      'after_json': after == null ? null : jsonEncode(after),
      'source': source,
      'task_id': taskId,
      'created_at': nowIso(),
    });
  }

  Future<List<Map<String, Object?>>> reviewHistory({
    String? targetType,
    String? targetId,
    int limit = 200,
  }) async {
    final rows = await store.db.query(
      'knowledge_review_events',
      where: targetType == null
          ? null
          : targetId == null
          ? 'target_type = ?'
          : 'target_type = ? AND target_id = ?',
      whereArgs: targetType == null
          ? null
          : targetId == null
          ? [targetType]
          : [targetType, targetId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows;
  }

  Future<void> undoReview(String auditId) async {
    final rows = await store.db.query(
      'knowledge_review_events',
      where: 'id = ?',
      whereArgs: [auditId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final row = rows.first;
    final beforeRaw = row['before_json'] as String?;
    if (beforeRaw == null) return;
    final before = jsonDecode(beforeRaw) as Map<String, dynamic>;
    final targetType = row['target_type'] as String;
    final targetId = row['target_id'] as String;
    final table = switch (targetType) {
      'entity' => 'entities',
      'relation' => 'entity_relations',
      'event' => 'historical_events',
      _ => null,
    };
    if (table == null) return;
    const allowed = {
      'canonical_name',
      'kind',
      'aliases',
      'dynasty',
      'status',
      'knowledge_type',
      'relation_type',
      'description',
      'name',
      'event_type',
      'time_raw',
      'time_start_year',
      'time_end_year',
      'time_precision',
      'updated_at',
    };
    final updates = <String, Object?>{
      for (final entry in before.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
      'updated_at': nowIso(),
    };
    await store.db.transaction((txn) async {
      await txn.update(table, updates, where: 'id = ?', whereArgs: [targetId]);
      await _audit(
        txn,
        targetType: targetType,
        targetId: targetId,
        action: 'undo',
        before: row,
        after: updates,
      );
    });
  }

  /// Merges [otherIds] into [primaryId], preserving all evidence and auditing
  /// the operation. Duplicate relations/participants created by the merge are
  /// consolidated instead of being left as separate rows.
  Future<void> mergeEntities(String primaryId, List<String> otherIds) async {
    if (otherIds.isEmpty) return;
    await store.db.transaction((txn) async {
      final primaryRows = await txn.query(
        'entities',
        where: 'id = ?',
        whereArgs: [primaryId],
        limit: 1,
      );
      if (primaryRows.isEmpty) return;
      final primary = primaryRows.first;
      final aliases = {..._decodeStringList(primary['aliases'])};
      for (final otherId in otherIds) {
        if (otherId == primaryId) continue;
        final otherRows = await txn.query(
          'entities',
          where: 'id = ?',
          whereArgs: [otherId],
          limit: 1,
        );
        if (otherRows.isEmpty) continue;
        final other = otherRows.first;
        aliases
          ..add('${other['canonical_name']}')
          ..addAll(_decodeStringList(other['aliases']))
          ..remove('${primary['canonical_name']}');
        await txn.update(
          'entities',
          {'aliases': jsonEncode(aliases.toList()), 'updated_at': nowIso()},
          where: 'id = ?',
          whereArgs: [primaryId],
        );
        await txn.update(
          'entity_mentions',
          {'entity_id': primaryId},
          where: 'entity_id = ?',
          whereArgs: [otherId],
        );
        await txn.update(
          'entity_relations',
          {'from_entity_id': primaryId, 'updated_at': nowIso()},
          where: 'from_entity_id = ?',
          whereArgs: [otherId],
        );
        await txn.update(
          'entity_relations',
          {'to_entity_id': primaryId, 'updated_at': nowIso()},
          where: 'to_entity_id = ?',
          whereArgs: [otherId],
        );
        await txn.update(
          'event_participants',
          {'entity_id': primaryId},
          where: 'entity_id = ?',
          whereArgs: [otherId],
        );
        await txn.delete('entities', where: 'id = ?', whereArgs: [otherId]);
        await _audit(
          txn,
          targetType: 'entity',
          targetId: otherId,
          action: 'merge_into:$primaryId',
          before: other,
          after: {'merged_into': primaryId},
        );
      }
      await _dedupeRelations(txn);
      await _dedupeParticipants(txn);
    });
  }

  /// Splits selected mentions from [entityId] into a new entity.
  Future<String> splitEntity({
    required String entityId,
    required List<String> mentionIds,
    required String newName,
  }) async {
    final newId = newLocalId('ent');
    await store.db.transaction((txn) async {
      final rows = await txn.query(
        'entities',
        where: 'id = ?',
        whereArgs: [entityId],
        limit: 1,
      );
      if (rows.isEmpty || mentionIds.isEmpty) return;
      final source = rows.first;
      final now = nowIso();
      await txn.insert('entities', {
        'id': newId,
        'canonical_name': newName.trim().isEmpty
            ? '${source['canonical_name']}（拆分）'
            : newName.trim(),
        'kind': source['kind'],
        'aliases': '[]',
        'dynasty': source['dynasty'],
        'status': 'pending',
        'knowledge_type': 'human_verified',
        'created_at': now,
        'updated_at': now,
      });
      final placeholders = List.filled(mentionIds.length, '?').join(',');
      await txn.rawUpdate(
        'UPDATE entity_mentions SET entity_id = ? WHERE id IN ($placeholders)',
        [newId, ...mentionIds],
      );
      await _audit(
        txn,
        targetType: 'entity',
        targetId: entityId,
        action: 'split_to:$newId',
        before: source,
        after: {'new_entity_id': newId, 'mention_ids': mentionIds},
      );
    });
    return newId;
  }

  Future<void> _dedupeRelations(DatabaseExecutor txn) async {
    final groups = await txn.rawQuery('''
      SELECT from_entity_id, to_entity_id, relation_type,
             GROUP_CONCAT(id) AS ids
      FROM entity_relations
      GROUP BY from_entity_id, to_entity_id, relation_type
      HAVING COUNT(*) > 1
      ''');
    for (final group in groups) {
      final ids = '${group['ids']}'
          .split(',')
          .where((id) => id.isNotEmpty)
          .toList();
      if (ids.length < 2) continue;
      final keep = ids.first;
      for (final duplicate in ids.skip(1)) {
        await txn.update(
          'relation_sources',
          {'relation_id': keep},
          where: 'relation_id = ?',
          whereArgs: [duplicate],
        );
        await txn.delete(
          'entity_relations',
          where: 'id = ?',
          whereArgs: [duplicate],
        );
      }
    }
  }

  Future<void> _dedupeParticipants(DatabaseExecutor txn) async {
    final groups = await txn.rawQuery('''
      SELECT event_id, name, GROUP_CONCAT(id) AS ids
      FROM event_participants
      GROUP BY event_id, name
      HAVING COUNT(*) > 1
      ''');
    for (final group in groups) {
      final ids = '${group['ids']}'
          .split(',')
          .where((id) => id.isNotEmpty)
          .toList();
      for (final duplicate in ids.skip(1)) {
        await txn.delete(
          'event_participants',
          where: 'id = ?',
          whereArgs: [duplicate],
        );
      }
    }
  }

  Future<List<HistoricalEvent>> listEvents({
    String? query,
    String? eventType,
    bool includeExtracted = true,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];
    if (query != null && query.trim().isNotEmpty) {
      conditions.add('name LIKE ?');
      args.add('%${query.trim()}%');
    }
    if (eventType != null && eventType.isNotEmpty) {
      conditions.add('event_type = ?');
      args.add(eventType);
    }
    if (!includeExtracted) conditions.add("status != 'extracted'");
    final rows = await store.db.query(
      'historical_events',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'COALESCE(time_start_year, 999999), created_at DESC',
      limit: 500,
    );
    return [
      for (final row in rows)
        HistoricalEvent(
          id: row['id'] as String,
          name: row['name'] as String,
          eventType: row['event_type'] as String? ?? '其他',
          description: row['description'] as String?,
          timeRaw: row['time_raw'] as String?,
          timeStartYear: row['time_start_year'] as int?,
          timeEndYear: row['time_end_year'] as int?,
          timeEndRaw: row['time_end_raw'] as String?,
          location: row['location'] as String?,
          timePrecision: row['time_precision'] as String? ?? 'unknown',
          dynasty: row['dynasty'] as String?,
          status: row['status'] as String? ?? 'extracted',
          knowledgeType: row['knowledge_type'] as String? ?? 'inferred',
          sourceKind: row['source_kind'] as String? ?? 'ai',
          updatedBy: row['updated_by'] as String?,
        ),
    ];
  }

  Future<HistoricalEvent?> event(String id) async {
    final rows = await store.db.query(
      'historical_events',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final participantRows = await store.db.query(
      'event_participants',
      where: 'event_id = ?',
      whereArgs: [id],
    );
    final sourceRows = await store.db.rawQuery(
      '''
      SELECT s.*, b.title AS book_title, c.title AS chapter_title
      FROM event_sources s LEFT JOIN books b ON b.id = s.book_id
      LEFT JOIN chapters c ON c.id = s.chapter_id
      WHERE s.event_id = ?
      ''',
      [id],
    );
    return HistoricalEvent(
      id: id,
      name: row['name'] as String,
      eventType: row['event_type'] as String? ?? '其他',
      description: row['description'] as String?,
      timeRaw: row['time_raw'] as String?,
      timeStartYear: row['time_start_year'] as int?,
      timeEndYear: row['time_end_year'] as int?,
      timeEndRaw: row['time_end_raw'] as String?,
      location: row['location'] as String?,
      timePrecision: row['time_precision'] as String? ?? 'unknown',
      dynasty: row['dynasty'] as String?,
      status: row['status'] as String? ?? 'extracted',
      knowledgeType: row['knowledge_type'] as String? ?? 'inferred',
      sourceKind: row['source_kind'] as String? ?? 'ai',
      updatedBy: row['updated_by'] as String?,
      participants: [
        for (final participant in participantRows)
          participant['name'] as String,
      ],
      sources: [
        for (final source in sourceRows)
          RelationSource(
            id: source['id'] as String?,
            quote: source['quote'] as String?,
            bookId: source['book_id'] as String?,
            chapterId: source['chapter_id'] as String?,
            sentenceId: source['sentence_id'] as String?,
            paragraphId: source['paragraph_id'] as String?,
            bookTitle: source['book_title'] as String?,
            chapterTitle: source['chapter_title'] as String?,
            evidenceType: source['evidence_type'] as String? ?? 'supporting',
            sourceKind: source['source_kind'] as String? ?? 'ai',
            note: source['note'] as String?,
            reviewStatus: source['review_status'] as String? ?? 'pending',
            createdAt: source['created_at'] as String?,
          ),
      ],
    );
  }

  Future<LocalGraphData> graph({
    String? centerId,
    int depth = 2,
    bool includePending = true,
  }) async {
    final nodeRows = await store.db.query('entities');
    final nodes = <String, GraphNode>{};
    for (final row in nodeRows) {
      nodes[row['id'] as String] = GraphNode(
        id: row['id'] as String,
        label: row['canonical_name'] as String,
        kind: row['kind'] as String? ?? 'person',
        dynasty: row['dynasty'] as String?,
        status: row['status'] as String?,
      );
    }
    final relationRows = await store.db.rawQuery(
      includePending ? 'SELECT * FROM entity_relations' : "SELECT * FROM entity_relations WHERE status IN ('confirmed','explicit')",
    );
    final edges = <GraphEdge>[];
    final degrees = <String, int>{};
    for (final row in relationRows) {
      final source = row['from_entity_id'] as String;
      final target = row['to_entity_id'] as String;
      if (!nodes.containsKey(source) || !nodes.containsKey(target)) continue;
      degrees[source] = (degrees[source] ?? 0) + 1;
      degrees[target] = (degrees[target] ?? 0) + 1;
      edges.add(
        GraphEdge(
          id: row['id'] as String,
          source: source,
          target: target,
          relationType: row['relation_type'] as String? ?? '其他',
          label: row['label'] as String?,
          status: row['status'] as String? ?? 'inferred',
        ),
      );
    }
    var visible = nodes.values.toList();
    if (centerId != null &&
        centerId.isNotEmpty &&
        nodes.containsKey(centerId)) {
      final adjacency = <String, Set<String>>{};
      for (final edge in edges) {
        adjacency.putIfAbsent(edge.source, () => {}).add(edge.target);
        adjacency.putIfAbsent(edge.target, () => {}).add(edge.source);
      }
      final visited = <String>{centerId};
      var frontier = <String>{centerId};
      for (var level = 0; level < depth; level++) {
        final next = <String>{};
        for (final id in frontier) {
          next.addAll(adjacency[id] ?? const {});
        }
        next.removeAll(visited);
        visited.addAll(next);
        frontier = next;
      }
      visible = visible.where((node) => visited.contains(node.id)).toList();
    }
    final visibleIds = visible.map((node) => node.id).toSet();
    final finalEdges = edges
        .where(
          (edge) =>
              visibleIds.contains(edge.source) &&
              visibleIds.contains(edge.target),
        )
        .toList();
    final withDegree = [
      for (final node in visible)
        GraphNode(
          id: node.id,
          label: node.label,
          kind: node.kind,
          dynasty: node.dynasty,
          status: node.status,
          degree: degrees[node.id] ?? 0,
        ),
    ];
    return LocalGraphData(
      nodes: withDegree,
      edges: finalEdges,
      centerId: centerId,
    );
  }

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
}

class KnowledgeException implements Exception {
  KnowledgeException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _EntityCandidate {
  const _EntityCandidate({
    required this.id,
    required this.name,
    required this.kind,
    required this.status,
    required this.score,
    this.dynasty,
  });

  final String id;
  final String name;
  final String kind;
  final String? dynasty;
  final String status;
  final double score;
}

class _EntityDecision {
  const _EntityDecision({
    required this.entityId,
    required this.isNew,
    required this.status,
    required this.confidence,
    required this.candidates,
    required this.name,
    required this.kind,
    required this.record,
    this.reason,
    this.dynasty,
  });

  final String entityId;
  final bool isNew;
  final String status;
  final double confidence;
  final List<_EntityCandidate> candidates;
  final String name;
  final String kind;
  final String? dynasty;
  final String? reason;
  final bool record;
}

class _ExtractionContext {
  const _ExtractionContext({
    required this.taskId,
    required this.providerId,
    required this.modelId,
    required this.promptVersion,
    required this.schemaVersion,
    required this.chunkIndex,
  });

  final String taskId;
  final String providerId;
  final String modelId;
  final int promptVersion;
  final int schemaVersion;
  final int chunkIndex;
}

class _KnowledgeChunk {
  const _KnowledgeChunk({
    required this.index,
    required this.sentences,
    required this.contentHash,
  });

  final int index;
  final List<Sentence> sentences;
  final String contentHash;
}

class _ChunkApplyStats {
  const _ChunkApplyStats({
    required this.createdEntities,
    required this.matchedEntities,
    required this.createdRelations,
    required this.matchedRelations,
    required this.createdEvents,
    required this.matchedEvents,
  });

  final int createdEntities;
  final int matchedEntities;
  final int createdRelations;
  final int matchedRelations;
  final int createdEvents;
  final int matchedEvents;
}
