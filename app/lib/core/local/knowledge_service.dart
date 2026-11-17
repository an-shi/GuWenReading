import 'dart:async';
import 'dart:convert';

import '../../data/models.dart';
import 'ai_service.dart';
import 'app_database.dart';
import 'local_models.dart';
import 'local_store.dart';

class KnowledgeService {
  KnowledgeService({
    required this.store,
    required this.aiSettings,
    required this.client,
  });

  final LocalStore store;
  final AiSettingsService aiSettings;
  final AiJsonClient client;

  Future<TaskInfo> startExtraction(String chapterId) async {
    final content = await store.chapterContent(chapterId);
    if (content == null) throw KnowledgeException('章节不存在');
    final task = await store.createTask(
      type: 'knowledge_extraction',
      title: '抽取知识《${content.bookTitle}》· ${content.chapterTitle}',
      total: 3,
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
    final resolved = await aiSettings.resolve(purpose: 'chat');
    if (resolved == null) {
      await store.updateTask(taskId, status: 'failed', error: '尚未配置默认问答模型');
      return;
    }
    await store.updateTask(taskId, status: 'running', progress: 5);
    final paragraphsJson = jsonEncode([
      for (final paragraph in content.paragraphs)
        {
          'paragraph_id': paragraph.id,
          'sentences': [
            for (final sentence in paragraph.sentences)
              {'id': sentence.id, 'text': sentence.originalText},
          ],
        },
    ]);
    try {
      final entityPrompt = await aiSettings.render('entity_extract', {
        'book_title': content.bookTitle,
        'chapter_title': content.chapterTitle,
        'paragraphs_json': paragraphsJson,
      });
      final entityData = await client.chatJson(
        purpose: 'chat',
        prompt: entityPrompt,
        temperature: 0.1,
      );
      final entityRows = jsonList(entityData['entities']);
      var entityCount = 0;
      for (final item in entityRows) {
        final name = jsonString(item['name']);
        if (name == null) continue;
        final entityId = await _findOrCreateEntity(item, name);
        final mentions = jsonList(item['mentions']);
        for (final mention in mentions) {
          final sentenceId = jsonString(mention['sentence_id']);
          final sentence = _findSentence(content, sentenceId);
          final quote =
              jsonString(mention['quote']) ?? sentence?.originalText ?? '';
          if (quote.isEmpty) continue;
          await _insertMention(entityId, content, sentence?.id, quote);
        }
        entityCount += 1;
      }
      await store.updateTask(taskId, progress: 38);
      final entities = await listEntities();
      final relationPrompt = await aiSettings.render('relation_extract', {
        'book_title': content.bookTitle,
        'chapter_title': content.chapterTitle,
        'entities_json': jsonEncode([
          for (final entity in entities)
            {
              'name': entity.name,
              'aliases': entity.aliases,
              'kind': entity.kind,
            },
        ]),
        'paragraphs_json': paragraphsJson,
      });
      final relationData = await client.chatJson(
        purpose: 'chat',
        prompt: relationPrompt,
        temperature: 0.1,
      );
      var relationCount = 0;
      for (final item in jsonList(relationData['relations'])) {
        final fromName = jsonString(item['from']);
        final toName = jsonString(item['to']);
        if (fromName == null || toName == null || fromName == toName) continue;
        final from = await _findEntityByName(fromName);
        final to = await _findEntityByName(toName);
        if (from == null || to == null) continue;
        final type = jsonString(item['type']) ?? '其他';
        final existing = await store.db.query(
          'entity_relations',
          where:
              'from_entity_id = ? AND to_entity_id = ? AND relation_type = ?',
          whereArgs: [from['id'], to['id'], type],
          limit: 1,
        );
        if (existing.isNotEmpty) continue;
        final relationId = newLocalId('rel');
        final now = nowIso();
        await store.db.insert('entity_relations', {
          'id': relationId,
          'from_entity_id': from['id'],
          'to_entity_id': to['id'],
          'relation_type': type,
          'label': type,
          'description': jsonString(item['description']),
          'status': 'inferred',
          'confidence': 0.65,
          'created_at': now,
          'updated_at': now,
        });
        final sentenceId = jsonString(item['sentence_id']);
        final sentence = _findSentence(content, sentenceId);
        final quote = jsonString(item['quote']) ?? sentence?.originalText ?? '';
        if (quote.isNotEmpty) {
          await store.db.insert('relation_sources', {
            'id': newLocalId('relsrc'),
            'relation_id': relationId,
            'sentence_id': sentence?.id,
            'book_id': content.bookId,
            'chapter_id': content.chapterId,
            'quote': quote,
          });
        }
        relationCount += 1;
      }
      await store.updateTask(taskId, progress: 70);
      final eventPrompt = await aiSettings.render('event_extract', {
        'book_title': content.bookTitle,
        'chapter_title': content.chapterTitle,
        'paragraphs_json': paragraphsJson,
      });
      final eventData = await client.chatJson(
        purpose: 'chat',
        prompt: eventPrompt,
        temperature: 0.1,
      );
      var eventCount = 0;
      for (final item in jsonList(eventData['events'])) {
        final name = jsonString(item['name']);
        if (name == null) continue;
        final eventId = newLocalId('event');
        final now = nowIso();
        await store.db.insert('historical_events', {
          'id': eventId,
          'name': name,
          'event_type': jsonString(item['type']) ?? '其他',
          'description': jsonString(item['description']),
          'dynasty': jsonString(item['dynasty']),
          'time_raw': jsonString(item['time_raw']),
          'time_start_year': jsonInt(item['time_start_year']),
          'time_end_year': jsonInt(item['time_end_year']),
          'time_precision': jsonString(item['time_precision']) ?? 'unknown',
          'time_note': jsonString(item['time_note']),
          'status': 'extracted',
          'created_at': now,
          'updated_at': now,
        });
        for (final participant in (item['participants'] as List? ?? const [])) {
          final participantName = '$participant'.trim();
          if (participantName.isEmpty) continue;
          final entity = await _findEntityByName(participantName);
          await store.db.insert('event_participants', {
            'id': newLocalId('ep'),
            'event_id': eventId,
            'entity_id': entity?['id'],
            'name': participantName,
          });
        }
        final sentenceId = jsonString(item['sentence_id']);
        final sentence = _findSentence(content, sentenceId);
        final quote = jsonString(item['quote']) ?? sentence?.originalText ?? '';
        if (quote.isNotEmpty) {
          await store.db.insert('event_sources', {
            'id': newLocalId('esrc'),
            'event_id': eventId,
            'sentence_id': sentence?.id,
            'book_id': content.bookId,
            'chapter_id': content.chapterId,
            'quote': quote,
          });
        }
        eventCount += 1;
      }
      await store.updateTask(
        taskId,
        status: 'completed',
        progress: 100,
        completed: 3,
        result: {
          'entities_created': entityCount,
          'relations_created': relationCount,
          'events_created': eventCount,
          'model': resolved.label,
        },
      );
    } catch (error) {
      await store.updateTask(taskId, status: 'failed', error: '$error');
    }
  }

  Sentence? _findSentence(ChapterContent content, String? sentenceId) {
    if (sentenceId == null) return null;
    for (final paragraph in content.paragraphs) {
      for (final sentence in paragraph.sentences) {
        if (sentence.id == sentenceId) return sentence;
      }
    }
    return null;
  }

  Future<String> _findOrCreateEntity(
    Map<String, dynamic> item,
    String name,
  ) async {
    final existing = await _findEntityByName(name);
    if (existing != null) return existing['id'] as String;
    final id = newLocalId('ent');
    final now = nowIso();
    await store.db.insert('entities', {
      'id': id,
      'canonical_name': name,
      'kind': jsonString(item['kind']) ?? 'person',
      'aliases': jsonEncode(
        (item['aliases'] as List? ?? const [])
            .map((value) => '$value')
            .toList(),
      ),
      'dynasty': jsonString(item['dynasty']),
      'identity': jsonString(item['identity']),
      'summary': jsonString(item['summary']),
      'description': jsonString(item['description']),
      'birth_raw': jsonString(item['birth_raw']),
      'death_raw': jsonString(item['death_raw']),
      'birth_year': jsonInt(item['birth_year']),
      'death_year': jsonInt(item['death_year']),
      'courtesy_name': jsonString(item['courtesy_name']),
      'art_name': jsonString(item['art_name']),
      'offices': jsonEncode(
        (item['offices'] as List? ?? const [])
            .map((value) => '$value')
            .toList(),
      ),
      'status': 'pending',
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  Future<Map<String, Object?>?> _findEntityByName(String name) async {
    final value = name.trim();
    if (value.isEmpty) return null;
    final rows = await store.db.query(
      'entities',
      where: 'canonical_name = ?',
      whereArgs: [value],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first;
    final aliasRows = await store.db.query(
      'entities',
      where: 'aliases LIKE ?',
      whereArgs: ['%$value%'],
      limit: 1,
    );
    return aliasRows.isEmpty ? null : aliasRows.first;
  }

  Future<void> _insertMention(
    String entityId,
    ChapterContent content,
    String? sentenceId,
    String quote,
  ) async {
    final existing = await store.db.query(
      'entity_mentions',
      where: 'entity_id = ? AND book_id = ? AND chapter_id = ? AND quote = ?',
      whereArgs: [entityId, content.bookId, content.chapterId, quote],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    await store.db.insert('entity_mentions', {
      'id': newLocalId('mention'),
      'entity_id': entityId,
      'book_id': content.bookId,
      'chapter_id': content.chapterId,
      'sentence_id': sentenceId,
      'quote': quote,
      'status': 'pending',
      'created_at': nowIso(),
    });
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
