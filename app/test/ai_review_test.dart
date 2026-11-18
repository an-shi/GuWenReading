import 'package:flutter_test/flutter_test.dart';
import 'package:guwenreader/core/local/ai_service.dart';
import 'package:guwenreader/core/local/app_database.dart';
import 'package:guwenreader/core/local/knowledge_service.dart';
import 'package:guwenreader/core/local/local_store.dart';

void main() {
  test(
    'merge preserves evidence, dedupes relations and records audit',
    () async {
      final database = await AppDatabase.openInMemory();
      final store = LocalStore(database);
      final ai = AiSettingsService(store: store);
      final knowledge = KnowledgeService(
        store: store,
        aiSettings: ai,
        client: AiJsonClient(ai),
      );
      await store.insertEntity(
        id: 'a',
        canonicalName: '李四',
        kind: 'person',
        aliases: const [],
      );
      await store.insertEntity(
        id: 'b',
        canonicalName: '李四',
        kind: 'person',
        aliases: const ['李司空'],
      );
      await store.insertEntity(
        id: 'c',
        canonicalName: '张三',
        kind: 'person',
        aliases: const [],
      );
      final now = DateTime.now().toUtc().toIso8601String();
      await store.db.insert('entity_mentions', {
        'id': 'm1',
        'entity_id': 'a',
        'quote': '李四',
        'created_at': now,
      });
      await store.db.insert('entity_mentions', {
        'id': 'm2',
        'entity_id': 'b',
        'quote': '李司空',
        'created_at': now,
      });
      await store.db.insert('entity_relations', {
        'id': 'r1',
        'from_entity_id': 'a',
        'to_entity_id': 'c',
        'relation_type': '朋友关系',
        'status': 'inferred',
        'created_at': now,
        'updated_at': now,
      });
      await store.db.insert('entity_relations', {
        'id': 'r2',
        'from_entity_id': 'b',
        'to_entity_id': 'c',
        'relation_type': '朋友关系',
        'status': 'inferred',
        'created_at': now,
        'updated_at': now,
      });
      await store.db.insert('relation_sources', {
        'id': 'rs1',
        'relation_id': 'r1',
        'quote': '李四与张三友善',
      });
      await store.db.insert('relation_sources', {
        'id': 'rs2',
        'relation_id': 'r2',
        'quote': '李司空与张三友善',
      });

      await knowledge.mergeEntities('a', ['b']);

      expect(
        (await store.db.query('entities', where: 'id = ?', whereArgs: ['b'])),
        isEmpty,
      );
      final primary = await store.db.query(
        'entities',
        where: 'id = ?',
        whereArgs: ['a'],
      );
      expect(primary.first['aliases'], contains('李司空'));
      expect(
        (await store.db.rawQuery(
          'SELECT COUNT(*) AS n FROM entity_mentions WHERE entity_id = ?',
          ['a'],
        )).first['n'],
        2,
      );
      final relations = await store.db.query('entity_relations');
      expect(relations, hasLength(1));
      expect(
        (await store.db.rawQuery(
          'SELECT COUNT(*) AS n FROM relation_sources WHERE relation_id = ?',
          [relations.first['id']],
        )).first['n'],
        2,
      );
      final audits = await knowledge.reviewHistory(targetType: 'entity');
      expect(
        audits.any((row) => '${row['action']}'.startsWith('merge_into')),
        isTrue,
      );
      await database.close();
    },
  );

  test(
    'confirm writes human_verified and undo restores previous status',
    () async {
      final database = await AppDatabase.openInMemory();
      final store = LocalStore(database);
      final ai = AiSettingsService(store: store);
      final knowledge = KnowledgeService(
        store: store,
        aiSettings: ai,
        client: AiJsonClient(ai),
      );
      await store.insertEntity(
        id: 'a',
        canonicalName: '李四',
        kind: 'person',
        aliases: const [],
        dynasty: '唐',
      );
      await knowledge.setEntityStatus('a', 'confirmed');
      var row = (await store.db.query(
        'entities',
        where: 'id = ?',
        whereArgs: ['a'],
      )).first;
      expect(row['knowledge_type'], 'human_verified');

      final audits = await knowledge.reviewHistory(
        targetType: 'entity',
        targetId: 'a',
      );
      expect(audits, isNotEmpty);
      await knowledge.undoReview(audits.first['id'] as String);
      row = (await store.db.query(
        'entities',
        where: 'id = ?',
        whereArgs: ['a'],
      )).first;
      expect(row['status'], 'pending');
      expect(row['knowledge_type'], 'explicit');
      await database.close();
    },
  );

  test('split moves selected mentions to a new entity and audits', () async {
    final database = await AppDatabase.openInMemory();
    final store = LocalStore(database);
    final ai = AiSettingsService(store: store);
    final knowledge = KnowledgeService(
      store: store,
      aiSettings: ai,
      client: AiJsonClient(ai),
    );
    await store.insertEntity(
      id: 'a',
      canonicalName: '李四',
      kind: 'person',
      aliases: const [],
    );
    final now = DateTime.now().toUtc().toIso8601String();
    for (final id in ['m1', 'm2']) {
      await store.db.insert('entity_mentions', {
        'id': id,
        'entity_id': 'a',
        'quote': id == 'm1' ? '李四（唐）' : '李四（汉）',
        'created_at': now,
      });
    }
    final newId = await knowledge.splitEntity(
      entityId: 'a',
      mentionIds: const ['m2'],
      newName: '李四（汉）',
    );
    expect(
      (await store.db.query(
        'entity_mentions',
        where: 'id = ?',
        whereArgs: ['m1'],
      )).first['entity_id'],
      'a',
    );
    expect(
      (await store.db.query(
        'entity_mentions',
        where: 'id = ?',
        whereArgs: ['m2'],
      )).first['entity_id'],
      newId,
    );
    final split = await store.db.query(
      'knowledge_review_events',
      where: "action LIKE 'split_to:%'",
    );
    expect(split, hasLength(1));
    await database.close();
  });
}
