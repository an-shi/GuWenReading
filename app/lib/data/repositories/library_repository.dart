import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local/local_api.dart';
import '../../core/local/local_store.dart';
import '../../core/providers.dart';
import '../models.dart';

class BookshelfSnapshot {
  const BookshelfSnapshot({required this.books, required this.fromCache});
  final List<Book> books;
  final bool fromCache;
}

class LibraryRepository {
  LibraryRepository({required this.store, required this.api});

  final LocalStore store;
  final LocalApi api;

  Future<BookshelfSnapshot> loadBooks({String? query}) async {
    final books = await api.books(query: query);
    return BookshelfSnapshot(books: books, fromCache: true);
  }

  Future<Book> book(String bookId) => api.book(bookId);

  Future<List<ChapterSummary>> chapters(String bookId, {bool force = false}) =>
      api.chapters(bookId);

  Future<ChapterContent> chapterContent(
    String chapterId, {
    bool force = false,
  }) => api.chapterContent(chapterId);

  Future<ChapterContent> mergeLocalTranslations(ChapterContent content) async =>
      content;

  Future<void> saveDirectTranslations(
    String chapterId,
    Map<String, String> translations,
  ) async {
    for (final entry in translations.entries) {
      await store.upsertTranslation(
        sentenceId: entry.key,
        text: entry.value,
        origin: 'manual',
      );
    }
  }

  Future<int> downloadBook(
    String bookId, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final chapters = await api.chapters(bookId);
    onProgress?.call(chapters.length, chapters.length);
    return chapters.length;
  }

  Future<bool> isDownloaded(String bookId) async => true;

  Future<Book> importBook({
    required String filename,
    required List<int> bytes,
    String? title,
    String? author,
    String? dynasty,
    String? category,
    String? tags,
  }) {
    return api.importBook(
      filename: filename,
      bytes: bytes,
      title: title,
      author: author,
      dynasty: dynasty,
      category: category,
      tags: tags,
    );
  }

  Future<AssistantAnswer> assistant({
    required String question,
    String? bookId,
    String? chapterId,
    String? paragraphId,
    String? sentenceId,
    String? sessionId,
  }) {
    return api.assistant(
      question: question,
      bookId: bookId,
      chapterId: chapterId,
      paragraphId: paragraphId,
      sentenceId: sentenceId,
      sessionId: sessionId,
    );
  }

  Future<int> cachedBookCount() async => (await api.books()).length;

  Future<void> clearCache() async {}
}

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(
    store: ref.watch(localStoreProvider),
    api: ref.watch(localApiProvider),
  );
});
