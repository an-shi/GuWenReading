import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../data/models.dart';
import 'app_database.dart';
import 'document_parser.dart';
import 'local_store.dart';
import 'text_utils.dart';

class ImportService {
  ImportService({required this.store, required this.paths});

  final LocalStore store;
  final AppPaths paths;

  Future<Book> importBytes({
    required String filename,
    required Uint8List bytes,
    String? title,
    String? author,
    String? dynasty,
    String? category,
    String? tags,
    String? description,
    void Function(double progress, String message)? onProgress,
  }) async {
    if (bytes.isEmpty) throw DocumentParseException('文件为空');
    onProgress?.call(0.02, '正在校验文件');
    final hash = sha256.convert(bytes).toString();
    final existing = await store.db.query(
      'books',
      where: 'source_hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final book = await store.getBook(existing.first['id'] as String);
      if (book != null) {
        onProgress?.call(1, '书籍已存在，直接打开');
        return book;
      }
    }

    onProgress?.call(0.05, '正在准备解析文件');
    final parsed = await parseDocument(
      filename: filename,
      bytes: bytes,
      onProgress: (progress, message) =>
          onProgress?.call(0.06 + progress * 0.28, message),
    );
    onProgress?.call(0.34, '已解析 ${parsed.chapters.length} 个章节，正在保存原始文件');

    final bookId = newLocalId('book');
    final bookDir = Directory(p.join(paths.booksDir.path, bookId));
    String? coverPath;
    final originalPath = p.join(
      bookDir.path,
      'original${p.extension(filename).toLowerCase()}',
    );
    try {
      if (!await bookDir.exists()) await bookDir.create(recursive: true);
      await File(originalPath).writeAsBytes(bytes, flush: true);
      if (parsed.cover != null && parsed.cover!.isNotEmpty) {
        coverPath = p.join(paths.coversDir.path, '$bookId.img');
        await File(coverPath).writeAsBytes(parsed.cover!, flush: true);
      }
    } catch (error) {
      if (await bookDir.exists()) await bookDir.delete(recursive: true);
      throw DocumentParseException('保存原始文件失败：$error');
    }

    final now = nowIso();
    final effectiveTitle = (title?.trim().isNotEmpty ?? false)
        ? title!.trim()
        : parsed.metadata.title;
    final effectiveAuthor = (author?.trim().isNotEmpty ?? false)
        ? author!.trim()
        : parsed.metadata.author;
    final effectiveDynasty = (dynasty?.trim().isNotEmpty ?? false)
        ? dynasty!.trim()
        : parsed.metadata.dynasty;
    final tagList = (tags ?? '')
        .split(RegExp(r'[,，、]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    var chapterCount = 0;
    var paragraphCount = 0;
    var sentenceCount = 0;
    final totalChapters = parsed.chapters.length;
    final totalParagraphs = parsed.chapters.fold<int>(
      0,
      (sum, chapter) => sum + chapter.paragraphs.length,
    );
    var processedParagraphs = 0;
    var lastReported = 0.36;
    onProgress?.call(0.36, '正在写入章节与句子');
    try {
      await store.db.transaction((txn) async {
        await txn.insert('books', {
          'id': bookId,
          'title': effectiveTitle,
          'author': effectiveAuthor,
          'dynasty': effectiveDynasty,
          'category': (category ?? '').trim().isEmpty ? null : category!.trim(),
          'description': (description ?? '').trim().isEmpty
              ? parsed.metadata.description
              : description!.trim(),
          'tags': tagList.isEmpty ? '[]' : _jsonList(tagList),
          'source_format': parsed.format,
          'source_filename': filename,
          'source_hash': hash,
          'original_path': originalPath,
          'cover_path': coverPath,
          'file_size': bytes.length,
          'status': 'ready',
          'created_at': now,
          'updated_at': now,
        });
        var chapterOrdinal = 0;
        for (final chapter in parsed.chapters) {
          final chapterId = newLocalId('ch');
          await txn.insert('chapters', {
            'id': chapterId,
            'book_id': bookId,
            'ordinal': chapterOrdinal,
            'title': chapter.title,
            'paragraph_count': chapter.paragraphs.length,
            'sentence_count': 0,
            'created_at': now,
          });
          var paragraphOrdinal = 0;
          var chapterSentenceCount = 0;
          var pendingInBatch = 0;
          var batch = txn.batch();
          for (final paragraphText in chapter.paragraphs) {
            final paragraphId = newLocalId('p');
            batch.insert('paragraphs', {
              'id': paragraphId,
              'book_id': bookId,
              'chapter_id': chapterId,
              'ordinal': paragraphOrdinal,
              'original_text': paragraphText,
              'start_offset': 0,
              'end_offset': paragraphText.length,
            });
            final spans = splitSentences(paragraphText);
            for (final span in spans) {
              batch.insert('sentences', {
                'id': newLocalId('s'),
                'book_id': bookId,
                'chapter_id': chapterId,
                'paragraph_id': paragraphId,
                'ordinal': chapterSentenceCount,
                'original_text': span.text,
                'start_offset': span.start,
                'end_offset': span.end,
                'translation_state': 'pending',
                'needs_review': span.needsReview ? 1 : 0,
                'created_at': now,
              });
              chapterSentenceCount += 1;
            }
            paragraphOrdinal += 1;
            processedParagraphs += 1;
            pendingInBatch += 1;
            if (pendingInBatch >= 200) {
              await batch.commit(noResult: true);
              batch = txn.batch();
              pendingInBatch = 0;
            }
            final writeProgress = totalParagraphs == 0
                ? 0.80
                : 0.36 + 0.44 * (processedParagraphs / totalParagraphs);
            if (writeProgress - lastReported >= 0.01 ||
                processedParagraphs == totalParagraphs) {
              lastReported = writeProgress;
              onProgress?.call(
                writeProgress,
                '正在写入第 ${chapterOrdinal + 1}/$totalChapters 章 · '
                '$processedParagraphs/$totalParagraphs 段',
              );
            }
          }
          if (pendingInBatch > 0) {
            await batch.commit(noResult: true);
          }
          await txn.update(
            'chapters',
            {'sentence_count': chapterSentenceCount},
            where: 'id = ?',
            whereArgs: [chapterId],
          );
          chapterOrdinal += 1;
          chapterCount += 1;
          paragraphCount += chapter.paragraphs.length;
          sentenceCount += chapterSentenceCount;
        }
        await txn.update(
          'books',
          {
            'chapter_count': chapterCount,
            'paragraph_count': paragraphCount,
            'sentence_count': sentenceCount,
            'translated_sentence_count': 0,
          },
          where: 'id = ?',
          whereArgs: [bookId],
        );
      });
    } catch (error) {
      if (await bookDir.exists()) await bookDir.delete(recursive: true);
      if (error is DocumentParseException) rethrow;
      throw DocumentParseException('写入书籍数据失败：$error');
    }
    onProgress?.call(0.84, '正在建立全文检索索引');
    await store.importSentencesSearchIndex(
      bookId,
      onProgress: (done, total) {
        final fraction = total == 0 ? 1.0 : done / total;
        onProgress?.call(0.84 + 0.14 * fraction, '正在建立全文检索索引 $done/$total');
      },
    );
    onProgress?.call(0.99, '正在完成导入');
    onProgress?.call(1, '导入完成');
    final book = await store.getBook(bookId);
    if (book == null) throw DocumentParseException('书籍写入失败');
    return book;
  }

  String _jsonList(List<String> values) => jsonEncode(values);
}

// Keep the sqflite import used for API symmetry in callers that construct a
// transaction directly.
typedef ImportTransaction = Transaction;
