import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/reader_repository.dart';
import '../core/storage/settings_controller.dart';

export 'data/repositories/library_repository.dart' show BookshelfSnapshot, LibraryRepository, libraryRepositoryProvider;
export 'data/repositories/reader_repository.dart' show ReaderRepository, readerRepositoryProvider;
export 'data/services/direct_ai_service.dart' show DirectAiService, directAiServiceProvider;

final bookshelfProvider = AsyncNotifierProvider<BookshelfController, BookshelfSnapshot>(
  BookshelfController.new,
);

class BookshelfController extends AsyncNotifier<BookshelfSnapshot> {
  String _query = '';

  @override
  Future<BookshelfSnapshot> build() async {
    final repository = ref.watch(libraryRepositoryProvider);
    return repository.loadBooks();
  }

  Future<void> refresh({String? query}) async {
    if (query != null) _query = query;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() {
      final repository = ref.read(libraryRepositoryProvider);
      return repository.loadBooks(query: _query);
    });
  }

  Future<Book> importBook({
    required String filename,
    required List<int> bytes,
    String? title,
    String? author,
    String? dynasty,
    String? category,
    String? tags,
  }) async {
    final repository = ref.read(libraryRepositoryProvider);
    final book = await repository.importBook(
      filename: filename,
      bytes: bytes,
      title: title,
      author: author,
      dynasty: dynasty,
      category: category,
      tags: tags,
    );
    await refresh();
    return book;
  }
}

final bookProvider = FutureProvider.family<Book, String>((ref, bookId) async {
  return ref.watch(libraryRepositoryProvider).book(bookId);
});

final chaptersProvider = FutureProvider.family<List<ChapterSummary>, String>((ref, bookId) async {
  return ref.watch(libraryRepositoryProvider).chapters(bookId);
});

final chapterContentProvider = FutureProvider.family<ChapterContent, String>((ref, chapterId) async {
  return ref.watch(libraryRepositoryProvider).chapterContent(chapterId);
});

final annotationsProvider = FutureProvider.family<List<Annotation>, String>((ref, bookId) async {
  return ref.watch(readerRepositoryProvider).annotations(bookId);
});

final bookmarksProvider = FutureProvider.family<List<Bookmark>, String>((ref, bookId) async {
  return ref.watch(readerRepositoryProvider).bookmarks(bookId);
});

final progressProvider = FutureProvider.family<ReaderProgress?, String>((ref, bookId) async {
  return ref.watch(readerRepositoryProvider).progress(bookId);
});

final tasksProvider = AsyncNotifierProvider<TasksController, List<TaskInfo>>(TasksController.new);

class TasksController extends AsyncNotifier<List<TaskInfo>> {
  @override
  Future<List<TaskInfo>> build() async {
    return ref.watch(libraryRepositoryProvider).api.tasks();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(libraryRepositoryProvider).api.tasks());
  }

  Future<void> cancel(String taskId) async {
    await ref.read(libraryRepositoryProvider).api.cancelTask(taskId);
    await refresh();
  }
}

final entitiesProvider = FutureProvider.family<List<HistoricalEntity>, String>((ref, query) async {
  return ref.watch(libraryRepositoryProvider).api.entities(query: query);
});

final entityProvider = FutureProvider.family<HistoricalEntity, String>((ref, id) async {
  return ref.watch(libraryRepositoryProvider).api.entity(id);
});

final eventsProvider = FutureProvider.family<List<HistoricalEvent>, String>((ref, query) async {
  return ref.watch(libraryRepositoryProvider).api.events(query: query);
});

final eventProvider = FutureProvider.family<HistoricalEvent, String>((ref, id) async {
  return ref.watch(libraryRepositoryProvider).api.event(id);
});

final systemInfoProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(apiClientProvider).info();
});

final deviceIdProvider = Provider<String>((ref) {
  return ref.watch(settingsProvider).deviceId;
});
