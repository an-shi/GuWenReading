import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guwenreader/core/local/app_database.dart';
import 'package:guwenreader/core/local/local_models.dart';
import 'package:guwenreader/core/local/local_store.dart';
import 'package:guwenreader/core/local/tokenizer_adapter.dart';
import 'package:guwenreader/core/local/tokenizer_vocabulary.dart';

void main() {
  test('vocabulary install registers exact tokenizer and uninstall restores fallback', () async {
    final database = await AppDatabase.openInMemory();
    final store = LocalStore(database);
    final service = TokenizerVocabularyService(store);
    final bytes = utf8.encode(
      jsonEncode({
        'tokens': ['黄帝', '少典', '之子', '。'],
      }),
    );
    final error = await service.install(
      key: 'guwen-test',
      name: '古文测试词表',
      version: '1.0',
      models: const ['mock-model'],
      bytes: bytes,
    );
    expect(error, isNull);
    await service.loadInstalled();
    final model = AiModelRecord(
      id: 'm',
      providerId: 'p',
      name: 'mock-model',
      displayName: 'mock',
      tokenizer: 'guwen-test',
    );
    final adapter = TokenizerRegistry.forModel(model);
    expect(adapter.source, TokenCountSource.localTokenizer);
    expect(adapter.count('黄帝少典之子。').tokens, 4);

    await service.uninstall('guwen-test');
    final fallback = TokenizerRegistry.forModel(
      AiModelRecord(
        id: 'm',
        providerId: 'p',
        name: 'unknown-model',
        displayName: 'unknown',
      ),
    );
    expect(fallback.source, TokenCountSource.localEstimate);
    await database.close();
  });

  test('corrupt vocabulary is rejected and does not register', () async {
    final database = await AppDatabase.openInMemory();
    final store = LocalStore(database);
    final service = TokenizerVocabularyService(store);
    final error = await service.install(
      key: 'broken',
      name: 'broken',
      version: '1',
      models: const [],
      bytes: utf8.encode('{not-json'),
    );
    expect(error, contains('JSON'));
    expect(TokenizerRegistry.registeredKeys, isNot(contains('broken')));
    await database.close();
  });
}
