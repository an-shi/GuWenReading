import 'local_models.dart';
import 'local_store.dart';

class SearchService {
  SearchService(this.store);
  final LocalStore store;

  Future<LocalSearchResults> search(
    String query, {
    String scope = 'all',
    String? bookId,
  }) async {
    final value = query.trim();
    if (value.isEmpty) return const LocalSearchResults();
    final sentenceHits = <SearchSentenceHit>[];
    final seen = <String>{};
    final ftsRows = await store.searchFts(value, bookId: bookId, scope: scope);
    for (final row in ftsRows) {
      final sentenceId = row['sentence_id'] as String?;
      final docType = row['doc_type'] as String? ?? 'original';
      if (sentenceId == null || !seen.add('$sentenceId:$docType')) continue;
      final titles = await store.bookAndChapterTitles(
        row['book_id'] as String,
        row['chapter_id'] as String,
      );
      final original = await _sentenceOriginal(sentenceId);
      sentenceHits.add(
        SearchSentenceHit(
          sentenceId: sentenceId,
          bookId: row['book_id'] as String,
          bookTitle: titles['book'] ?? '',
          chapterId: row['chapter_id'] as String,
          chapterTitle: titles['chapter'] ?? '',
          text: row['text'] as String? ?? '',
          docType: docType,
          originalText: docType == 'translation' ? original : null,
        ),
      );
    }
    if (sentenceHits.isEmpty) {
      final rows = await store.searchSentencesLike(
        value,
        bookId: bookId,
        scope: scope,
      );
      for (final row in rows) {
        final original = row['original_text'] as String? ?? '';
        final translation = row['translation_text'] as String? ?? '';
        if (scope != 'translation' && original.contains(value)) {
          final key = '${row['sentence_id']}:original';
          if (seen.add(key)) {
            sentenceHits.add(
              SearchSentenceHit(
                sentenceId: row['sentence_id'] as String,
                bookId: row['book_id'] as String,
                bookTitle: row['book_title'] as String? ?? '',
                chapterId: row['chapter_id'] as String,
                chapterTitle: row['chapter_title'] as String? ?? '',
                text: original,
                docType: 'original',
              ),
            );
          }
        }
        if (scope != 'original' &&
            translation.isNotEmpty &&
            translation.contains(value)) {
          final key = '${row['sentence_id']}:translation';
          if (seen.add(key)) {
            sentenceHits.add(
              SearchSentenceHit(
                sentenceId: row['sentence_id'] as String,
                bookId: row['book_id'] as String,
                bookTitle: row['book_title'] as String? ?? '',
                chapterId: row['chapter_id'] as String,
                chapterTitle: row['chapter_title'] as String? ?? '',
                text: translation,
                docType: 'translation',
                originalText: original,
              ),
            );
          }
        }
      }
    }

    final entityRows = await store.db.query(
      'entities',
      where: 'canonical_name LIKE ? OR aliases LIKE ? OR COALESCE(summary,\'\') LIKE ?',
      whereArgs: ['%$value%', '%$value%', '%$value%'],
      orderBy: 'updated_at DESC',
      limit: 50,
    );
    final eventRows = await store.db.query(
      'historical_events',
      where: 'name LIKE ? OR COALESCE(description,\'\') LIKE ? OR COALESCE(time_raw,\'\') LIKE ?',
      whereArgs: ['%$value%', '%$value%', '%$value%'],
      orderBy: 'COALESCE(time_start_year, 999999) ASC',
      limit: 50,
    );

    return LocalSearchResults(
      sentences: sentenceHits,
      entities: [
        for (final row in entityRows)
          SearchEntityHit(
            id: row['id'] as String,
            name: row['canonical_name'] as String,
            kind: row['kind'] as String? ?? 'person',
            dynasty: row['dynasty'] as String?,
            summary: row['summary'] as String?,
            status: row['status'] as String? ?? 'pending',
          ),
      ],
      events: [
        for (final row in eventRows)
          SearchEventHit(
            id: row['id'] as String,
            name: row['name'] as String,
            eventType: row['event_type'] as String? ?? '其他',
            timeRaw: row['time_raw'] as String?,
            timeStartYear: row['time_start_year'] as int?,
            status: row['status'] as String? ?? 'extracted',
          ),
      ],
    );
  }

  Future<String?> _sentenceOriginal(String sentenceId) async {
    final rows = await store.db.query(
      'sentences',
      where: 'id = ?',
      whereArgs: [sentenceId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['original_text'] as String?;
  }
}
