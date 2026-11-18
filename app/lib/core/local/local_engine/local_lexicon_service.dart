import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../local_store.dart';
import 'lexicon.dart';

class LocalLexiconService {
  LocalLexiconService(this.store);
  final LocalStore store;

  Future<List<Map<String, Object?>>> list() async {
    final rows = await store.db.query(
      'local_lexicon_entries',
      where: "status <> 'deleted'",
      orderBy: 'is_custom ASC, word ASC',
    );
    final effective = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final word = '${row['word']}';
      final existing = effective[word];
      if (existing == null || row['is_custom'] == 1) {
        effective[word] = {
          ...row,
          'meanings': jsonDecode('${row['meanings_json']}'),
        };
      }
    }
    final result = effective.values.toList()
      ..sort((a, b) {
        final customCompare = (b['is_custom'] as int? ?? 0).compareTo(
          a['is_custom'] as int? ?? 0,
        );
        return customCompare != 0
            ? customCompare
            : '${a['word']}'.compareTo('${b['word']}');
      });
    return result;
  }

  Future<void> upsert({
    required String word,
    required String kind,
    required List<String> meanings,
    String? source,
    double confidence = 0.85,
    bool custom = true,
  }) async {
    final id = 'lex-${custom ? 'custom' : 'builtin'}-$word';
    final now = DateTime.now().toUtc().toIso8601String();
    await store.db.insert('local_lexicon_entries', {
      'id': id,
      'word': word,
      'kind': kind,
      'meanings_json': jsonEncode(meanings),
      'source': source ?? '用户自定义',
      'version': lexiconVersion,
      'confidence': confidence,
      'is_custom': custom ? 1 : 0,
      'status': 'active',
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> remove(String id) async {
    await store.db.delete(
      'local_lexicon_entries',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<String> exportJson() async {
    final rows = await store.db.query(
      'local_lexicon_entries',
      where: 'is_custom = 1',
    );
    return jsonEncode({
      'format': 'guwenreader.local-lexicon.v1',
      'entries': rows
          .map(
            (row) => {
              'word': row['word'],
              'kind': row['kind'],
              'meanings': row['meanings_json'],
              'source': row['source'],
            },
          )
          .toList(),
    });
  }

  Future<void> loadCustom() async {
    await seedBuiltin();
  }

  Future<void> seedBuiltin() async {
    final seeded = await store.getSetting('local_lexicon_seed_version');
    if (seeded == lexiconVersion) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await store.db.transaction((txn) async {
      for (final entry in builtinLexicon.values) {
        await txn.insert('local_lexicon_entries', {
          'id': 'lex-builtin-${entry.word}',
          'word': entry.word,
          'kind': entry.kind,
          'meanings_json': jsonEncode(
            entry.meanings.map((meaning) => meaning.modern).toList(),
          ),
          'source': entry.source,
          'version': lexiconVersion,
          'confidence': entry.confidence,
          'is_custom': 0,
          'status': 'active',
          'created_at': now,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    await store.setSetting('local_lexicon_seed_version', lexiconVersion);
  }

  Future<Map<String, LexiconEntry>> effectiveLexicon() async {
    await seedBuiltin();
    final rows = await store.db.query(
      'local_lexicon_entries',
      where: 'status = ?',
      whereArgs: ['active'],
      orderBy: 'is_custom ASC, updated_at ASC',
    );
    final result = <String, LexiconEntry>{};
    for (final row in rows) {
      try {
        final meanings = (jsonDecode('${row['meanings_json']}') as List)
            .map((item) => '$item')
            .toList();
        if (meanings.isEmpty) continue;
        result['${row['word']}'] = LexiconEntry(
          word: '${row['word']}',
          kind: '${row['kind'] ?? '实词'}',
          meanings: meanings.map((item) => LexiconMeaning(item)).toList(),
          source: row['source'] as String? ?? '数据库词条',
          confidence: (row['confidence'] as num? ?? 0.85).toDouble(),
        );
      } catch (_) {
        // Invalid rows must not break local translation.
      }
    }
    return result;
  }
}
