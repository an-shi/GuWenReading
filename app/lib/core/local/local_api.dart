import 'dart:typed_data';

import '../../data/models.dart';
import 'ai_service.dart';
import 'assistant_service.dart';
import 'backup_service.dart';
import 'import_service.dart';
import 'knowledge_service.dart';
import 'local_models.dart';
import 'local_store.dart';
import 'search_service.dart';
import 'translation_service.dart';

/// A local, in-process replacement for the former HTTP API client.
///
/// Existing feature screens keep their familiar method names while all data
/// access goes directly to SQLite and the local AI/translation services.
class LocalApi {
  LocalApi({
    required this.store,
    required this.importService,
    required this.translationService,
    required this.knowledgeService,
    required this.searchService,
    required this.assistantService,
    required this.backupService,
    required this.aiSettings,
  });

  final LocalStore store;
  final ImportService importService;
  final TranslationService translationService;
  final KnowledgeService knowledgeService;
  final SearchService searchService;
  final AssistantService assistantService;
  final BackupService backupService;
  final AiSettingsService aiSettings;

  String get baseUrl => '';
  String absoluteUrl(String? path) => path ?? '';
  Future<bool> health() async => true;

  Future<Map<String, dynamic>> info() async => {
    'name': '古文阅读器',
    'version': '0.1.0',
    'mode': 'local',
    'auth_required': false,
    'supported_formats': ['txt', 'epub', 'docx', 'pdf'],
    'capabilities': {
      'epub': true,
      'pdf_text': true,
      'pdf_ocr': false,
      'docx': true,
      'txt': true,
      'fts5': store.database.ftsAvailable,
      'sync': false,
      'ai': (await aiSettings.models()).any((model) => model.enabled),
      'backup': true,
    },
  };

  Future<List<Book>> books({String? query}) => store.listBooks(query: query);

  Future<Book> book(String bookId) async {
    final book = await store.getBook(bookId);
    if (book == null) throw LocalException('书籍不存在');
    return book;
  }

  Future<List<ChapterSummary>> chapters(String bookId) =>
      store.listChapters(bookId);

  Future<ChapterContent> chapterContent(String chapterId) async {
    final content = await store.chapterContent(chapterId);
    if (content == null) throw LocalException('章节不存在');
    return content;
  }

  Future<TranslationStatus> translationStatus(String chapterId) =>
      store.translationStatus(chapterId);

  Future<TaskInfo> translateChapter(
    String chapterId, {
    bool retranslate = false,
  }) => translationService.startChapterTranslation(
    chapterId,
    retranslate: retranslate,
  );

  Future<TaskInfo> task(String taskId) async {
    final task = await store.getTask(taskId);
    if (task == null) throw LocalException('任务不存在');
    return task;
  }

  Future<List<TaskInfo>> tasks() => store.tasks();

  Future<TaskInfo> cancelTask(String taskId) async {
    await store.cancelTask(taskId);
    return task(taskId);
  }

  Future<Map<String, dynamic>> saveProgress({
    required String bookId,
    required String deviceId,
    String? chapterId,
    String? paragraphId,
    String? sentenceId,
    required double positionRatio,
  }) async {
    final progress = ReaderProgress(
      bookId: bookId,
      chapterId: chapterId,
      paragraphId: paragraphId,
      sentenceId: sentenceId,
      positionRatio: positionRatio,
    );
    await store.saveProgress(progress);
    return progress.toJson();
  }

  Future<Map<String, dynamic>?> progress(String bookId, String deviceId) async {
    final value = await store.progress(bookId);
    return value?.toJson();
  }

  Future<List<Annotation>> annotations({String? bookId}) =>
      store.annotations(bookId: bookId);

  Future<Annotation> createAnnotation(Map<String, dynamic> payload) =>
      store.createAnnotation(
        bookId: payload['book_id'] as String,
        content: payload['content'] as String,
        chapterId: payload['chapter_id'] as String?,
        paragraphId: payload['paragraph_id'] as String?,
        sentenceId: payload['sentence_id'] as String?,
        quote: payload['quote'] as String?,
        color: payload['color'] as String? ?? 'amber',
      );

  Future<void> deleteAnnotation(String id) => store.deleteAnnotation(id);

  Future<List<Bookmark>> bookmarks({String? bookId}) =>
      store.bookmarks(bookId: bookId);

  Future<Bookmark> createBookmark(Map<String, dynamic> payload) =>
      store.createBookmark(
        bookId: payload['book_id'] as String,
        chapterId: payload['chapter_id'] as String,
        paragraphId: payload['paragraph_id'] as String?,
        sentenceId: payload['sentence_id'] as String?,
        label: payload['label'] as String?,
        positionRatio: (payload['position_ratio'] as num? ?? 0).toDouble(),
      );

  Future<void> deleteBookmark(String id) => store.deleteBookmark(id);

  Future<Book> importBook({
    required String filename,
    required List<int> bytes,
    String? title,
    String? author,
    String? dynasty,
    String? category,
    String? tags,
    String? description,
  }) {
    return importService.importBytes(
      filename: filename,
      bytes: Uint8List.fromList(bytes),
      title: title,
      author: author,
      dynasty: dynasty,
      category: category,
      tags: tags,
      description: description,
    );
  }

  Future<List<HistoricalEntity>> entities({
    String? query,
    String? kind,
    String? status,
  }) => knowledgeService.listEntities(query: query, kind: kind, status: status);

  Future<HistoricalEntity> entity(String id) async {
    final value = await knowledgeService.entity(id);
    if (value == null) throw LocalException('人物不存在');
    return value;
  }

  Future<List<HistoricalEvent>> events({
    String? query,
    bool includeExtracted = true,
  }) => knowledgeService.listEvents(
    query: query,
    includeExtracted: includeExtracted,
  );

  Future<HistoricalEvent> event(String id) async {
    final value = await knowledgeService.event(id);
    if (value == null) throw LocalException('事件不存在');
    return value;
  }

  Future<AssistantAnswer> assistant({
    required String question,
    String? bookId,
    String? chapterId,
    String? paragraphId,
    String? sentenceId,
    String? sessionId,
  }) {
    return assistantService.ask(
      question: question,
      bookId: bookId,
      chapterId: chapterId,
      paragraphId: paragraphId,
      sentenceId: sentenceId,
      sessionId: sessionId,
    );
  }

  Future<LocalSearchResults> search(
    String query, {
    String scope = 'all',
    String? bookId,
  }) => searchService.search(query, scope: scope, bookId: bookId);
}

class LocalException implements Exception {
  LocalException(this.message);
  final String message;
  @override
  String toString() => message;
}
