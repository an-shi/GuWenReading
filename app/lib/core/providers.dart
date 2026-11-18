import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local/ai_service.dart';
import 'local/app_database.dart';
import 'local/assistant_service.dart';
import 'local/backup_service.dart';
import 'local/budget_service.dart';
import 'local/import_service.dart';
import 'local/knowledge_service.dart';
import 'local/local_engine/local_lexicon_service.dart';
import 'local/local_api.dart';
import 'local/local_store.dart';
import 'local/quality_service.dart';
import 'local/search_service.dart';
import 'local/task_recovery_service.dart';
import 'local/tokenizer_vocabulary.dart';
import 'local/translation_service.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('appDatabaseProvider must be overridden');
});

final localStoreProvider = Provider<LocalStore>((ref) {
  return LocalStore(ref.watch(appDatabaseProvider));
});

final aiSettingsProvider = Provider<AiSettingsService>((ref) {
  return AiSettingsService(store: ref.watch(localStoreProvider));
});

final aiClientProvider = Provider<AiJsonClient>((ref) {
  return AiJsonClient(ref.watch(aiSettingsProvider));
});

final budgetServiceProvider = Provider<BudgetService>((ref) {
  return BudgetService(store: ref.watch(localStoreProvider));
});

final qualityServiceProvider = Provider<QualityService>((ref) {
  return const QualityService();
});

final tokenizerVocabularyProvider = Provider<TokenizerVocabularyService>((ref) {
  return TokenizerVocabularyService(ref.watch(localStoreProvider));
});

final localLexiconProvider = Provider<LocalLexiconService>((ref) {
  return LocalLexiconService(ref.watch(localStoreProvider));
});

final importServiceProvider = Provider<ImportService>((ref) {
  return ImportService(
    store: ref.watch(localStoreProvider),
    paths: ref.watch(appDatabaseProvider).paths,
  );
});

final translationServiceProvider = Provider<TranslationService>((ref) {
  return TranslationService(
    store: ref.watch(localStoreProvider),
    aiSettings: ref.watch(aiSettingsProvider),
    client: ref.watch(aiClientProvider),
    budgets: ref.watch(budgetServiceProvider),
    quality: ref.watch(qualityServiceProvider),
  );
});

final knowledgeServiceProvider = Provider<KnowledgeService>((ref) {
  return KnowledgeService(
    store: ref.watch(localStoreProvider),
    aiSettings: ref.watch(aiSettingsProvider),
    client: ref.watch(aiClientProvider),
    budgets: ref.watch(budgetServiceProvider),
    quality: ref.watch(qualityServiceProvider),
  );
});

final searchServiceProvider = Provider<SearchService>((ref) {
  return SearchService(ref.watch(localStoreProvider));
});

final taskRecoveryServiceProvider = Provider<TaskRecoveryService>((ref) {
  return TaskRecoveryService(
    store: ref.watch(localStoreProvider),
    translation: ref.watch(translationServiceProvider),
    knowledge: ref.watch(knowledgeServiceProvider),
  );
});

final assistantServiceProvider = Provider<AssistantService>((ref) {
  return AssistantService(
    store: ref.watch(localStoreProvider),
    aiSettings: ref.watch(aiSettingsProvider),
    client: ref.watch(aiClientProvider),
    search: ref.watch(searchServiceProvider),
  );
});

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    store: ref.watch(localStoreProvider),
    paths: ref.watch(appDatabaseProvider).paths,
  );
});

final localApiProvider = Provider<LocalApi>((ref) {
  return LocalApi(
    store: ref.watch(localStoreProvider),
    importService: ref.watch(importServiceProvider),
    translationService: ref.watch(translationServiceProvider),
    knowledgeService: ref.watch(knowledgeServiceProvider),
    searchService: ref.watch(searchServiceProvider),
    assistantService: ref.watch(assistantServiceProvider),
    backupService: ref.watch(backupServiceProvider),
    aiSettings: ref.watch(aiSettingsProvider),
  );
});
