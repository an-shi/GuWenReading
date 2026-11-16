import 'package:flutter_test/flutter_test.dart';
import 'package:guwenreading_mobile/core/api/api_client.dart';
import 'package:guwenreading_mobile/core/db/local_database.dart';
import 'package:guwenreading_mobile/data/models.dart';
import 'package:guwenreading_mobile/data/repositories/library_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Minimal offline API surface: all network calls fail with OfflineException.
class _OfflineApi extends ApiClient {
  _OfflineApi() : super(baseUrl: 'http://127.0.0.1:1/api/v1');

  @override
  Future<List<Book>> books({String? query}) async => throw OfflineException();

  @override
  Future<List<ChapterSummary>> chapters(String bookId) async => throw OfflineException();

  @override
  Future<ChapterContent> chapterContent(String chapterId) async => throw OfflineException();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  test('offline bookshelf falls back to local cache', () async {
    final db = await LocalDatabase.open();
    await db.putCache('books:list', [
      {
        'id': 'book-1',
        'title': '史记',
        'author': '司马迁',
        'source_format': 'txt',
        'chapter_count': 3,
        'sentence_count': 16,
        'translated_sentence_count': 11,
        'translation_percent': 68.75,
      },
    ]);
    final repository = LibraryRepository(db: db, api: _OfflineApi());
    final snapshot = await repository.loadBooks();
    expect(snapshot.fromCache, isTrue);
    expect(snapshot.books.single.title, '史记');
    await db.close();
  });

  test('local annotations, bookmarks and progress persist', () async {
    final db = await LocalDatabase.open();
    await db.upsertAnnotation(
      Annotation(
        id: 'a1',
        bookId: 'book-1',
        chapterId: 'c1',
        content: '批注',
        quote: '黄帝者',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ),
      dirty: true,
    );
    await db.upsertBookmark(
      Bookmark(
        id: 'b1',
        bookId: 'book-1',
        chapterId: 'c1',
        label: '书签',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ),
      dirty: true,
    );
    await db.saveProgress(const ReaderProgress(
      bookId: 'book-1',
      chapterId: 'c1',
      paragraphId: 'p1',
      paragraphIndex: 2,
      positionRatio: 0.4,
    ));
    expect((await db.annotations(bookId: 'book-1')).single.content, '批注');
    expect((await db.bookmarks(bookId: 'book-1')).single.label, '书签');
    expect((await db.progress('book-1'))!.paragraphIndex, 2);
    expect(await db.pendingWriteCount(), 2);
    await db.close();
  });

  test('direct translations merge without replacing server translations', () async {
    final db = await LocalDatabase.open();
    await db.putCache('chapter:c1', {
      'book': {'id': 'book-1', 'title': '史记'},
      'chapter': {'id': 'c1', 'ordinal': 0, 'title': '五帝本纪'},
      'paragraphs': [
        {
          'id': 'p1',
          'ordinal': 0,
          'original_text': '甲。乙。',
          'sentences': [
            {
              'id': 's1',
              'ordinal': 0,
              'original_text': '甲。',
              'translation_state': 'completed',
              'translation': {'id': 't1', 'sentence_id': 's1', 'text': '服务器译文。', 'origin': 'ai'},
            },
            {
              'id': 's2',
              'ordinal': 1,
              'original_text': '乙。',
              'translation_state': 'pending',
            },
          ],
        },
      ],
    });
    final repository = LibraryRepository(db: db, api: _OfflineApi());
    await repository.saveDirectTranslations('c1', {'s1': '本地覆盖', 's2': '直连译文。'});
    final content = await repository.chapterContent('c1');
    final sentences = content.paragraphs.single.sentences;
    expect(sentences[0].translation!.text, '服务器译文。');
    expect(sentences[1].translation!.text, '直连译文。');
    await db.close();
  });
}
