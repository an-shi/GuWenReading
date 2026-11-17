import 'dart:convert';

import '../../data/models.dart';
import 'ai_service.dart';
import 'app_database.dart';
import 'local_models.dart';
import 'local_store.dart';
import 'search_service.dart';

class AssistantService {
  AssistantService({
    required this.store,
    required this.aiSettings,
    required this.client,
    required this.search,
  });

  final LocalStore store;
  final AiSettingsService aiSettings;
  final AiJsonClient client;
  final SearchService search;

  Future<AssistantAnswer> ask({
    required String question,
    String? bookId,
    String? chapterId,
    String? paragraphId,
    String? sentenceId,
    String? sessionId,
  }) async {
    final resolved = await aiSettings.resolve(purpose: 'chat');
    if (resolved == null) throw AiNotConfiguredException();
    ChapterContent? content;
    if (chapterId != null && chapterId.isNotEmpty) {
      content = await store.chapterContent(chapterId);
    }
    final context = _buildContext(content, paragraphId, sentenceId);
    final results = await search.search(question, bookId: bookId);
    final knowledgeContext = _knowledgeContext(results);
    final history = sessionId == null ? '' : await _history(sessionId);
    final prompt = await aiSettings.render('assistant', {
      'book_title': content?.bookTitle ?? '当前书籍',
      'author': content?.bookAuthor ?? '未详',
      'chapter_title': content?.chapterTitle ?? '未指定章节',
      'context': context,
      'knowledge_context': knowledgeContext,
      'history': history,
      'question': question,
    });
    final data = await client.chatJson(
      purpose: 'chat',
      prompt: prompt,
      temperature: 0.3,
    );
    final answerText =
        jsonString(data['answer']) ?? jsonString(data['text']) ?? '';
    final citations = <AssistantCitation>[];
    for (final item in jsonList(data['citations'])) {
      final quote = jsonString(item['quote']);
      citations.add(
        AssistantCitation(
          book: jsonString(item['book']) ?? content?.bookTitle ?? '',
          chapter: jsonString(item['chapter']) ?? content?.chapterTitle ?? '',
          quote: quote,
          note: jsonString(item['note']),
          verified: quote != null && context.contains(quote),
        ),
      );
    }
    final claims = <AssistantClaim>[
      for (final item in jsonList(data['claims']))
        AssistantClaim(
          text: jsonString(item['text']) ?? '',
          kind: jsonString(item['kind']) ?? 'unverified',
        ),
    ];
    final effectiveSession = sessionId ?? newLocalId('chat');
    await _ensureSession(effectiveSession, question, bookId, chapterId);
    await store.db.insert('assistant_messages', {
      'id': newLocalId('msg'),
      'session_id': effectiveSession,
      'role': 'user',
      'content': question,
      'created_at': nowIso(),
    });
    await store.db.insert('assistant_messages', {
      'id': newLocalId('msg'),
      'session_id': effectiveSession,
      'role': 'assistant',
      'content': answerText,
      'citations': jsonEncode([
        for (final citation in citations)
          {
            'book': citation.book,
            'chapter': citation.chapter,
            'quote': citation.quote,
            'note': citation.note,
            'verified': citation.verified,
          },
      ]),
      'claims': jsonEncode([
        for (final claim in claims) {'text': claim.text, 'kind': claim.kind},
      ]),
      'created_at': nowIso(),
    });
    await store.db.update(
      'assistant_sessions',
      {'updated_at': nowIso()},
      where: 'id = ?',
      whereArgs: [effectiveSession],
    );
    return AssistantAnswer(
      answer: answerText,
      citations: citations,
      claims: claims,
      sessionId: effectiveSession,
      model: resolved.label,
    );
  }

