import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../providers.dart';
import '../reader/reader_screen.dart';

const relationTypes = [
  '君臣关系',
  '亲属关系',
  '师生关系',
  '朋友关系',
  '敌对关系',
  '任职关系',
  '隶属关系',
  '政治关系',
  '军事关系',
  '其他',
];

const eventTypes = [
  'war',
  'coup',
  'accession',
  'appointment',
  'migration',
  'diplomacy',
  'institution_change',
  'other',
];

const timePrecisions = [
  'exact_date',
  'year_month',
  'year',
  'dynasty',
  'period',
  'estimated',
  'unknown',
];

const evidenceTypes = ['supporting', 'contradicting', 'contextual', 'inferred'];

String eventTypeLabel(String value) => switch (value) {
  'war' => '战争',
  'coup' => '政变',
  'accession' => '登基/即位',
  'appointment' => '任免',
  'migration' => '迁徙',
  'diplomacy' => '外交',
  'institution_change' => '制度变更',
  _ => '其他',
};

String evidenceTypeLabel(String value) => switch (value) {
  'contradicting' => '反驳',
  'contextual' => '背景',
  'inferred' => '推断',
  _ => '支持',
};

String evidenceStatusLabel(String value) => switch (value) {
  'confirmed' => '已确认',
  'rejected' => '已驳回',
  'disputed' => '存在争议',
  _ => '待审核',
};

