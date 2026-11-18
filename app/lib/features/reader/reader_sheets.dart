import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/settings_controller.dart';
import '../../data/models.dart';
import '../../domain/reading_mode.dart';
import '../../providers.dart';

Future<void> showReaderSettings(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ReaderSettingsSheet(),
  );
}

class _ReaderSettingsSheet extends ConsumerWidget {
  const _ReaderSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('阅读设置', style: theme.textTheme.titleLarge),
            const SizedBox(height: 18),
            Row(
              children: [
                Text('正文字号', style: theme.textTheme.bodyMedium),
                Expanded(
                  child: Slider(
                    value: settings.fontSize,
                    min: 14,
                    max: 28,
                    divisions: 14,
                    label: settings.fontSize.round().toString(),
                    onChanged: (value) => controller.setFontSize(value),
                  ),
                ),
                SizedBox(
                  width: 42,
                  child: Text(
                    '${settings.fontSize.round()}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text('行距', style: theme.textTheme.bodyMedium),
                Expanded(
                  child: Slider(
                    value: settings.lineHeight,
                    min: 1.4,
                    max: 2.6,
                    divisions: 12,
                    label: settings.lineHeight.toStringAsFixed(1),
                    onChanged: (value) => controller.setLineHeight(value),
                  ),
                ),
                SizedBox(
                  width: 42,
                  child: Text(
                    settings.lineHeight.toStringAsFixed(1),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('阅读主题', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in const [
                  ('paper', '纸张', Icons.style_outlined),
                  ('light', '浅色', Icons.light_mode_outlined),
                  ('dark', '深色', Icons.dark_mode_outlined),
                ])
                  ChoiceChip(
                    avatar: Icon(entry.$3, size: 16),
                    label: Text(entry.$2),
                    selected: settings.themeMode == entry.$1,
                    onSelected: (_) => controller.setTheme(entry.$1),
                    showCheckmark: false,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('打开章节时自动翻译'),
              subtitle: const Text('仅在已配置翻译方式且存在未译句子时触发'),
              value: settings.autoTranslate,
              onChanged: controller.setAutoTranslate,
            ),
            const Divider(),
            Text(
              '阅读偏好保存在本机。翻译方式与移动端直连 AI 可在“我的”中配置。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.46),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> showTocSheet(
  BuildContext context,
  List<ChapterSummary> chapters,
  String currentChapterId,
) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (context, scrollController) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                child: Row(
                  children: [
                    Text('章节目录', style: theme.textTheme.titleLarge),
                    const Spacer(),
                    Text(
                      '${chapters.length} 章',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: chapters.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 22, endIndent: 22),
                  itemBuilder: (context, index) {
                    final chapter = chapters[index];
                    final active = chapter.id == currentChapterId;
                    return ListTile(
                      onTap: () => Navigator.of(context).pop(chapter.id),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 3,
                      ),
                      leading: SizedBox(
                        width: 28,
                        child: Text(
                          '${chapter.ordinal + 1}'.padLeft(2, '0'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        chapter.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: active ? theme.colorScheme.primary : null,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: (chapter.translationPercent / 100).clamp(
                              0,
                              1,
                            ),
                            minHeight: 3,
                            backgroundColor: theme.colorScheme.onSurface
                                .withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                      trailing: active
                          ? Icon(
                              Icons.menu_book_rounded,
                              color: theme.colorScheme.primary,
                              size: 19,
                            )
                          : null,
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> showParagraphSheet(
  BuildContext context, {
  required ChapterContent content,
  required Paragraph paragraph,
  required void Function(Sentence sentence) onSentenceTap,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
            children: [
              Text(
                '第 ${paragraph.ordinal + 1} 段',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                paragraph.originalText,
                style: TextStyle(
                  fontSize: 17,
                  height: 1.9,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 10),
              Text('译文', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              if (paragraph.translationText == null)
                Text(
                  '本段尚未翻译。可点击顶部“翻译”按钮请求 AI 翻译本章。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    height: 1.7,
                  ),
                )
              else
                Text(
                  paragraph.translationText!,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.85,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final sentence in paragraph.sentences)
                    ActionChip(
                      avatar: Icon(
                        sentence.translation != null
                            ? Icons.check_circle_outline
                            : Icons.hourglass_empty,
                        size: 15,
                      ),
                      label: Text(
                        sentence.originalText.length > 10
                            ? '${sentence.originalText.substring(0, 10)}…'
                            : sentence.originalText,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        onSentenceTap(sentence);
                      },
                    ),
                ],
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> showSentenceSheet(
  BuildContext context, {
  required String bookId,
  required ChapterContent content,
  required Paragraph paragraph,
  required Sentence sentence,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SentenceSheet(
      bookId: bookId,
      content: content,
      paragraph: paragraph,
      sentence: sentence,
    ),
  );
}

class _SentenceSheet extends ConsumerStatefulWidget {
  const _SentenceSheet({
    required this.bookId,
    required this.content,
    required this.paragraph,
    required this.sentence,
  });

  final String bookId;
  final ChapterContent content;
  final Paragraph paragraph;
  final Sentence sentence;

  @override
  ConsumerState<_SentenceSheet> createState() => _SentenceSheetState();
}

class _SentenceSheetState extends ConsumerState<_SentenceSheet> {
  final _annotationController = TextEditingController();
  bool _showAnnotation = false;
  bool _savingAnnotation = false;
  bool _explaining = false;
  String? _explanation;
  List<AssistantCitation> _citations = const [];
  List<Annotation> _annotations = const [];
  List<Map<String, Object?>> _versions = const [];

  @override
  void initState() {
    super.initState();
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    final annotations = await ref
        .read(readerRepositoryProvider)
        .annotations(widget.bookId);
    final versions = await ref
        .read(localStoreProvider)
        .translationVersions(widget.sentence.id);
    if (!mounted) return;
    setState(() {
      _annotations = annotations
          .where((item) => item.sentenceId == widget.sentence.id)
          .toList();
      _versions = versions;
    });
  }

  @override
  void dispose() {
    _annotationController.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.sentence.originalText));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制原文')));
    }
  }

  Future<void> _saveAnnotation() async {
    final text = _annotationController.text.trim();
    if (text.isEmpty) return;
    setState(() => _savingAnnotation = true);
    try {
      await ref
          .read(readerRepositoryProvider)
          .createAnnotation(
            bookId: widget.bookId,
            chapterId: widget.content.chapterId,
            paragraphId: widget.paragraph.id,
            sentenceId: widget.sentence.id,
            quote: widget.sentence.originalText,
            content: text,
          );
      if (!mounted) return;
      _annotationController.clear();
      setState(() => _showAnnotation = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('批注已保存')));
    } finally {
      if (mounted) setState(() => _savingAnnotation = false);
    }
  }

  Future<void> _editTranslation() async {
    final controller = TextEditingController(
      text: widget.sentence.translation?.text ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.sentence.translation == null ? '添加人工译文' : '修改译文'),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: '译文',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true || controller.text.trim().isEmpty) return;
    try {
      await ref
          .read(translationServiceProvider)
          .saveManual(widget.sentence.id, controller.text.trim());
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    }
  }

  Future<void> _retranslateSentence({bool useCache = true}) async {
    try {
      await ref
          .read(translationServiceProvider)
          .retranslateSentence(widget.sentence.id, useCache: useCache);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('重新翻译失败：$error')));
      }
    }
  }

  Future<void> _resolveReview(bool accept) async {
    final review = widget.sentence.pendingReview;
    if (review == null) return;
    await ref.read(translationServiceProvider).resolveReview(review.id, accept);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _deleteAnnotation(Annotation annotation) async {
    await ref.read(readerRepositoryProvider).deleteAnnotation(annotation);
    await _loadExtras();
  }

  Future<void> _explain() async {
    setState(() {
      _explaining = true;
      _explanation = null;
      _citations = const [];
    });
    try {
      final answer = await ref
          .read(localApiProvider)
          .assistant(
            question: '请解释这句话的难词、句式、典故与整体含义。',
            bookId: widget.bookId,
            chapterId: widget.content.chapterId,
            paragraphId: widget.paragraph.id,
            sentenceId: widget.sentence.id,
          );
      if (!mounted) return;
      setState(() {
        _explanation = answer.answer;
        _citations = answer.citations;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _explanation = '解释失败：$error');
      }
    } finally {
      if (mounted) setState(() => _explaining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sentence = widget.sentence;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.64,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('句子详情', style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_rounded, size: 19),
                ),
                IconButton(
                  onPressed: () =>
                      setState(() => _showAnnotation = !_showAnnotation),
                  icon: const Icon(Icons.edit_note_rounded, size: 21),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary.withValues(alpha: 0.055),
                borderRadius: BorderRadius.circular(14),
                border: Border(
                  left: BorderSide(
                    color: theme.colorScheme.secondary.withValues(alpha: 0.5),
                    width: 3,
                  ),
                ),
              ),
              child: Text(
                sentence.originalText,
                style: TextStyle(
                  fontSize: 17,
                  height: 1.9,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _stateColor(
                      theme,
                      sentence.state,
                    ).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    stateLabel(sentence.state),
                    style: TextStyle(
                      fontSize: 10,
                      color: _stateColor(theme, sentence.state),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                if (sentence.isManual)
                  Text(
                    '人工修订',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                if (sentence.needsReview)
                  Text(
                    ' · 断句待复核',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('译文', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            if (sentence.translation != null)
              Text(
                sentence.translation!.text,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.85,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
                ),
              )
            else
              Text(
                '尚未翻译。可以在阅读页请求 AI 翻译本章。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.44),
                ),
              ),
            if (sentence.translationError != null) ...[
              const SizedBox(height: 8),
              Text(
                sentence.translationError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _editTranslation,
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: Text(sentence.translation == null ? '添加人工译文' : '修改译文'),
                ),
                TextButton.icon(
                  onPressed: () => _retranslateSentence(),
                  icon: const Icon(Icons.translate_rounded, size: 18),
                  label: const Text('重新翻译此句'),
                ),
                TextButton.icon(
                  onPressed: () => _retranslateSentence(useCache: false),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('强制重译'),
                ),
              ],
            ),
            if (sentence.pendingReview != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.tertiary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('待审核候选译文', style: theme.textTheme.labelMedium),
                    const SizedBox(height: 6),
                    if (sentence.translation != null)
                      Text(
                        sentence.translation!.text,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.7,
                          decoration: TextDecoration.lineThrough,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.42,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      sentence.pendingReview!.candidateText,
                      style: const TextStyle(height: 1.8),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FilledButton.tonal(
                          onPressed: () => _resolveReview(true),
                          child: const Text('采用候选'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => _resolveReview(false),
                          child: const Text('保留现译文'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _explaining ? null : _explain,
              icon: _explaining
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('AI 解释这句话'),
            ),
            if (_explanation != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.035),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI 解释', style: theme.textTheme.labelMedium),
                    const SizedBox(height: 6),
                    Text(
                      _explanation!,
                      style: const TextStyle(height: 1.8, fontSize: 14),
                    ),
                    for (final citation in _citations) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondary.withValues(
                            alpha: 0.06,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${citation.book} · ${citation.chapter}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (citation.quote != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                citation.quote!,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  height: 1.7,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (_showAnnotation) ...[
              const SizedBox(height: 18),
              TextField(
                controller: _annotationController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(hintText: '记录你的理解、疑问或考据…'),
              ),
              const SizedBox(height: 9),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _showAnnotation = false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: _savingAnnotation ? null : _saveAnnotation,
                    child: _savingAnnotation
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('保存批注'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 22),
            Text(
              '批注 · ${_annotations.length}',
              style: theme.textTheme.labelLarge,
            ),
            if (_annotations.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '本句暂无批注。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                  ),
                ),
              )
            else
              for (final annotation in _annotations)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          annotation.content,
                          style: const TextStyle(height: 1.7, fontSize: 13.5),
                        ),
                      ),
                      IconButton(
                        tooltip: '删除批注',
                        onPressed: () => _deleteAnnotation(annotation),
                        icon: const Icon(Icons.delete_outline, size: 17),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
            if (_versions.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text(
                '版本历史 · ${_versions.length}',
                style: theme.textTheme.labelLarge,
              ),
              for (final version in _versions)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.025,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${version['origin'] == 'manual' ? '人工' : 'AI'} · ${version['model_name'] ?? ''}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.45,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          version['text'] as String? ?? '',
                          style: const TextStyle(height: 1.7, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Color _stateColor(ThemeData theme, String state) => switch (state) {
    'completed' => theme.colorScheme.primary,
    'failed' => theme.colorScheme.error,
    'queued' || 'translating' => theme.colorScheme.tertiary,
    _ => theme.colorScheme.onSurface.withValues(alpha: 0.5),
  };
}

Future<void> showAssistantSheet(
  BuildContext context, {
  required ChapterContent content,
  Sentence? sentence,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AssistantSheet(content: content, sentence: sentence),
  );
}

class _AssistantMessage {
  const _AssistantMessage({
    required this.role,
    required this.text,
    this.citations = const [],
    this.claims = const [],
  });
  final String role;
  final String text;
  final List<AssistantCitation> citations;
  final List<AssistantClaim> claims;
}

class _AssistantSheet extends ConsumerStatefulWidget {
  const _AssistantSheet({required this.content, this.sentence});
  final ChapterContent content;
  final Sentence? sentence;

  @override
  ConsumerState<_AssistantSheet> createState() => _AssistantSheetState();
}

class _AssistantSheetState extends ConsumerState<_AssistantSheet> {
  final _questionController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_AssistantMessage> _messages = [];
  bool _sending = false;
  String? _sessionId;

  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? suggested]) async {
    final question = (suggested ?? _questionController.text).trim();
    if (question.isEmpty || _sending) return;
    setState(() {
      _messages.add(_AssistantMessage(role: 'user', text: question));
      _sending = true;
    });
    _questionController.clear();
    _scrollToBottom();
    try {
      final answer = await ref
          .read(localApiProvider)
          .assistant(
            question: question,
            bookId: widget.content.bookId,
            chapterId: widget.content.chapterId,
            sentenceId: widget.sentence?.id,
            sessionId: _sessionId,
          );
      _sessionId = answer.sessionId ?? _sessionId;
      if (!mounted) return;
      setState(() {
        _messages.add(
          _AssistantMessage(
            role: 'assistant',
            text: answer.answer,
            citations: answer.citations,
            claims: answer.claims,
          ),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _AssistantMessage(role: 'assistant', text: '回答失败：$error'),
        );
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_awesome, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI 阅读助手',
                          style: theme.textTheme.titleMedium?.copyWith(),
                        ),
                        Text(
                          '${widget.content.bookTitle} · ${widget.content.chapterTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _messages.clear();
                      _sessionId = null;
                    }),
                    child: const Text('新对话'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _messages.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(22),
                      children: [
                        Text(
                          '“知之为知之，不知为不知。”',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.65,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '我会优先依据当前书籍、章节与本地知识库回答，并尽量标注原文出处。AI 推断与未证实内容会单独标记。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.75,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        for (final suggestion in const [
                          '解释当前句意',
                          '概括本章主要内容',
                          '介绍相关人物背景',
                          '有哪些史料出处',
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: ActionChip(
                              label: Text(suggestion),
                              onPressed: () => _send(suggestion),
                            ),
                          ),
                      ],
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      itemCount: _messages.length + (_sending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _messages.length) {
                          return const Padding(
                            padding: EdgeInsets.all(14),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text('正在查阅史料…', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          );
                        }
                        final message = _messages[index];
                        return _AssistantBubble(message: message);
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.07,
                      ),
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _questionController,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: '询问当前句意、人物、制度或出处…',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : () => _send(),
                      icon: const Icon(Icons.arrow_upward_rounded, size: 19),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.message});
  final _AssistantMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = message.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 13),
        padding: const EdgeInsets.all(13),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.84,
        ),
        decoration: BoxDecoration(
          color: user
              ? theme.colorScheme.primary.withValues(alpha: 0.09)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15),
            topRight: const Radius.circular(15),
            bottomLeft: Radius.circular(user ? 15 : 4),
            bottomRight: Radius.circular(user ? 4 : 15),
          ),
          border: user
              ? null
              : Border.all(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: const TextStyle(fontSize: 13.5, height: 1.78),
            ),
            if (message.claims.isNotEmpty) ...[
              const SizedBox(height: 9),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final claim in message.claims)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _claimColor(
                          theme,
                          claim.kind,
                        ).withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${_claimLabel(claim.kind)} · ${claim.text}',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: _claimColor(theme, claim.kind),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            for (final citation in message.citations) ...[
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    left: BorderSide(
                      color: theme.colorScheme.secondary.withValues(
                        alpha: 0.45,
                      ),
                      width: 2,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${citation.book} · ${citation.chapter}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          citation.verified
                              ? Icons.verified_outlined
                              : Icons.help_outline,
                          size: 14,
                          color: citation.verified
                              ? theme.colorScheme.primary
                              : theme.colorScheme.tertiary,
                        ),
                      ],
                    ),
                    if (citation.quote != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        citation.quote!,
                        style: const TextStyle(fontSize: 12, height: 1.7),
                      ),
                    ],
                    if (citation.note != null)
                      Text(
                        citation.note!,
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.42,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _claimLabel(String kind) => switch (kind) {
    'explicit' || '原文明确' => '原文明确',
    'inference' || '合理推断' => '合理推断',
    'analysis' || '分析' => '分析',
    'unverified' || '证据不足' => '证据不足',
    _ => '证据不足',
  };

  Color _claimColor(ThemeData theme, String kind) => switch (kind) {
    'explicit' || '原文明确' => theme.colorScheme.primary,
    'inference' || '合理推断' => theme.colorScheme.tertiary,
    'analysis' || '分析' => theme.colorScheme.secondary,
    _ => theme.colorScheme.error,
  };
}

class ChapterSearchDelegate extends SearchDelegate<int?> {
  ChapterSearchDelegate(this.content);
  final ChapterContent content;

  @override
  String get searchFieldLabel => '在章节内搜索';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(
      icon: const Icon(Icons.close),
      onPressed: () {
        if (query.isEmpty) {
          close(context, null);
        } else {
          query = '';
        }
      },
    ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => _buildResults(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildResults(context);

  Widget _buildResults(BuildContext context) {
    final value = query.trim();
    if (value.isEmpty) {
      return const Center(child: Text('输入句子或词语，定位到对应段落'));
    }
    final matches = <(int, Sentence)>[];
    for (final paragraph in content.paragraphs) {
      for (final sentence in paragraph.sentences) {
        if (sentence.originalText.contains(value) ||
            (sentence.translation?.text.contains(value) ?? false)) {
          matches.add((paragraph.ordinal, sentence));
        }
      }
    }
    if (matches.isEmpty) {
      return const Center(child: Text('本章没有找到相关句子'));
    }
    return ListView.separated(
      itemCount: matches.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: 18, endIndent: 18),
      itemBuilder: (context, index) {
        final (paragraphIndex, sentence) = matches[index];
        return ListTile(
          title: Text(
            sentence.originalText,
            style: const TextStyle(fontSize: 14),
          ),
          subtitle: Text(
            '第 ${paragraphIndex + 1} 段 · ${sentence.translation?.text ?? '未翻译'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => close(context, paragraphIndex),
        );
      },
    );
  }
}
