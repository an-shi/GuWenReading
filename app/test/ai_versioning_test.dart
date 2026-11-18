import 'package:flutter_test/flutter_test.dart';
import 'package:guwenreader/core/local/ai_service.dart';
import 'package:guwenreader/core/local/app_database.dart';
import 'package:guwenreader/core/local/local_models.dart';
import 'package:guwenreader/core/local/local_store.dart';

void main() {
  test('prompt and schema versions can be added and activated', () async {
    final database = await AppDatabase.openInMemory();
    final store = LocalStore(database);
    final ai = AiSettingsService(store: store);
    await ai.seedPrompts();

    expect(await ai.activePromptVersion('translation'), 1);
    final v1 = await store.activePrompt('translation');
    expect(v1, isNotNull);
    await store.insertPrompt(
      PromptRecord(
        id: newLocalId('prompt'),
        key: 'translation',
        version: 2,
        name: '翻译 v2',
        template: '${v1!.template}\n补充规则',
        variables: v1.variables,
        isActive: false,
      ),
    );
    expect(await ai.activePromptVersion('translation'), 1);
    await store.activatePrompt('translation', 2);
    expect(await ai.activePromptVersion('translation'), 2);
    expect(
      (await store.activePrompt('translation'))!.template,
      contains('补充规则'),
    );

    final schemaKeys = (await store.allSchemas())
        .map((item) => item.key)
        .toSet();
    expect(schemaKeys, containsAll(['translation', 'knowledge_extract']));
    expect(await store.activeSchemaVersion('knowledge_extract'), 2);
    await store.insertSchema(
      PromptSchemaRecord(
        id: newLocalId('schema'),
        key: 'knowledge_extract',
        version: 3,
        name: '抽取 v3',
        schemaJson: '{"type":"object"}',
      ),
    );
    await store.activateSchema('knowledge_extract', 3);
    expect(await store.activeSchemaVersion('knowledge_extract'), 3);
    final active = await store.activeSchema('knowledge_extract');
    expect(active!.version, 3);
    expect(active.schemaJson, contains('object'));

    await database.close();
  });
}
