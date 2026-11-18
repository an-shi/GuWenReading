import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import 'local_store.dart';
import 'tokenizer_adapter.dart';

class TokenizerVocabularyRecord {
  const TokenizerVocabularyRecord({
    required this.key,
    required this.name,
    required this.version,
    required this.models,
    required this.source,
    required this.fileSize,
    required this.checksum,
    required this.status,
    required this.installedAt,
  });

  final String key;
  final String name;
  final String version;
  final List<String> models;
  final String? source;
  final int fileSize;
  final String checksum;
  final String status;
  final String installedAt;

  factory TokenizerVocabularyRecord.fromRow(Map<String, Object?> row) =>
      TokenizerVocabularyRecord(
        key: row['key'] as String,
        name: row['name'] as String,
        version: row['version'] as String,
        models: (() {
          try {
            return (jsonDecode('${row['models']}') as List)
                .map((item) => '$item')
                .toList();
          } catch (_) {
            return const <String>[];
          }
        })(),
        source: row['source'] as String?,
        fileSize: row['file_size'] as int? ?? 0,
        checksum: row['checksum'] as String,
        status: row['status'] as String? ?? 'installed',
        installedAt: row['installed_at'] as String? ?? '',
      );
}

/// Installs optional local vocabularies. The vocabulary is a JSON object with
/// a `tokens` array or a `vocab` map. It is an exact longest-match vocabulary
/// tokenizer, not a claim to reproduce a provider's proprietary BPE.
class TokenizerVocabularyService {
  TokenizerVocabularyService(this.store);

  final LocalStore store;

  Future<List<TokenizerVocabularyRecord>> list() async {
    final rows = await store.db.query(
      'tokenizer_vocabularies',
      orderBy: 'installed_at DESC',
    );
    return rows.map(TokenizerVocabularyRecord.fromRow).toList();
  }

  Future<String?> install({
    required String key,
    required String name,
    required String version,
    required List<String> models,
    required List<int> bytes,
    String? source,
    String? expectedChecksum,
  }) async {
    final checksum = sha256.convert(bytes).toString();
    if (expectedChecksum != null &&
        expectedChecksum.toLowerCase() != checksum) {
      return '校验值不匹配';
    }
    late final List<String> tokens;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map) {
        final vocab = decoded['tokens'] ?? decoded['vocab'];
        if (vocab is List) {
          tokens = vocab
              .map((item) => '$item')
              .where((item) => item.isNotEmpty)
              .toList();
        } else if (vocab is Map) {
          tokens = vocab.keys.map((item) => '$item').toList();
        } else {
          tokens = const [];
        }
      } else {
        tokens = const [];
      }
      if (tokens.isEmpty) return '词表为空或格式不正确';
    } catch (_) {
      return '词表 JSON 无法解析';
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await store.db.insert('tokenizer_vocabularies', {
      'key': key,
      'name': name,
      'version': version,
      'models': jsonEncode(models),
      'source': source,
      'file_size': bytes.length,
      'checksum': checksum,
      'vocab_json': jsonEncode({'tokens': tokens}),
      'status': 'installed',
      'installed_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    TokenizerRegistry.register(
      key,
      VocabularyTokenizerAdapter(name: key, tokens: tokens),
    );
    return null;
  }

  Future<void> uninstall(String key) async {
    await store.db.delete(
      'tokenizer_vocabularies',
      where: 'key = ?',
      whereArgs: [key],
    );
    TokenizerRegistry.unregister(key);
  }

  Future<void> loadInstalled() async {
    final rows = await store.db.query('tokenizer_vocabularies');
    for (final row in rows) {
      try {
        final decoded =
            jsonDecode('${row['vocab_json']}') as Map<String, dynamic>;
        final tokens = (decoded['tokens'] as List? ?? const [])
            .map((item) => '$item')
            .toList();
        if (tokens.isEmpty) continue;
        TokenizerRegistry.register(
          '${row['key']}',
          VocabularyTokenizerAdapter(name: '${row['key']}', tokens: tokens),
        );
      } catch (_) {
        await store.db.update(
          'tokenizer_vocabularies',
          {'status': 'invalid'},
          where: 'key = ?',
          whereArgs: [row['key']],
        );
      }
    }
  }
}

class VocabularyTokenizerAdapter implements TokenizerAdapter {
  VocabularyTokenizerAdapter({required this.name, required List<String> tokens})
    : _tokens = [...tokens]..sort((a, b) => b.length.compareTo(a.length)),
      _maxLength = tokens.fold<int>(
        1,
        (max, token) => math.max(max, token.length),
      );

  @override
  final String name;
  final List<String> _tokens;
  final int _maxLength;

  @override
  TokenCountSource get source => TokenCountSource.localTokenizer;

  @override
  TokenCount count(String text) {
    if (text.isEmpty) {
      return TokenCount(tokens: 0, source: source, tokenizer: name);
    }
    var tokens = 0;
    var index = 0;
    while (index < text.length) {
      final max = math.min(text.length, index + _maxLength);
      var matched = false;
      for (var end = max; end > index; end--) {
        if (_tokens.contains(text.substring(index, end))) {
          tokens += 1;
          index = end;
          matched = true;
          break;
        }
      }
      if (!matched) {
        tokens += 1;
        index += 1;
      }
    }
    return TokenCount(
      tokens: math.max(1, tokens),
      source: source,
      tokenizer: name,
    );
  }
}
