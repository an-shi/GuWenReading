import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/local/local_models.dart';
import '../core/providers.dart';
import '../core/storage/settings_controller.dart';
import '../data/models.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/reader_repository.dart';

export '../core/providers.dart'
    show
        localApiProvider,
        localStoreProvider,
        aiSettingsProvider,
        budgetServiceProvider,
        importServiceProvider,
        translationServiceProvider,
        knowledgeServiceProvider,
        searchServiceProvider,
        assistantServiceProvider,
        backupServiceProvider,
        taskRecoveryServiceProvider;
export '../data/repositories/library_repository.dart'
    show BookshelfSnapshot, LibraryRepository, libraryRepositoryProvider;
export '../data/repositories/reader_repository.dart'
    show ReaderRepository, readerRepositoryProvider;

final bookshelfProvider =
    AsyncNotifierProvider<BookshelfController, BookshelfSnapshot>(
      BookshelfController.new,
    );

class BookshelfController extends AsyncNotifier<BookshelfSnapshot> {
  String _query = '';

  @override
  Future<BookshelfSnapshot> build() async {
    return ref.watch(libraryRepositoryProvider).loadBooks();
  }

  Future<void> refresh({String? query}) async {
    if (query != null) _query = query;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() {
      return ref.read(libraryRepositoryProvider).loadBooks(query: _query);
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
    void Function(double progress, String message)? onProgress,
  }) async {
    final book = await ref
        .read(libraryRepositoryProvider)
        .importBook(
          filename: filename,
          bytes: bytes,
          title: title,
          author: author,
          dynasty: dynasty,
          category: category,
          tags: tags,
          onProgress: onProgress,
        );
    await refresh();
    return book;
  }
}

final bookProvider = FutureProvider.family<Book, String>((ref, bookId) async {
  return ref.watch(libraryRepositoryProvider).book(bookId);
});

final chaptersProvider = FutureProvider.family<List<ChapterSummary>, String>((
  ref,
  bookId,
) async {
  return ref.watch(libraryRepositoryProvider).chapters(bookId);
});

final chapterContentProvider = FutureProvider.family<ChapterContent, String>((
  ref,
  chapterId,
) async {
  return ref.watch(libraryRepositoryProvider).chapterContent(chapterId);
});

final annotationsProvider = FutureProvider.family<List<Annotation>, String>((
  ref,
  bookId,
) async {
  return ref.watch(readerRepositoryProvider).annotations(bookId);
});

final bookmarksProvider = FutureProvider.family<List<Bookmark>, String>((
  ref,
  bookId,
) async {
  return ref.watch(readerRepositoryProvider).bookmarks(bookId);
});

final progressProvider = FutureProvider.family<ReaderProgress?, String>((
  ref,
  bookId,
) async {
  return ref.watch(readerRepositoryProvider).progress(bookId);
});

final tasksProvider = AsyncNotifierProvider<TasksController, List<TaskInfo>>(
  TasksController.new,
);

final aiUsageSummaryProvider = FutureProvider<AiUsageSummary>((ref) {
  return ref.watch(localStoreProvider).aiUsageSummary();
});

class TasksController extends AsyncNotifier<List<TaskInfo>> {
  @override
  Future<List<TaskInfo>> build() async {
    return ref.watch(localStoreProvider).tasks();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(localStoreProvider).tasks());
  }

  Future<void> cancel(String taskId) async {
    await ref.read(localStoreProvider).cancelTask(taskId);
    await refresh();
  }
}

final entitiesProvider = FutureProvider.family<List<HistoricalEntity>, String>((
  ref,
  query,
) async {
  return ref.watch(knowledgeServiceProvider).listEntities(query: query);
});

final entityProvider = FutureProvider.family<HistoricalEntity, String>((
  ref,
  id,
) async {
  final entity = await ref.watch(knowledgeServiceProvider).entity(id);
  if (entity == null) throw StateError('人物不存在');
  return entity;
});

final eventsProvider = FutureProvider.family<List<HistoricalEvent>, String>((
  ref,
  query,
) async {
  return ref.watch(knowledgeServiceProvider).listEvents(query: query);
});

final eventProvider = FutureProvider.family<HistoricalEvent, String>((
  ref,
  id,
) async {
  final event = await ref.watch(knowledgeServiceProvider).event(id);
  if (event == null) throw StateError('事件不存在');
  return event;
});

final graphProvider = FutureProvider.family<LocalGraphData, String>((
  ref,
  centerId,
) async {
  return ref
      .watch(knowledgeServiceProvider)
      .graph(centerId: centerId.isEmpty ? null : centerId);
});

final timelineProvider = FutureProvider<List<HistoricalEvent>>((ref) async {
  return ref.watch(knowledgeServiceProvider).listEvents();
});

final systemInfoProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(localApiProvider).info();
});

final settingsRevisionProvider = Provider<int>((ref) {
  final settings = ref.watch(settingsProvider);
  return Object.hash(
    settings.themeMode,
    settings.fontSize,
    settings.lineHeight,
  );
});
