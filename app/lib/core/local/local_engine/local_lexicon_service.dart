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
      orderBy: 'is_custom DESC, word ASC',
    );
    return rows
        .map(
          (row) => {...row, 'meanings': jsonDecode('${row['meanings_json']}')},
        )
        .toList();
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
    localCustomLexicon[word] = LexiconEntry(
      word: word,
      kind: kind,
      meanings: meanings.map((item) => LexiconMeaning(item)).toList(),
      source: source ?? '用户自定义',
      confidence: confidence,
    );
  }

  Future<void> remove(String id) async {
    final rows = await store.db.query(
      'local_lexicon_entries',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    await store.db.delete(
      'local_lexicon_entries',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isNotEmpty) {
      localCustomLexicon.remove('${rows.first['word']}');
    }
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
    final rows = await store.db.query(
      'local_lexicon_entries',
      where: 'is_custom = 1 AND status = ?',
      whereArgs: ['active'],
    );
    localCustomLexicon.clear();
    for (final row in rows) {
      try {
        final meanings = (jsonDecode('${row['meanings_json']}') as List)
            .map((item) => '$item')
            .toList();
        localCustomLexicon['${row['word']}'] = LexiconEntry(
          word: '${row['word']}',
          kind: '${row['kind'] ?? '实词'}',
          meanings: meanings.map((item) => LexiconMeaning(item)).toList(),
          source: row['source'] as String? ?? '用户自定义',
          confidence: (row['confidence'] as num? ?? 0.85).toDouble(),
        );
      } catch (_) {
        // Invalid custom entries must not break the engine.
      }
    }
  }
}
