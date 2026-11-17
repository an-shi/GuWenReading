import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local/local_api.dart';
import '../../core/local/local_store.dart';
import '../../core/providers.dart';
import '../models.dart';

class ReaderRepository {
  ReaderRepository({required this.store, required this.api});

  final LocalStore store;
  final LocalApi api;

  Future<ChapterContent> chapter(String chapterId, {bool force = false}) =>
      api.chapterContent(chapterId);

  Future<TaskInfo> startTranslation(
    String chapterId, {
    bool retranslate = false,
  }) => api.translateChapter(chapterId, retranslate: retranslate);

  Future<TaskInfo> task(String taskId) => api.task(taskId);

  Future<TaskInfo> cancelTask(String taskId) => api.cancelTask(taskId);

  Future<List<Annotation>> annotations(String bookId) =>
      store.annotations(bookId: bookId);

  Future<Annotation> createAnnotation({
    required String bookId,
    required String content,
    String? chapterId,
    String? paragraphId,
    String? sentenceId,
    String? quote,
    String color = 'amber',
  }) {
    return store.createAnnotation(
      bookId: bookId,
      content: content,
      chapterId: chapterId,
      paragraphId: paragraphId,
      sentenceId: sentenceId,
      quote: quote,
      color: color,
    );
  }

  Future<void> deleteAnnotation(Annotation annotation) =>
      store.deleteAnnotation(annotation.id);

  Future<List<Bookmark>> bookmarks(String bookId) =>
      store.bookmarks(bookId: bookId);

  Future<Bookmark> createBookmark({
    required String bookId,
    required String chapterId,
    String? paragraphId,
    String? sentenceId,
    String? label,
    double positionRatio = 0,
  }) {
    return store.createBookmark(
      bookId: bookId,
      chapterId: chapterId,
      paragraphId: paragraphId,
      sentenceId: sentenceId,
      label: label,
      positionRatio: positionRatio,
    );
  }

  Future<void> deleteBookmark(Bookmark bookmark) =>
      store.deleteBookmark(bookmark.id);

  Future<ReaderProgress?> progress(String bookId) => store.progress(bookId);

  Future<void> saveProgress(ReaderProgress progress) =>
      store.saveProgress(progress);

  Future<int> flushPending() async => 0;
}

final readerRepositoryProvider = Provider<ReaderRepository>((ref) {
  return ReaderRepository(
    store: ref.watch(localStoreProvider),
    api: ref.watch(localApiProvider),
  );
});