Future<void> showEvidenceContext(
  BuildContext context,
  WidgetRef ref,
  Map<String, Object?> row, {
  required String targetType,
  required String targetId,
}) async {
  final contextData = await ref
      .read(knowledgeServiceProvider)
      .evidenceContext(
        bookId: '${row['book_id'] ?? ''}',
        chapterId: row['chapter_id'] as String?,
        sentenceId: row['sentence_id'] as String?,
        paragraphId: row['paragraph_id'] as String?,
      );
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('证据上下文'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '关联对象：${targetType == 'relation' ? '关系' : '事件'} · $targetId',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '${row['quote'] ?? ''}',
                style: const TextStyle(height: 1.8),
              ),
              const SizedBox(height: 10),
              if (contextData != null) ...[
                Text(
                  '${contextData['book_id']} · ${contextData['chapter_title'] ?? ''}'
                  ' · 第 ${contextData['paragraph_index']} 段'
                  '${contextData['sentence_index'] != null ? ' · 第 ${contextData['sentence_index']} 句' : ''}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if ('${contextData['before'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('前文：${contextData['before']}'),
                ],
                if ('${contextData['after'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('后文：${contextData['after']}'),
                ],
              ] else
                const Text('无法定位到原文位置，仅保留来源信息。'),
              const SizedBox(height: 10),
              Text(
                '${evidenceTypeLabel('${row['evidence_type'] ?? 'supporting'}')}'
                ' · ${evidenceStatusLabel('${row['review_status'] ?? 'pending'}')}'
                ' · ${row['source_kind'] == 'manual'
                    ? '人工'
                    : row['source_kind'] == 'external'
                    ? '外部补充'
                    : 'AI'}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              if (row['note'] != null && '${row['note']}'.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('备注：${row['note']}'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (contextData?['chapter_id'] != null)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReaderScreen(
                    bookId: '${contextData!['book_id']}',
                    chapterId: '${contextData['chapter_id']}',
                    chapterTitle: '${contextData['chapter_title'] ?? ''}',
                    bookTitle: '',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.menu_book_rounded),
            label: const Text('打开原文'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

class RelationEditorDialog extends ConsumerStatefulWidget {
  const RelationEditorDialog({
    super.key,
    required this.entityId,
    required this.relation,
  });

  final String entityId;
  final EntityRelation relation;

  @override
  ConsumerState<RelationEditorDialog> createState() =>
      _RelationEditorDialogState();
}

class _RelationEditorDialogState extends ConsumerState<RelationEditorDialog> {
  late String _type;
  late String _status;
  late String _precision;
  late TextEditingController _description;
  late TextEditingController _fromRaw;
  late TextEditingController _fromYear;
  late TextEditingController _toRaw;
  late TextEditingController _toYear;
  late TextEditingController _confidence;
  List<Map<String, Object?>> _evidence = const [];
  List<Map<String, Object?>> _history = const [];

  @override
  void initState() {
    super.initState();
    final relation = widget.relation;
    _type = relationTypes.contains(relation.relationType)
        ? relation.relationType
        : '其他';
    _status = relation.status == 'confirmed'
        ? 'confirmed'
        : relation.status == 'rejected'
        ? 'rejected'
        : 'pending';
    _precision = timePrecisions.contains(relation.timePrecision)
        ? relation.timePrecision
        : 'unknown';
    _description = TextEditingController(text: relation.description ?? '');
    _fromRaw = TextEditingController(text: relation.validFromRaw ?? '');
    _fromYear = TextEditingController(
      text: relation.validFromYear?.toString() ?? '',
    );
    _toRaw = TextEditingController(text: relation.validToRaw ?? '');
    _toYear = TextEditingController(
      text: relation.validToYear?.toString() ?? '',
    );
    _confidence = TextEditingController(
      text: relation.confidence.toStringAsFixed(2),
    );
    _loadEvidence();
    _loadHistory();
  }

  Future<void> _loadEvidence() async {
    final rows = await ref
        .read(knowledgeServiceProvider)
        .relationEvidence(widget.relation.id);
    if (mounted) setState(() => _evidence = rows);
  }

  Future<void> _loadHistory() async {
    final rows = await ref
        .read(knowledgeServiceProvider)
        .reviewHistory(targetType: 'relation', targetId: widget.relation.id);
    if (mounted) setState(() => _history = rows);
  }

  @override
  void dispose() {
    for (final controller in [
      _description,
      _fromRaw,
      _fromYear,
      _toRaw,
      _toYear,
      _confidence,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    await ref
        .read(knowledgeServiceProvider)
        .updateRelation(
          widget.relation.id,
          type: _type,
          description: _description.text.trim(),
          status: _status,
          validFromRaw: _fromRaw.text.trim(),
          validFromYear: int.tryParse(_fromYear.text.trim()),
          validToRaw: _toRaw.text.trim(),
          validToYear: int.tryParse(_toYear.text.trim()),
          timePrecision: _precision,
          confidence: double.tryParse(_confidence.text.trim()),
        );
    ref.invalidate(entityProvider(widget.entityId));
    ref.invalidate(graphProvider);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('编辑关系 · ${widget.relation.otherName ?? ''}'),
      content: SizedBox(
        width: 760,
        height: 620,
        child: ListView(
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: '关系类型'),
                    items: [
                      for (final type in relationTypes)
                        DropdownMenuItem(value: type, child: Text(type)),
                    ],
                    onChanged: (value) =>
                        setState(() => _type = value ?? _type),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: '审核状态'),
                    items: const [
                      DropdownMenuItem(value: 'confirmed', child: Text('确认')),
                      DropdownMenuItem(value: 'pending', child: Text('待审')),
                      DropdownMenuItem(value: 'rejected', child: Text('驳回')),
                    ],
                    onChanged: (value) =>
                        setState(() => _status = value ?? _status),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    initialValue: _precision,
                    decoration: const InputDecoration(labelText: '时间精度'),
                    items: [
                      for (final precision in timePrecisions)
                        DropdownMenuItem(
                          value: precision,
                          child: Text(precision),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _precision = value ?? _precision),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _confidence,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: '置信度'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(labelText: '关系描述'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _fromRaw,
                    decoration: const InputDecoration(labelText: '有效开始（原文）'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _fromYear,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '开始年份'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _toRaw,
                    decoration: const InputDecoration(labelText: '有效结束（原文）'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _toYear,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '结束年份'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text('原文证据', style: theme.textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addEvidence,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加证据'),
                ),
              ],
            ),
            if (_evidence.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('暂无证据。'),
              )
            else
              for (final row in _evidence)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    row['source_kind'] == 'manual'
                        ? Icons.edit_note_rounded
                        : Icons.auto_awesome_rounded,
                    size: 18,
                  ),
                  title: Text('${row['quote'] ?? ''}'),
                  subtitle: Text(
                    [
                      '${row['book_title'] ?? '未知书籍'}',
                      '${row['chapter_title'] ?? ''}',
                      evidenceTypeLabel(
                        '${row['evidence_type'] ?? 'supporting'}',
                      ),
                      row['source_kind'] == 'manual' ? '人工' : 'AI',
                    ].where((item) => item.isNotEmpty).join(' · '),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        evidenceStatusLabel(
                          '${row['review_status'] ?? 'pending'}',
                        ),
                        style: theme.textTheme.labelSmall,
                      ),
                      IconButton(
                        tooltip: '查看上下文',
                        icon: const Icon(Icons.article_outlined, size: 18),
                        onPressed: () => showEvidenceContext(
                          context,
                          ref,
                          row,
                          targetType: 'relation',
                          targetId: widget.relation.id,
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: '证据审核',
                        onSelected: (value) async {
                          if (value == '__delete') {
                            await ref
                                .read(knowledgeServiceProvider)
                                .deleteRelationEvidence(row['id'] as String);
                          } else {
                            await ref
                                .read(knowledgeServiceProvider)
                                .setEvidenceReviewStatus(
                                  targetType: 'relation',
                                  evidenceId: row['id'] as String,
                                  status: value,
                                );
                          }
                          await _loadEvidence();
                          await _loadHistory();
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'confirmed',
                            child: Text('确认证据'),
                          ),
                          PopupMenuItem(value: 'rejected', child: Text('驳回证据')),
                          PopupMenuItem(value: 'disputed', child: Text('标记争议')),
                          PopupMenuItem(value: 'pending', child: Text('恢复待审')),
                          PopupMenuDivider(),
                          PopupMenuItem(value: '__delete', child: Text('删除证据')),
                        ],
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('修改记录（${_history.length}）'),
              children: [
                for (final row in _history)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${row['action']}'),
                    subtitle: Text('${row['created_at']}'),
                    trailing: TextButton(
                      onPressed: () async {
                        await ref
                            .read(knowledgeServiceProvider)
                            .undoReview(row['id'] as String);
                        ref.invalidate(entityProvider(widget.entityId));
                        if (!context.mounted) return;
                        Navigator.pop(context, true);
                      },
                      child: const Text('撤销'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('删除关系'),
                content: const Text('删除后关系及其证据关联将移除，可在修改记录中查看。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除'),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              await ref
                  .read(knowledgeServiceProvider)
                  .deleteRelation(widget.relation.id);
              ref.invalidate(entityProvider(widget.entityId));
              ref.invalidate(graphProvider);
              if (!context.mounted) return;
              Navigator.pop(context, true);
            }
          },
          child: const Text('删除'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  Future<void> _addEvidence() async {
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => const EvidencePickerDialog(),
    );
    if (result == null) return;
    await ref
        .read(knowledgeServiceProvider)
        .addRelationEvidence(
          widget.relation.id,
          sentenceId: result['sentence_id'] as String?,
          bookId: result['book_id'] as String?,
          chapterId: result['chapter_id'] as String?,
          paragraphId: result['paragraph_id'] as String?,
          quote: '${result['quote']}',
          evidenceType: '${result['evidence_type']}',
          note: result['note'] as String?,
          sourceKind: '${result['source_kind']}',
        );
    await _loadEvidence();
    await _loadHistory();
  }
}

class EvidencePickerDialog extends ConsumerStatefulWidget {
  const EvidencePickerDialog({super.key});

  @override
  ConsumerState<EvidencePickerDialog> createState() =>
      _EvidencePickerDialogState();
}

class _EvidencePickerDialogState extends ConsumerState<EvidencePickerDialog> {
  final _quote = TextEditingController();
  final _note = TextEditingController();
  List<Book> _books = const [];
  List<ChapterSummary> _chapters = const [];
  List<Sentence> _sentences = const [];
  List<Paragraph> _paragraphs = const [];
  String? _bookId;
  String? _chapterId;
  String? _sentenceId;
  String? _paragraphId;
  bool _paragraphMode = false;
  String _evidenceType = 'supporting';
  String _sourceKind = 'manual';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    final books = await ref.read(localStoreProvider).listBooks();
    if (mounted) setState(() => _books = books);
  }

  Future<void> _loadChapters(String bookId) async {
    setState(() => _loading = true);
    final chapters = await ref.read(localStoreProvider).listChapters(bookId);
    if (!mounted) return;
    setState(() {
      _chapters = chapters;
      _chapterId = null;
      _sentences = const [];
      _sentenceId = null;
      _loading = false;
    });
  }

  Future<void> _loadSentences(String chapterId) async {
    setState(() => _loading = true);
    final content = await ref
        .read(localStoreProvider)
        .chapterContent(chapterId);
    if (!mounted) return;
    setState(() {
      _sentences = content == null
          ? const []
          : content.paragraphs
                .expand((paragraph) => paragraph.sentences)
                .toList();
      _paragraphs = content?.paragraphs ?? const [];
      _sentenceId = null;
      _paragraphId = null;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _quote.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加证据'),
      content: SizedBox(
        width: 620,
        height: 520,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _bookId,
                    decoration: const InputDecoration(labelText: '书籍'),
                    items: [
                      for (final book in _books)
                        DropdownMenuItem(
                          value: book.id,
                          child: Text(book.title),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() => _bookId = value);
                      if (value != null) _loadChapters(value);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _chapterId,
                    decoration: const InputDecoration(labelText: '章节'),
                    items: [
                      for (final chapter in _chapters)
                        DropdownMenuItem(
                          value: chapter.id,
                          child: Text(chapter.title),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() => _chapterId = value);
                      if (value != null) _loadSentences(value);
                    },
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('按段落选择证据'),
                    value: _paragraphMode,
                    onChanged: (value) =>
                        setState(() => _paragraphMode = value),
                  ),
                  if (_paragraphMode)
                    DropdownButtonFormField<String>(
                      initialValue: _paragraphId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '原文段落'),
                      items: [
                        for (var i = 0; i < _paragraphs.length; i++)
                          DropdownMenuItem(
                            value: _paragraphs[i].id,
                            child: Text(
                              '第 ${i + 1} 段 · ${_paragraphs[i].originalText}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() => _paragraphId = value);
                        final paragraph = _paragraphs
                            .where((item) => item.id == value)
                            .firstOrNull;
                        if (paragraph != null) {
                          _quote.text = paragraph.originalText;
                        }
                      },
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _sentenceId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '原文句子'),
                      items: [
                        for (final sentence in _sentences)
                          DropdownMenuItem(
                            value: sentence.id,
                            child: Text(
                              sentence.originalText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() => _sentenceId = value);
                        final sentence = _sentences
                            .where((item) => item.id == value)
                            .firstOrNull;
                        if (sentence != null) {
                          _quote.text = sentence.originalText;
                        }
                      },
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _quote,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '证据原文',
                      hintText: '从原文选择后自动填充；外部补充请注明',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _evidenceType,
                          decoration: const InputDecoration(labelText: '证据类型'),
                          items: [
                            for (final type in evidenceTypes)
                              DropdownMenuItem(
                                value: type,
                                child: Text(evidenceTypeLabel(type)),
                              ),
                          ],
                          onChanged: (value) => setState(
                            () => _evidenceType = value ?? _evidenceType,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _sourceKind,
                          decoration: const InputDecoration(labelText: '来源'),
                          items: const [
                            DropdownMenuItem(
                              value: 'manual',
                              child: Text('人工补充'),
                            ),
                            DropdownMenuItem(
                              value: 'external',
                              child: Text('外部补充'),
                            ),
                          ],
                          onChanged: (value) => setState(
                            () => _sourceKind = value ?? _sourceKind,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _note,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: '备注'),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _quote.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, {
                  'book_id': _bookId,
                  'chapter_id': _chapterId,
                  'sentence_id': _paragraphMode ? null : _sentenceId,
                  'paragraph_id': _paragraphMode ? _paragraphId : null,
                  'quote': _quote.text.trim(),
                  'evidence_type': _evidenceType,
                  'source_kind': _sourceKind,
                  'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
                }),
          child: const Text('添加'),
        ),
      ],
    );
  }
}
