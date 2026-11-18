import 'dart:convert';

int _int(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

double _double(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? fallback;
}

String? _str(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

class Book {
  const Book({
    required this.id,
    required this.title,
    this.author,
    this.dynasty,
    this.category,
    this.description,
    this.tags = const [],
    this.sourceFormat = 'txt',
    this.coverPath,
    this.chapterCount = 0,
    this.sentenceCount = 0,
    this.translatedSentenceCount = 0,
    this.translationPercent = 0,
    this.lastReadAt,
  });

  final String id;
  final String title;
  final String? author;
  final String? dynasty;
  final String? category;
  final String? description;
  final List<String> tags;
  final String sourceFormat;
  final String? coverPath;
  final int chapterCount;
  final int sentenceCount;
  final int translatedSentenceCount;
  final double translationPercent;
  final String? lastReadAt;

  factory Book.fromJson(Map<String, dynamic> json) => Book(
    id: json['id'] as String,
    title: json['title'] as String? ?? '未命名古籍',
    author: _str(json['author']),
    dynasty: _str(json['dynasty']),
    category: _str(json['category']),
    description: _str(json['description']),
    tags: (json['tags'] as List? ?? const []).map((e) => '$e').toList(),
    sourceFormat: json['source_format'] as String? ?? 'txt',
    coverPath: _str(json['cover_url']),
    chapterCount: _int(json['chapter_count']),
    sentenceCount: _int(json['sentence_count']),
    translatedSentenceCount: _int(json['translated_sentence_count']),
    translationPercent: _double(json['translation_percent']),
    lastReadAt: _str(json['last_read_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'dynasty': dynasty,
    'category': category,
    'description': description,
    'tags': tags,
    'source_format': sourceFormat,
    'cover_url': coverPath,
    'chapter_count': chapterCount,
    'sentence_count': sentenceCount,
    'translated_sentence_count': translatedSentenceCount,
    'translation_percent': translationPercent,
    'last_read_at': lastReadAt,
  };
}

class ChapterSummary {
  const ChapterSummary({
    required this.id,
    required this.bookId,
    required this.ordinal,
    required this.title,
    this.paragraphCount = 0,
    this.sentenceCount = 0,
    this.translatedCount = 0,
    this.translationPercent = 0,
  });

  final String id;
  final String bookId;
  final int ordinal;
  final String title;
  final int paragraphCount;
  final int sentenceCount;
  final int translatedCount;
  final double translationPercent;

  factory ChapterSummary.fromJson(Map<String, dynamic> json) => ChapterSummary(
    id: json['id'] as String,
    bookId: json['book_id'] as String? ?? '',
    ordinal: _int(json['ordinal']),
    title: json['title'] as String? ?? '未命名章节',
    paragraphCount: _int(json['paragraph_count']),
    sentenceCount: _int(json['sentence_count']),
    translatedCount: _int(json['translated_count']),
    translationPercent: _double(json['translation_percent']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'book_id': bookId,
    'ordinal': ordinal,
    'title': title,
    'paragraph_count': paragraphCount,
    'sentence_count': sentenceCount,
    'translated_count': translatedCount,
    'translation_percent': translationPercent,
  };
}

class TranslationStatus {
  const TranslationStatus({
    this.total = 0,
    this.translated = 0,
    this.manual = 0,
    this.pendingReviews = 0,
    this.pending = 0,
    this.queued = 0,
    this.translating = 0,
    this.failed = 0,
    this.percent = 0,
  });

  final int total;
  final int translated;
  final int manual;
  final int pendingReviews;
  final int pending;
  final int queued;
  final int translating;
  final int failed;
  final double percent;

  factory TranslationStatus.fromJson(Map<String, dynamic>? json) {
    final states =
        (json?['states'] as Map?)?.cast<String, dynamic>() ?? const {};
    return TranslationStatus(
      total: _int(json?['total']),
      translated: _int(json?['translated']),
      manual: _int(json?['manual']),
      pendingReviews: _int(json?['pending_reviews']),
      pending: _int(states['pending']),
      queued: _int(states['queued']),
      translating: _int(states['translating']),
      failed: _int(states['failed']),
      percent: _double(json?['percent']),
    );
  }

  bool get hasActiveTask => queued > 0 || translating > 0;
}

class TranslationRecord {
  const TranslationRecord({
    required this.id,
    required this.sentenceId,
    required this.text,
    this.origin = 'ai',
    this.status = 'completed',
    this.modelName,
    this.localAnalysis,
    this.version = 1,
  });

  final String id;
  final String sentenceId;
  final String text;
  final String origin;
  final String status;
  final String? modelName;
  final String? localAnalysis;
  final int version;

  bool get isManual => origin == 'manual';

  factory TranslationRecord.fromJson(Map<String, dynamic> json) =>
      TranslationRecord(
        id: json['id'] as String,
        sentenceId: json['sentence_id'] as String? ?? '',
        text: json['text'] as String? ?? '',
        origin: json['origin'] as String? ?? 'ai',
        status: json['status'] as String? ?? 'completed',
        modelName: _str(json['model_name']),
        localAnalysis: _str(json['local_analysis']),
        version: _int(json['version'], 1),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sentence_id': sentenceId,
    'text': text,
    'origin': origin,
    'status': status,
    'model_name': modelName,
    'local_analysis': localAnalysis,
    'version': version,
  };
}

class PendingReview {
  const PendingReview({required this.id, required this.candidateText});
  final String id;
  final String candidateText;

  factory PendingReview.fromJson(Map<String, dynamic> json) => PendingReview(
    id: json['id'] as String,
    candidateText: json['candidate_text'] as String? ?? '',
  );
}

class Sentence {
  const Sentence({
    required this.id,
    required this.ordinal,
    required this.originalText,
    this.state = 'pending',
    this.translationError,
    this.translation,
    this.pendingReview,
    this.needsReview = false,
  });

  final String id;
  final int ordinal;
  final String originalText;
  final String state;
  final String? translationError;
  final TranslationRecord? translation;
  final PendingReview? pendingReview;
  final bool needsReview;

  bool get hasTranslation => translation != null;
  bool get isManual => translation?.isManual ?? false;

  factory Sentence.fromJson(Map<String, dynamic> json) => Sentence(
    id: json['id'] as String,
    ordinal: _int(json['ordinal']),
    originalText: json['original_text'] as String? ?? '',
    state: json['translation_state'] as String? ?? 'pending',
    translationError: _str(json['translation_error']),
    translation: json['translation'] is Map
        ? TranslationRecord.fromJson(
            (json['translation'] as Map).cast<String, dynamic>(),
          )
        : null,
    pendingReview: json['pending_review'] is Map
        ? PendingReview.fromJson(
            (json['pending_review'] as Map).cast<String, dynamic>(),
          )
        : null,
    needsReview: json['needs_review'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'ordinal': ordinal,
    'original_text': originalText,
    'translation_state': state,
    'translation_error': translationError,
    'translation': translation?.toJson(),
    'pending_review': pendingReview == null
        ? null
        : {
            'id': pendingReview!.id,
            'candidate_text': pendingReview!.candidateText,
          },
    'needs_review': needsReview,
  };

  Sentence copyWith({TranslationRecord? translation, String? state}) =>
      Sentence(
        id: id,
        ordinal: ordinal,
        originalText: originalText,
        state: state ?? this.state,
        translationError: translationError,
        translation: translation ?? this.translation,
        pendingReview: pendingReview,
        needsReview: needsReview,
      );
}

class Paragraph {
  const Paragraph({
    required this.id,
    required this.ordinal,
    required this.originalText,
    this.sentences = const [],
    this.translationText,
    this.translationComplete = false,
  });

  final String id;
  final int ordinal;
  final String originalText;
  final List<Sentence> sentences;
  final String? translationText;
  final bool translationComplete;

  factory Paragraph.fromJson(Map<String, dynamic> json) => Paragraph(
    id: json['id'] as String,
    ordinal: _int(json['ordinal']),
    originalText: json['original_text'] as String? ?? '',
    sentences: (json['sentences'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Sentence.fromJson(e.cast<String, dynamic>()))
        .toList(),
    translationText: _str(json['translation_text']),
    translationComplete: json['translation_complete'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'ordinal': ordinal,
    'original_text': originalText,
    'sentences': sentences.map((e) => e.toJson()).toList(),
    'translation_text': translationText,
    'translation_complete': translationComplete,
  };

  Paragraph copyWith({
    List<Sentence>? sentences,
    String? translationText,
    bool? translationComplete,
  }) {
    final updated = sentences ?? this.sentences;
    final parts = updated
        .where((s) => s.translation != null)
        .map((s) => s.translation!.text)
        .toList();
    return Paragraph(
      id: id,
      ordinal: ordinal,
      originalText: originalText,
      sentences: updated,
      translationText: translationText ?? (parts.isEmpty ? null : parts.join()),
      translationComplete:
          translationComplete ?? updated.every((s) => s.translation != null),
    );
  }
}

class ChapterContent {
  const ChapterContent({
    required this.bookId,
    required this.bookTitle,
    this.bookAuthor,
    required this.chapterId,
    required this.chapterTitle,
    required this.chapterOrdinal,
    this.previousChapterId,
    this.nextChapterId,
    this.status = const TranslationStatus(),
    this.paragraphs = const [],
  });

  final String bookId;
  final String bookTitle;
  final String? bookAuthor;
  final String chapterId;
  final String chapterTitle;
  final int chapterOrdinal;
  final String? previousChapterId;
  final String? nextChapterId;
  final TranslationStatus status;
  final List<Paragraph> paragraphs;

  factory ChapterContent.fromJson(Map<String, dynamic> json) {
    final book = (json['book'] as Map?)?.cast<String, dynamic>() ?? const {};
    final chapter =
        (json['chapter'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ChapterContent(
      bookId: book['id'] as String? ?? chapter['book_id'] as String? ?? '',
      bookTitle: book['title'] as String? ?? '',
      bookAuthor: _str(book['author']),
      chapterId: chapter['id'] as String? ?? '',
      chapterTitle: chapter['title'] as String? ?? '',
      chapterOrdinal: _int(chapter['ordinal']),
      previousChapterId: _str(json['previous_chapter_id']),
      nextChapterId: _str(json['next_chapter_id']),
      status: TranslationStatus.fromJson(
        (json['translation_status'] as Map?)?.cast<String, dynamic>(),
      ),
      paragraphs: (json['paragraphs'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Paragraph.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'book': {'id': bookId, 'title': bookTitle, 'author': bookAuthor},
    'chapter': {
      'id': chapterId,
      'book_id': bookId,
      'ordinal': chapterOrdinal,
      'title': chapterTitle,
    },
    'previous_chapter_id': previousChapterId,
    'next_chapter_id': nextChapterId,
    'translation_status': {
      'total': status.total,
      'translated': status.translated,
      'manual': status.manual,
      'pending_reviews': status.pendingReviews,
      'percent': status.percent,
      'states': {
        'pending': status.pending,
        'queued': status.queued,
        'translating': status.translating,
        'failed': status.failed,
      },
    },
    'paragraphs': paragraphs.map((p) => p.toJson()).toList(),
  };

  ChapterContent copyWith({
    List<Paragraph>? paragraphs,
    TranslationStatus? status,
  }) {
    final updated = paragraphs ?? this.paragraphs;
    final total = updated.fold<int>(0, (sum, p) => sum + p.sentences.length);
    final translated = updated.fold<int>(
      0,
      (sum, p) => sum + p.sentences.where((s) => s.translation != null).length,
    );
    return ChapterContent(
      bookId: bookId,
      bookTitle: bookTitle,
      bookAuthor: bookAuthor,
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      chapterOrdinal: chapterOrdinal,
      previousChapterId: previousChapterId,
      nextChapterId: nextChapterId,
      status:
          status ??
          TranslationStatus(
            total: total,
            translated: translated,
            manual: this.status.manual,
            pending: total - translated,
            percent: total == 0 ? 0 : translated / total * 100,
          ),
      paragraphs: updated,
    );
  }
}

class TaskInfo {
  const TaskInfo({
    required this.id,
    required this.type,
    required this.status,
    required this.title,
    this.progress = 0,
    this.total = 0,
    this.completed = 0,
    this.failedCount = 0,
    this.error,
    this.bookId,
    this.chapterId,
    this.result = const {},
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.cost = 0,
    this.requests = 0,
    this.estimatedUsage = 0,
    this.heartbeatAt,
    this.leaseOwner,
    this.stage,
    this.checkpoint,
  });

  final String id;
  final String type;
  final String status;
  final String title;
  final double progress;
  final int total;
  final int completed;
  final int failedCount;
  final String? error;
  final String? bookId;
  final String? chapterId;
  final Map<String, dynamic> result;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final double cost;
  final int requests;
  final int estimatedUsage;
  final String? heartbeatAt;
  final String? leaseOwner;
  final String? stage;
  final String? checkpoint;

  bool get isActive =>
      status == 'queued' || status == 'running' || status == 'paused';
  bool get isFinished => [
    'completed',
    'partial',
    'failed',
    'cancelled',
    'interrupted',
  ].contains(status);

  factory TaskInfo.fromJson(Map<String, dynamic> json) => TaskInfo(
    id: json['id'] as String,
    type: json['type'] as String? ?? '',
    status: json['status'] as String? ?? 'queued',
    title: json['title'] as String? ?? '任务',
    progress: _double(json['progress']),
    total: _int(json['total']),
    completed: _int(json['completed']),
    failedCount: _int(json['failed_count']),
    error: _str(json['error']),
    bookId: _str(json['book_id']),
    chapterId: _str(json['chapter_id']),
    result: (json['result'] as Map?)?.cast<String, dynamic>() ?? const {},
    inputTokens: _int(json['input_tokens']),
    outputTokens: _int(json['output_tokens']),
    cacheReadTokens: _int(json['cache_read_tokens']),
    cacheWriteTokens: _int(json['cache_write_tokens']),
    cost: _double(json['cost']),
    requests: _int(json['requests']),
    estimatedUsage: _int(json['estimated_usage']),
    heartbeatAt: _str(json['heartbeat_at']),
    leaseOwner: _str(json['lease_owner']),
    stage: _str(json['stage']),
    checkpoint: _str(json['checkpoint']),
  );
}

class HistoricalEntity {
  const HistoricalEntity({
    required this.id,
    required this.name,
    this.kind = 'person',
    this.dynasty,
    this.identity,
    this.summary,
    this.aliases = const [],
    this.status = 'pending',
    this.knowledgeType = 'explicit',
    this.mentions = const [],
    this.relations = const [],
  });

  final String id;
  final String name;
  final String kind;
  final String? dynasty;
  final String? identity;
  final String? summary;
  final List<String> aliases;
  final String status;
  final String knowledgeType;
  final List<EntityMention> mentions;
  final List<EntityRelation> relations;

  factory HistoricalEntity.fromJson(Map<String, dynamic> json) =>
      HistoricalEntity(
        id: json['id'] as String,
        name: json['canonical_name'] as String? ?? '',
        kind: json['kind'] as String? ?? 'person',
        dynasty: _str(json['dynasty']),
        identity: _str(json['identity']),
        summary: _str(json['summary']),
        aliases: (json['aliases'] as List? ?? const [])
            .map((e) => '$e')
            .toList(),
        status: json['status'] as String? ?? 'pending',
        knowledgeType: json['knowledge_type'] as String? ?? 'explicit',
        mentions: (json['mentions'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => EntityMention.fromJson(e.cast<String, dynamic>()))
            .toList(),
        relations: (json['relations'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => EntityRelation.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

class EntityMention {
  const EntityMention({
    required this.id,
    required this.quote,
    this.sentenceId,
    this.bookId,
    this.bookTitle,
    this.chapterId,
    this.chapterTitle,
  });
  final String id;
  final String quote;
  final String? sentenceId;
  final String? bookId;
  final String? bookTitle;
  final String? chapterId;
  final String? chapterTitle;

  factory EntityMention.fromJson(Map<String, dynamic> json) => EntityMention(
    id: json['id'] as String,
    quote: json['quote'] as String? ?? '',
    sentenceId: _str(json['sentence_id']),
    bookId: _str(json['book_id']),
    bookTitle: _str(json['book_title']),
    chapterId: _str(json['chapter_id']),
    chapterTitle: _str(json['chapter_title']),
  );
}

class EntityRelation {
  const EntityRelation({
    required this.id,
    required this.relationType,
    this.otherName,
    this.description,
    this.status = 'inferred',
    this.knowledgeType = 'inferred',
    this.confidence = 0.5,
    this.validFromRaw,
    this.validFromYear,
    this.validToRaw,
    this.validToYear,
    this.timePrecision = 'unknown',
    this.sourceKind = 'ai',
    this.sources = const [],
    this.otherId,
  });
  final String id;
  final String relationType;
  final String? otherName;
  final String? description;
  final String status;
  final String knowledgeType;
  final double confidence;
  final String? validFromRaw;
  final int? validFromYear;
  final String? validToRaw;
  final int? validToYear;
  final String timePrecision;
  final String sourceKind;
  final List<RelationSource> sources;
  final String? otherId;

  factory EntityRelation.fromJson(Map<String, dynamic> json) => EntityRelation(
    id: json['id'] as String,
    relationType: json['relation_type'] as String? ?? '其他',
    otherName: _str(json['other_entity_name']),
    description: _str(json['description']),
    status: json['status'] as String? ?? 'inferred',
    knowledgeType: json['knowledge_type'] as String? ?? 'inferred',
    confidence: (json['confidence'] as num? ?? 0.5).toDouble(),
    validFromRaw: _str(json['valid_from_raw']),
    validFromYear: json['valid_from_year'] as int?,
    validToRaw: _str(json['valid_to_raw']),
    validToYear: json['valid_to_year'] as int?,
    timePrecision: json['time_precision'] as String? ?? 'unknown',
    sourceKind: json['source_kind'] as String? ?? 'ai',
    otherId: _str(json['other_entity_id']),
    sources: (json['sources'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => RelationSource.fromJson(e.cast<String, dynamic>()))
        .toList(),
  );
}

class RelationSource {
  const RelationSource({
    this.id,
    this.quote,
    this.bookId,
    this.chapterId,
    this.sentenceId,
    this.paragraphId,
    this.bookTitle,
    this.chapterTitle,
    this.evidenceType = 'supporting',
    this.sourceKind = 'ai',
    this.note,
    this.reviewStatus = 'pending',
    this.createdAt,
  });
  final String? id;
  final String? quote;
  final String? bookId;
  final String? chapterId;
  final String? sentenceId;
  final String? paragraphId;
  final String? bookTitle;
  final String? chapterTitle;
  final String evidenceType;
  final String sourceKind;
  final String? note;
  final String reviewStatus;
  final String? createdAt;

  factory RelationSource.fromJson(Map<String, dynamic> json) => RelationSource(
    id: _str(json['id']),
    quote: _str(json['quote']),
    bookId: _str(json['book_id']),
    chapterId: _str(json['chapter_id']),
    sentenceId: _str(json['sentence_id']),
    paragraphId: _str(json['paragraph_id']),
    bookTitle: _str(json['book_title']),
    chapterTitle: _str(json['chapter_title']),
    evidenceType: json['evidence_type'] as String? ?? 'supporting',
    sourceKind: json['source_kind'] as String? ?? 'ai',
    note: _str(json['note']),
    reviewStatus: json['review_status'] as String? ?? 'pending',
    createdAt: _str(json['created_at']),
  );
}

class HistoricalEvent {
  const HistoricalEvent({
    required this.id,
    required this.name,
    this.eventType = '其他',
    this.description,
    this.timeRaw,
    this.timeStartYear,
    this.timeEndYear,
    this.timeEndRaw,
    this.location,
    this.timePrecision = 'unknown',
    this.dynasty,
    this.status = 'extracted',
    this.knowledgeType = 'inferred',
    this.sourceKind = 'ai',
    this.updatedBy,
    this.participants = const [],
    this.sources = const [],
  });

  final String id;
  final String name;
  final String eventType;
  final String? description;
  final String? timeRaw;
  final int? timeStartYear;
  final int? timeEndYear;
  final String? timeEndRaw;
  final String? location;
  final String timePrecision;
  final String? dynasty;
  final String status;
  final String knowledgeType;
  final String sourceKind;
  final String? updatedBy;
  final List<String> participants;
  final List<RelationSource> sources;

  factory HistoricalEvent.fromJson(Map<String, dynamic> json) =>
      HistoricalEvent(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        eventType: json['event_type'] as String? ?? '其他',
        description: _str(json['description']),
        timeRaw: _str(json['time_raw']),
        timeStartYear: json['time_start_year'] == null
            ? null
            : _int(json['time_start_year']),
        timeEndYear: json['time_end_year'] == null
            ? null
            : _int(json['time_end_year']),
        timeEndRaw: _str(json['time_end_raw']),
        location: _str(json['location']),
        timePrecision: json['time_precision'] as String? ?? 'unknown',
        dynasty: _str(json['dynasty']),
        status: json['status'] as String? ?? 'extracted',
        knowledgeType: json['knowledge_type'] as String? ?? 'inferred',
        sourceKind: json['source_kind'] as String? ?? 'ai',
        updatedBy: _str(json['updated_by']),
        participants: (json['participants'] as List? ?? const [])
            .map((e) => e is Map ? (e['name'] as String? ?? '') : '$e')
            .where((e) => e.isNotEmpty)
            .toList(),
        sources: (json['sources'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => RelationSource.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

class Annotation {
  const Annotation({
    required this.id,
    required this.bookId,
    required this.content,
    this.chapterId,
    this.paragraphId,
    this.sentenceId,
    this.quote,
    this.color = 'amber',
    this.tags = const [],
    this.createdAt,
    this.dirty = false,
  });

  final String id;
  final String bookId;
  final String content;
  final String? chapterId;
  final String? paragraphId;
  final String? sentenceId;
  final String? quote;
  final String color;
  final List<String> tags;
  final String? createdAt;
  final bool dirty;

  factory Annotation.fromJson(
    Map<String, dynamic> json, {
    bool dirty = false,
  }) => Annotation(
    id: json['id'] as String,
    bookId: json['book_id'] as String? ?? '',
    content: json['content'] as String? ?? '',
    chapterId: _str(json['chapter_id']),
    paragraphId: _str(json['paragraph_id']),
    sentenceId: _str(json['sentence_id']),
    quote: _str(json['quote']),
    color: json['color'] as String? ?? 'amber',
    tags: (json['tags'] as List? ?? const []).map((e) => '$e').toList(),
    createdAt: _str(json['created_at']),
    dirty: dirty,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'book_id': bookId,
    'chapter_id': chapterId,
    'paragraph_id': paragraphId,
    'sentence_id': sentenceId,
    'quote': quote,
    'content': content,
    'color': color,
    'tags': tags,
    'created_at': createdAt,
  };
}

class Bookmark {
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.chapterId,
    this.paragraphId,
    this.sentenceId,
    this.label,
    this.positionRatio = 0,
    this.createdAt,
    this.dirty = false,
  });

  final String id;
  final String bookId;
  final String chapterId;
  final String? paragraphId;
  final String? sentenceId;
  final String? label;
  final double positionRatio;
  final String? createdAt;
  final bool dirty;

  factory Bookmark.fromJson(Map<String, dynamic> json, {bool dirty = false}) =>
      Bookmark(
        id: json['id'] as String,
        bookId: json['book_id'] as String? ?? '',
        chapterId: json['chapter_id'] as String? ?? '',
        paragraphId: _str(json['paragraph_id']),
        sentenceId: _str(json['sentence_id']),
        label: _str(json['label']),
        positionRatio: _double(json['position_ratio']),
        createdAt: _str(json['created_at']),
        dirty: dirty,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'book_id': bookId,
    'chapter_id': chapterId,
    'paragraph_id': paragraphId,
    'sentence_id': sentenceId,
    'label': label,
    'position_ratio': positionRatio,
    'created_at': createdAt,
  };
}

class ReaderProgress {
  const ReaderProgress({
    required this.bookId,
    this.chapterId,
    this.paragraphId,
    this.paragraphIndex = 0,
    this.sentenceId,
    this.positionRatio = 0,
    this.updatedAt,
  });
  final String bookId;
  final String? chapterId;
  final String? paragraphId;
  final int paragraphIndex;
  final String? sentenceId;
  final double positionRatio;
  final String? updatedAt;

  factory ReaderProgress.fromJson(Map<String, dynamic> json) => ReaderProgress(
    bookId: json['book_id'] as String? ?? '',
    chapterId: _str(json['chapter_id']),
    paragraphId: _str(json['paragraph_id']),
    paragraphIndex: _int(json['paragraph_index']),
    sentenceId: _str(json['sentence_id']),
    positionRatio: _double(json['position_ratio']),
    updatedAt: _str(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'book_id': bookId,
    'chapter_id': chapterId,
    'paragraph_id': paragraphId,
    'paragraph_index': paragraphIndex,
    'sentence_id': sentenceId,
    'position_ratio': positionRatio,
    'updated_at': updatedAt,
  };
}

class AssistantAnswer {
  const AssistantAnswer({
    required this.answer,
    this.citations = const [],
    this.claims = const [],
    this.sessionId,
    this.model,
  });

  final String answer;
  final List<AssistantCitation> citations;
  final List<AssistantClaim> claims;
  final String? sessionId;
  final String? model;

  factory AssistantAnswer.fromJson(Map<String, dynamic> json) =>
      AssistantAnswer(
        answer: json['answer'] as String? ?? '',
        sessionId: _str(json['session_id']),
        model: _str(json['model']),
        citations: (json['citations'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => AssistantCitation.fromJson(e.cast<String, dynamic>()))
            .toList(),
        claims: (json['claims'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => AssistantClaim.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

class AssistantCitation {
  const AssistantCitation({
    required this.book,
    required this.chapter,
    this.quote,
    this.note,
    this.verified = false,
  });
  final String book;
  final String chapter;
  final String? quote;
  final String? note;
  final bool verified;

  factory AssistantCitation.fromJson(Map<String, dynamic> json) =>
      AssistantCitation(
        book: json['book'] as String? ?? '',
        chapter: json['chapter'] as String? ?? '',
        quote: _str(json['quote']),
        note: _str(json['note']),
        verified: json['verified'] as bool? ?? false,
      );
}

class AssistantClaim {
  const AssistantClaim({required this.text, this.kind = 'unverified'});
  final String text;
  final String kind;

  factory AssistantClaim.fromJson(Map<String, dynamic> json) => AssistantClaim(
    text: json['text'] as String? ?? '',
    kind: json['kind'] as String? ?? 'unverified',
  );
}

String? encodeJson(Object? value) => value == null ? null : jsonEncode(value);

Map<String, dynamic> decodeMap(String? value) {
  if (value == null || value.isEmpty) return const {};
  final decoded = jsonDecode(value);
  return decoded is Map<String, dynamic> ? decoded : const {};
}

List<dynamic> decodeList(String? value) {
  if (value == null || value.isEmpty) return const [];
  final decoded = jsonDecode(value);
  return decoded is List ? decoded : const [];
}
