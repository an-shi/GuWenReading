import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guwenreader/core/local/app_database.dart';
import 'package:guwenreader/core/local/backup_service.dart';
import 'package:guwenreader/core/local/import_service.dart';
import 'package:guwenreader/core/local/local_store.dart';
import 'package:guwenreader/core/local/search_service.dart';
import 'package:guwenreader/data/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late LocalStore store;
  late ImportService importer;
  late SearchService search;

  setUp(() async {
    database = await AppDatabase.openInMemory();
    store = LocalStore(database);
    importer = ImportService(store: store, paths: database.paths);
    search = SearchService(store);
  });

  tearDown(() async {
    await database.close();
  });

  test('imports TXT into chapters, paragraphs and sentences', () async {
    final text = '''
史记
作者：司马迁
卷一 五帝本纪
黄帝者，少典之子，姓公孙，名曰轩辕。生而神灵，弱而能言。
轩辕之时，神农氏世衰。
卷二 夏本纪
禹之父曰鲧。鲧之父曰帝颛顼。
''';
    final book = await importer.importBytes(
      filename: '史记.txt',
      bytes: utf8.encode(text),
    );
    expect(book.title, '史记');
    expect(book.author, '司马迁');
    expect(book.chapterCount, greaterThanOrEqualTo(2));
    expect(book.sentenceCount, greaterThan(0));

    final chapters = await store.listChapters(book.id);
    final content = await store.chapterContent(
      chapters.firstWhere((chapter) => chapter.title.contains('五帝')).id,
    );
    expect(content, isNotNull);
    expect(content!.paragraphs, isNotEmpty);
    expect(
      content.paragraphs.first.sentences.first.originalText,
      contains('黄帝'),
    );

    final results = await search.search('轩辕');
    expect(results.sentences, isNotEmpty);
    expect(results.sentences.first.bookTitle, '史记');
  });

  test('manual translation is protected and retranslation becomes a review candidate', () async {
    final book = await importer.importBytes(
      filename: '史记.txt',
      bytes: utf8.encode('卷一 五帝本纪\n黄帝者，少典之子。\n'),
    );
    final chapters = await store.listChapters(book.id);
    final content = await store.chapterContent(chapters.first.id);
    final sentence = content!.paragraphs.first.sentences.first;

    await store.upsertTranslation(
      sentenceId: sentence.id,
      text: '黄帝是少典的儿子。',
      origin: 'manual',
    );
    await store.upsertTranslation(
      sentenceId: sentence.id,
      text: 'AI 新译文。',
      origin: 'ai',
    );

    final refreshed = await store.chapterContent(chapters.first.id);
    final updated = refreshed!.paragraphs.first.sentences.first;
    expect(updated.translation!.text, '黄帝是少典的儿子。');
    expect(updated.translation!.isManual, isTrue);
    expect(updated.pendingReview, isNotNull);
    expect(updated.pendingReview!.candidateText, 'AI 新译文。');

    await store.resolveReview(updated.pendingReview!.id, true);
    final accepted = await store.chapterContent(chapters.first.id);
    expect(
      accepted!.paragraphs.first.sentences.first.translation!.text,
      'AI 新译文。',
    );
  });

  test('annotations, bookmarks and progress persist locally', () async {
    final book = await importer.importBytes(
      filename: '史记.txt',
      bytes: utf8.encode('卷一 五帝本纪\n黄帝者，少典之子。\n'),
    );
    final chapter = (await store.listChapters(book.id)).first;
    final content = await store.chapterContent(chapter.id);
    final sentence = content!.paragraphs.first.sentences.first;

    await store.createAnnotation(
      bookId: book.id,
      chapterId: chapter.id,
      paragraphId: content.paragraphs.first.id,
      sentenceId: sentence.id,
      quote: sentence.originalText,
      content: '此处值得注意。',
    );
    await store.createBookmark(
      bookId: book.id,
      chapterId: chapter.id,
      paragraphId: content.paragraphs.first.id,
      label: '读到这里',
    );
    await store.saveProgress(
      ReaderProgress(
        bookId: book.id,
        chapterId: chapter.id,
        paragraphId: content.paragraphs.first.id,
        paragraphIndex: 0,
        positionRatio: 0.4,
      ),
    );

    expect(
      (await store.annotations(bookId: book.id)).single.content,
      '此处值得注意。',
    );
    expect((await store.bookmarks(bookId: book.id)).single.label, '读到这里');
    expect((await store.progress(book.id))!.positionRatio, 0.4);
  });

  test('local backup contains database and can be listed', () async {
    await importer.importBytes(
      filename: '史记.txt',
      bytes: utf8.encode('卷一 五帝本纪\n黄帝者，少典之子。\n'),
    );
    final service = BackupService(store: store, paths: database.paths);
    final info = await service.createBackup();
    expect(info.filename, startsWith('古文阅读器备份-'));
    expect(info.size, greaterThan(0));
    final list = await service.listBackups();
    expect(list.map((item) => item.filename), contains(info.filename));
  });

  test('DOCX and EPUB imports preserve chapter text', () async {
    final docx = _docxBytes(['卷一 五帝本纪', '黄帝者，少典之子，姓公孙，名曰轩辕。']);
    final docxBook = await importer.importBytes(
      filename: '史记.docx',
      bytes: docx,
    );
    expect(docxBook.sourceFormat, 'docx');
    final docxContent = await store.chapterContent(
      (await store.listChapters(docxBook.id)).first.id,
    );
    expect(
      docxContent!.paragraphs.map((p) => p.originalText).join(),
      contains('黄帝'),
    );

    final epub = _epubBytes(
      title: '史记',
      author: '司马迁',
      chapterTitle: '卷一 五帝本纪',
      paragraph: '黄帝者，少典之子，姓公孙，名曰轩辕。',
    );
    final epubBook = await importer.importBytes(
      filename: '史记.epub',
      bytes: epub,
    );
    expect(epubBook.sourceFormat, 'epub');
    expect(epubBook.title, '史记');
    final epubContent = await store.chapterContent(
      (await store.listChapters(epubBook.id)).first.id,
    );
    expect(
      epubContent!.paragraphs.map((p) => p.originalText).join(),
      contains('黄帝'),
    );
  });

  test('restores a backup into the live local database', () async {
    final book = await importer.importBytes(
      filename: '史记.txt',
      bytes: utf8.encode('卷一 五帝本纪\n黄帝者，少典之子。\n'),
    );
    final service = BackupService(store: store, paths: database.paths);
    final info = await service.createBackup();
    await store.createAnnotation(bookId: book.id, content: '备份之后新增的批注');
    expect((await store.annotations(bookId: book.id)), isNotEmpty);
    await service.restoreBackup(info.path);
    expect((await store.annotations(bookId: book.id)), isEmpty);
    expect(await store.getBook(book.id), isNotNull);
  });
}

Uint8List _docxBytes(List<String> paragraphs) {
  final xml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    ${paragraphs.map((text) => '<w:p><w:r><w:t>${_escapeXml(text)}</w:t></w:r></w:p>').join('\n')}
  </w:body>
</w:document>''';
  final archive = Archive();
  final bytes = utf8.encode(xml);
  archive.addFile(ArchiveFile('word/document.xml', bytes.length, bytes));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List _epubBytes({
  required String title,
  required String author,
  required String chapterTitle,
  required String paragraph,
}) {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''');
  add('OEBPS/content.opf', '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title><dc:creator>$author</dc:creator><dc:language>zh</dc:language>
  </metadata>
  <manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest>
  <spine><itemref idref="chapter"/></spine>
</package>''');
  add('OEBPS/chapter.xhtml', '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>$chapterTitle</title></head>
<body><h1>$chapterTitle</h1><p>${_escapeXml(paragraph)}</p></body></html>''');
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _escapeXml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
