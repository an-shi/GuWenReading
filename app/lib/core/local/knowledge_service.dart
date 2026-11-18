import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/models.dart';
import 'ai_service.dart';
import 'app_database.dart';
import 'local_models.dart';
import 'local_store.dart';
import 'tokenizer_adapter.dart';

class KnowledgeService {
  KnowledgeService({
    required this.store,
    required this.aiSettings,
    required this.client,
  });

  final LocalStore store;
  final AiSettingsService aiSettings;
  final AiJsonClient client;

  static const _schemaVersion = 2;

  Future<TaskInfo> startExtraction(String chapterId) async {
    final active = await store.activeTask(
      type: 'knowledge_extraction',
      chapterId: chapterId,
    );
    if (active != null && active.status != 'paused') return active;
    if (active != null) {
      await store.updateTask(active.id, status: 'running', error: null);
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
    unawaited(_runExtraction(task.id, chapterId));
    return task;
  }

  Future<void> _runExtraction(String taskId, String chapterId) async {
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
      'knowledge_extract',
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
        cachedState['schema_version'] == _schemaVersion) {
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
    var completedChunks = 0;
    var failedChunks = 0;
    var cachedChunks = 0;
    var createdEntities = 0;
    var matchedEntities = 0;
    var createdRelations = 0;
    var matchedRelations = 0;
    var createdEvents = 0;
    var matchedEvents = 0;
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
          schemaVersion: _schemaVersion,
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
          );
          await store.putKnowledgeChunkCache(
            chapterId: chapterId,
            chunkIndex: chunk.index,
            contentHash: chunk.contentHash,
            modelLabel: resolved.label,
            promptVersion: promptVersion,
            schemaVersion: _schemaVersion,
            resultJson: jsonEncode(data),
          );
        }
        final stats = await _applyChunk(content, chunk, data);
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
      schemaVersion: _schemaVersion,
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
        'model': resolved.label,
      },
    );
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
  ) async {
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
        final existing = await _findEntityRecord(txn, name, aliases);
        final now = nowIso();
        String entityId;
        if (existing == null) {
          entityId = newLocalId('ent');
          await txn.insert('entities', {
            'id': entityId,
            'canonical_name': name,
            'kind': kind,
            'aliases': jsonEncode(aliases),
            'dynasty': dynasty,
            'status': 'pending',
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
          await txn.update(
            'entities',
            updates,
            where: 'id = ?',
            whereArgs: [entityId],
          );
        }
        entityIds[localId] = entityId;
        entityNames[entityId] = name;
        for (final sentence in _evidenceSentences(
          item['evidence'],
          sentenceByIndex,
        )) {
          await _insertMentionIfMissing(
            txn,
            entityId: entityId,
            content: content,
            sentence: sentence,
            quote: sentence.originalText,
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
      'created_at': nowIso(),
    });
  }

  Future<void> _insertRelationSourceIfMissing(
    DatabaseExecutor txn, {
    required String relationId,
    required ChapterContent content,
    required Sentence sentence,
    required String quote,
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
    });
  }

  Future<void> _insertEventSourceIfMissing(
    DatabaseExecutor txn, {
    required String eventId,
    required ChapterContent content,
    required Sentence sentence,
    required String quote,
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
      final sources = await store.db.query(
        'relation_sources',
        where: 'relation_id = ?',
        whereArgs: [relation['id']],
      );
      relations.add(
        EntityRelation(
          id: relation['id'] as String,
          relationType: relation['relation_type'] as String? ?? '其他',
          otherName: relation['other_entity_name'] as String?,
          otherId: relation['other_entity_id'] as String?,
          description: relation['description'] as String?,
          status: relation['status'] as String? ?? 'inferred',
          sources: [
            for (final source in sources)
              RelationSource(
                quote: source['quote'] as String?,
                bookTitle: null,
                chapterTitle: null,
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

  Future<void> setEntityStatus(String id, String status) async {
    await store.db.update(
      'entities',
      {'status': status, 'updated_at': nowIso()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setRelationStatus(String id, String status) async {
    await store.db.update(
      'entity_relations',
      {'status': status, 'updated_at': nowIso()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> mergeEntities(String primaryId, List<String> otherIds) async {
    for (final otherId in otherIds) {
      if (otherId == primaryId) continue;
      final primary = await store.db.query(
        'entities',
        where: 'id = ?',
        whereArgs: [primaryId],
        limit: 1,
      );
      final other = await store.db.query(
        'entities',
        where: 'id = ?',
        whereArgs: [otherId],
        limit: 1,
      );
      if (primary.isEmpty || other.isEmpty) continue;
      final aliases = {
        ..._decodeStringList(primary.first['aliases']),
        other.first['canonical_name'] as String,
        ..._decodeStringList(other.first['aliases']),
      };
      await store.db.update(
        'entities',
        {'aliases': jsonEncode(aliases.toList()), 'updated_at': nowIso()},
        where: 'id = ?',
        whereArgs: [primaryId],
      );
      await store.db.update(
        'entity_mentions',
        {'entity_id': primaryId},
        where: 'entity_id = ?',
        whereArgs: [otherId],
      );
      await store.db.update(
        'entity_relations',
        {'from_entity_id': primaryId},
        where: 'from_entity_id = ?',
        whereArgs: [otherId],
      );
      await store.db.update(
        'entity_relations',
        {'to_entity_id': primaryId},
        where: 'to_entity_id = ?',
        whereArgs: [otherId],
      );
      await store.db.update(
        'event_participants',
        {'entity_id': primaryId},
        where: 'entity_id = ?',
        whereArgs: [otherId],
      );
      await store.db.delete('entities', where: 'id = ?', whereArgs: [otherId]);
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
          timePrecision: row['time_precision'] as String? ?? 'unknown',
          dynasty: row['dynasty'] as String?,
          status: row['status'] as String? ?? 'extracted',
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
      timePrecision: row['time_precision'] as String? ?? 'unknown',
      dynasty: row['dynasty'] as String?,
      status: row['status'] as String? ?? 'extracted',
      participants: [
        for (final participant in participantRows)
          participant['name'] as String,
      ],
      sources: [
        for (final source in sourceRows)
          RelationSource(
            quote: source['quote'] as String?,
            bookTitle: source['book_title'] as String?,
            chapterTitle: source['chapter_title'] as String?,
          ),
      ],
    );
  }

  Future<void> setEventStatus(String id, String status) async {
    await store.db.update(
      'historical_events',
      {'status': status, 'updated_at': nowIso()},
      where: 'id = ?',
      whereArgs: [id],
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