  Future<String> explainSentence({
    required String sentenceId,
    String question = '请解释这句话的难词、句式、典故与整体含义。',
  }) async {
    final rows = await store.db.rawQuery(
      '''
      SELECT s.*, p.original_text AS paragraph_text, c.title AS chapter_title,
             b.title AS book_title, b.author AS book_author, t.text AS translation_text
      FROM sentences s
      JOIN paragraphs p ON p.id = s.paragraph_id
      JOIN chapters c ON c.id = s.chapter_id
      JOIN books b ON b.id = s.book_id
      LEFT JOIN translations t ON t.sentence_id = s.id
      WHERE s.id = ?
      ''',
      [sentenceId],
    );
    if (rows.isEmpty) throw AiNotConfiguredException('句子不存在');
    final row = rows.first;
    final prompt = await aiSettings.render('sentence_explain', {
      'book_title': row['book_title'] ?? '',
      'chapter_title': row['chapter_title'] ?? '',
      'original': row['original_text'] ?? '',
      'translation': row['translation_text'] ?? '暂无译文',
      'context': row['paragraph_text'] ?? '',
      'question': question,
    });
    return client.chat(purpose: 'chat', prompt: prompt, temperature: 0.3);
  }

  Future<List<Map<String, Object?>>> sessions() async {
    return store.db.query(
      'assistant_sessions',
      orderBy: 'updated_at DESC',
      limit: 50,
    );
  }

  Future<List<Map<String, Object?>>> messages(String sessionId) async {
    return store.db.query(
      'assistant_messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> deleteSession(String sessionId) async {
    await store.db.delete(
      'assistant_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> _ensureSession(
    String id,
    String question,
    String? bookId,
    String? chapterId,
  ) async {
    final existing = await store.db.query(
      'assistant_sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    await store.db.insert('assistant_sessions', {
      'id': id,
      'title': question.length > 40 ? question.substring(0, 40) : question,
      'book_id': bookId,
      'chapter_id': chapterId,
      'created_at': nowIso(),
      'updated_at': nowIso(),
    });
  }

  Future<String> _history(String sessionId) async {
    final rows = await store.db.query(
      'assistant_messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at DESC',
      limit: 8,
    );
    if (rows.isEmpty) return '';
    final ordered = rows.reversed.toList();
    return ordered
        .map(
          (row) => '${row['role'] == 'user' ? '用户' : '助手'}：${row['content']}',
        )
        .join('\n');
  }

  String _buildContext(
    ChapterContent? content,
    String? paragraphId,
    String? sentenceId,
  ) {
    if (content == null) return '未指定章节。';
    final buffer = StringBuffer();
    for (final paragraph in content.paragraphs) {
      final isTargetParagraph =
          paragraphId != null && paragraph.id == paragraphId;
      buffer.writeln('第 ${paragraph.ordinal + 1} 段：');
      buffer.writeln(paragraph.originalText);
      final translations = paragraph.sentences
          .where((sentence) => sentence.translation != null)
          .map((sentence) => sentence.translation!.text)
          .join();
      if (translations.isNotEmpty) buffer.writeln('译文：$translations');
      if (sentenceId != null &&
          paragraph.sentences.any((sentence) => sentence.id == sentenceId)) {
        buffer.writeln('（用户正在阅读的句子在此段）');
      }
      if (isTargetParagraph) buffer.writeln('（用户当前段落）');
      if (buffer.length > 9000) break;
    }
    return buffer.toString();
  }

  String _knowledgeContext(LocalSearchResults results) {
    final buffer = StringBuffer();
    for (final hit in results.sentences.take(6)) {
      buffer.writeln('《${hit.bookTitle}》· ${hit.chapterTitle}：${hit.text}');
    }
    for (final entity in results.entities.take(5)) {
      buffer.writeln(
        '人物/实体：${entity.name}（${entity.kind}）${entity.summary ?? ''}',
      );
    }
    for (final event in results.events.take(5)) {
      buffer.writeln(
        '历史事件：${event.name}（${event.timeRaw ?? '时间未详'}，${event.eventType}）',
      );
    }
    return buffer.isEmpty ? '本地知识库暂无相关记载。' : buffer.toString();
  }
}
