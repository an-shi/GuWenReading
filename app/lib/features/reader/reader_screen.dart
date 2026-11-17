import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/storage/settings_controller.dart';
import '../../data/models.dart';
import '../../domain/reading_mode.dart';
import '../../providers.dart';
import '../notes/notes_screen.dart';
import 'reader_sheets.dart';
import 'reader_widgets.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.bookId,
    required this.chapterId,
    required this.chapterTitle,
    required this.bookTitle,
    this.initialMode,
  });

  final String bookId;
  final String chapterId;
  final String chapterTitle;
  final String bookTitle;
  final ReaderMode? initialMode;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener =
      ItemPositionsListener.create();
  final Set<String> _autoTriggered = {};

  ChapterContent? _content;
  List<ChapterSummary> _chapters = const [];
  ReaderMode _mode = ReaderMode.alternating;
  IndependentSide _side = IndependentSide.original;
  bool _loading = true;
  String? _error;
  bool _initialProgressApplied = false;
  int _currentIndex = 0;
  int _initialIndex = 0;
  TaskInfo? _activeTask;
  Timer? _pollTimer;
  Timer? _saveTimer;
  bool _translating = false;
  Sentence? _lastSentence;
  bool _bookmarked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final settings = ref.read(settingsProvider);
    final preferred = ReaderMode.fromKey(settings.defaultReadingMode);
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    _mode =
        widget.initialMode ??
        (wide && preferred == ReaderMode.alternating
            ? ReaderMode.columns
            : preferred);
    _positionsListener.itemPositions.addListener(_onPositionsChanged);
    _load(initial: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionsListener.itemPositions.removeListener(_onPositionsChanged);
    _pollTimer?.cancel();
    _saveTimer?.cancel();
    _persistProgress();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pollActiveTaskOnce();
    } else if (state == AppLifecycleState.paused) {
      _persistProgress();
    }
  }

  Future<void> _load({bool initial = false, bool force = false}) async {
    if (mounted) {
      setState(() {
        _loading = _content == null;
        _error = null;
      });
    }
    try {
      final repo = ref.read(readerRepositoryProvider);
      final chapters = await ref
          .read(libraryRepositoryProvider)
          .chapters(widget.bookId);
      final content = await repo.chapter(widget.chapterId, force: force);
      if (!mounted) return;

      var index = _currentIndex;
      if (initial && !_initialProgressApplied) {
        final progress = await repo.progress(widget.bookId);
        if (progress?.chapterId == widget.chapterId) {
          final byId = content.paragraphs.indexWhere(
            (p) => p.id == progress?.paragraphId,
          );
          index = byId >= 0
              ? byId
              : (progress?.paragraphIndex ?? 0)
                    .clamp(0, content.paragraphs.length - 1)
                    .toInt();
          if (byId < 0 &&
              (progress?.paragraphIndex ?? 0) == 0 &&
              content.paragraphs.isNotEmpty) {
            index = (progress!.positionRatio * (content.paragraphs.length - 1))
                .round();
          }
        } else {
          index = 0;
        }
        _initialProgressApplied = true;
        _initialIndex = index;
      }
      setState(() {
        _chapters = chapters;
        _content = content;
        _currentIndex = content.paragraphs.isEmpty
            ? 0
            : index.clamp(0, content.paragraphs.length - 1).toInt();
        _loading = false;
      });
      _jumpToCurrent();
      if (initial) _maybeAutoTranslate();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  void _jumpToCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.isAttached) return;
      if (_content == null || _content!.paragraphs.isEmpty) return;
      _scrollController.jumpTo(
        index: _currentIndex.clamp(0, _content!.paragraphs.length - 1),
        alignment: 0.02,
      );
    });
  }

  void _onPositionsChanged() {
    if (_content == null || _loading) return;
    final positions =
        _positionsListener.itemPositions.value
            .where(
              (position) =>
                  position.itemTrailingEdge > 0.12 &&
                  position.itemLeadingEdge < 0.88,
            )
            .toList()
          ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
    if (positions.isEmpty) return;
    final index = positions.first.index
        .clamp(0, _content!.paragraphs.length - 1)
        .toInt();
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
      _scheduleSave();
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _persistProgress);
  }

  void _persistProgress() {
    final content = _content;
    if (content == null || content.paragraphs.isEmpty) return;
    final index = _currentIndex.clamp(0, content.paragraphs.length - 1);
    final paragraph = content.paragraphs[index];
    final ratio = content.paragraphs.length <= 1
        ? 0.0
        : index / (content.paragraphs.length - 1);
    unawaited(
      ref
          .read(readerRepositoryProvider)
          .saveProgress(
            ReaderProgress(
              bookId: widget.bookId,
              chapterId: widget.chapterId,
              paragraphId: paragraph.id,
              paragraphIndex: index,
              sentenceId: _lastSentence?.id,
              positionRatio: ratio,
            ),
          ),
    );
  }

  void _maybeAutoTranslate() {
    final settings = ref.read(settingsProvider);
    final content = _content;
    if (!settings.autoTranslate || content == null) return;
    if (content.status.translated >= content.status.total) return;
    if (_activeTask != null || _translating) return;
    if (_autoTriggered.contains(widget.chapterId)) return;
    _autoTriggered.add(widget.chapterId);
    _translate(automatic: true);
  }

  Future<void> _translate({
    bool retranslate = false,
    bool automatic = false,
  }) async {
    final content = _content;
    if (content == null) return;
    if (_activeTask != null || _translating) return;
    if (!retranslate && content.status.translated >= content.status.total) {
      _toast('本章已全部翻译');
      return;
    }
    try {
      setState(() {
        _translating = true;
        _translatingLabel = '正在准备本地翻译任务';
      });
      final task = await ref
          .read(readerRepositoryProvider)
          .startTranslation(widget.chapterId, retranslate: retranslate);
      if (!mounted) return;
      setState(() {
        _activeTask = task;
        _translating = false;
        _translatingLabel = '';
      });
      _startTaskPolling(task);
      if (!automatic) _toast('已创建本地翻译任务');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _translating = false;
        _translatingLabel = '';
      });
      _toast('翻译请求失败：$error');
    }
  }

  String _translatingLabel = '';

  void _startTaskPolling(TaskInfo task) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        final updated = await ref.read(readerRepositoryProvider).task(task.id);
        if (!mounted) return;
        setState(() => _activeTask = updated);
        if (updated.isFinished) {
          timer.cancel();
          _pollTimer = null;
          if (!mounted) return;
          setState(() {
            _activeTask = null;
            _translating = false;
          });
          if (updated.status == 'completed' || updated.status == 'partial') {
            await _load(force: true);
            _toast(
              updated.status == 'partial'
                  ? '翻译完成，但有 ${updated.failedCount} 句失败'
                  : '本章翻译完成',
            );
          } else if (updated.status == 'failed') {
            _toast(updated.error ?? '翻译任务失败');
          }
        }
      } catch (_) {
        // Keep polling; the local task may still be running.
      }
    });
  }

  Future<void> _pollActiveTaskOnce() async {
    final task = _activeTask;
    if (task == null) return;
    try {
      final updated = await ref.read(readerRepositoryProvider).task(task.id);
      if (!mounted) return;
      setState(() => _activeTask = updated);
      if (updated.isFinished) {
        _pollTimer?.cancel();
        setState(() {
          _activeTask = null;
          _translating = false;
        });
        await _load(force: true);
      }
    } catch (_) {}
  }

  Future<void> _cancelTranslation() async {
    final task = _activeTask;
    if (task == null) return;
    try {
      await ref.read(readerRepositoryProvider).cancelTask(task.id);
      _pollTimer?.cancel();
      setState(() {
        _activeTask = null;
        _translating = false;
      });
      _toast('已请求取消翻译任务');
    } catch (error) {
      _toast('取消失败：$error');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _changeMode(ReaderMode value) {
    if (_mode == value) return;
    setState(() => _mode = value);
    _jumpToCurrent();
  }

  void _changeSide(IndependentSide value) {
    if (_side == value) return;
    setState(() => _side = value);
    _jumpToCurrent();
  }

  Future<void> _openSearch() async {
    final content = _content;
    if (content == null) return;
    final index = await showSearch<int?>(
      context: context,
      delegate: ChapterSearchDelegate(content),
    );
    if (index != null && index >= 0 && index < content.paragraphs.length) {
      setState(() => _currentIndex = index);
      _jumpToCurrent();
    }
  }

  Future<void> _openToc() async {
    final id = await showTocSheet(context, _chapters, widget.chapterId);
    if (id != null && id != widget.chapterId) {
      final chapter = _chapters.firstWhere((c) => c.id == id);
      _replaceChapter(chapter);
    }
  }

  Future<void> _openAssistant() async {
    final content = _content;
    if (content == null) return;
    await showAssistantSheet(
      context,
      content: content,
      sentence: _lastSentence,
    );
  }

  Future<void> _addBookmark() async {
    final content = _content;
    if (content == null || content.paragraphs.isEmpty) return;
    final index = _currentIndex.clamp(0, content.paragraphs.length - 1);
    final paragraph = content.paragraphs[index];
    try {
      await ref
          .read(readerRepositoryProvider)
          .createBookmark(
            bookId: widget.bookId,
            chapterId: widget.chapterId,
            paragraphId: paragraph.id,
            sentenceId: _lastSentence?.id,
            label: '${content.chapterTitle} · 第 ${paragraph.ordinal + 1} 段',
            positionRatio: content.paragraphs.length <= 1
                ? 0
                : index / (content.paragraphs.length - 1),
          );
      if (mounted) setState(() => _bookmarked = true);
      _toast('书签已添加');
    } catch (error) {
      _toast('添加书签失败：$error');
    }
  }

  void _replaceChapter(ChapterSummary chapter) {
    _persistProgress();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          bookId: widget.bookId,
          chapterId: chapter.id,
          chapterTitle: chapter.title,
          bookTitle: _content?.bookTitle ?? widget.bookTitle,
          initialMode: _mode,
        ),
      ),
    );
  }

  Future<void> _openSentence(Sentence sentence, Paragraph paragraph) async {
    final content = _content;
    if (content == null) return;
    setState(() => _lastSentence = sentence);
    await showSentenceSheet(
      context,
      bookId: widget.bookId,
      content: content,
      paragraph: paragraph,
      sentence: sentence,
    );
    if (mounted) await _load(force: true);
  }

  void _openParagraph(Paragraph paragraph) {
    final content = _content;
    if (content == null) return;
    showParagraphSheet(
      context,
      content: content,
      paragraph: paragraph,
      onSentenceTap: (sentence) => _openSentence(sentence, paragraph),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final content = _content;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            _persistProgress();
            Navigator.of(context).pop();
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              content?.chapterTitle ?? widget.chapterTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(fontFamily: 'serif'),
            ),
            Text(
              content?.bookTitle ?? widget.bookTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '章节内搜索',
            onPressed: _openSearch,
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: '目录',
            onPressed: _openToc,
            icon: const Icon(Icons.format_list_bulleted_rounded),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (value) {
              switch (value) {
                case 'translate':
                  _translate();
                case 'retranslate':
                  _translate(retranslate: true);
                case 'assistant':
                  _openAssistant();
                case 'bookmark':
                  _addBookmark();
                case 'settings':
                  showReaderSettings(context);
                case 'notes':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => NotesScreen(
                        bookId: widget.bookId,
                        bookTitle: _content?.bookTitle ?? widget.bookTitle,
                      ),
                    ),
                  );
                case 'book':
                  Navigator.of(context).pop();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'translate',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.translate_rounded),
                  title: const Text('翻译本章'),
                  subtitle: const Text('本地 AI 翻译，人工译文不会被覆盖'),
                ),
              ),
              const PopupMenuItem(
                value: 'retranslate',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh_rounded),
                  title: Text('重新翻译本章'),
                  subtitle: Text('人工译文不会被覆盖'),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'assistant',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.auto_awesome_outlined),
                  title: Text('AI 阅读助手'),
                ),
              ),
              PopupMenuItem(
                value: 'bookmark',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _bookmarked
                        ? Icons.bookmark_added
                        : Icons.bookmark_add_outlined,
                  ),
                  title: const Text('添加书签'),
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.text_fields_rounded),
                  title: Text('阅读设置'),
                ),
              ),
              const PopupMenuItem(
                value: 'notes',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.sticky_note_2_outlined),
                  title: Text('笔记与书签'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _TranslationBanner(
            content: content,
            translating: _translating,
            translatingLabel: _translatingLabel,
            activeTask: _activeTask,
            onTranslate: () => _translate(),
            onRetranslate: () => _translate(retranslate: true),
            onCancel: _cancelTranslation,
            onRefresh: () => _load(force: true),
          ),
          ReaderModeBar(
            mode: _mode,
            side: _side,
            onModeChanged: _changeMode,
            onSideChanged: _changeSide,
          ),
          Expanded(child: _buildBody(settings, theme)),
          if (content != null && content.paragraphs.isNotEmpty)
            _ReadingFooter(
              progress: content.paragraphs.length <= 1
                  ? 1
                  : (_currentIndex + 1) / content.paragraphs.length,
              index: _currentIndex,
              total: content.paragraphs.length,
            ),
        ],
      ),
    );
  }

  Widget _buildBody(AppSettings settings, ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _content == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 42,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text('章节加载失败', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => _load(force: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    final content = _content;
    if (content == null || content.paragraphs.isEmpty) {
      return const Center(child: Text('本章没有可显示的正文'));
    }
    return ScrollablePositionedList.builder(
      itemScrollController: _scrollController,
      itemPositionsListener: _positionsListener,
      initialScrollIndex: _initialIndex,
      padding: EdgeInsets.zero,
      itemCount: content.paragraphs.length + 1,
      itemBuilder: (context, index) {
        if (index >= content.paragraphs.length) {
          return _ChapterFooter(
            content: content,
            chapters: _chapters,
            onNavigate: _replaceChapter,
          );
        }
        final paragraph = content.paragraphs[index];
        return ReaderParagraph(
          paragraph: paragraph,
          mode: _mode,
          side: _side,
          fontSize: settings.fontSize,
          lineHeight: settings.lineHeight,
          current: index == _currentIndex,
          onSentenceTap: (sentence) => _openSentence(sentence, paragraph),
          onParagraphTap: () => _openParagraph(paragraph),
        );
      },
    );
  }
}

class _TranslationBanner extends StatelessWidget {
  const _TranslationBanner({
    required this.content,
    required this.translating,
    required this.translatingLabel,
    required this.activeTask,
    required this.onTranslate,
    required this.onRetranslate,
    required this.onCancel,
    required this.onRefresh,
  });

  final ChapterContent? content;
  final bool translating;
  final String translatingLabel;
  final TaskInfo? activeTask;
  final VoidCallback onTranslate;
  final VoidCallback onRetranslate;
  final VoidCallback onCancel;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = content?.status;
    final active = activeTask != null || translating;
    final percent = status == null || status.total == 0
        ? 0.0
        : status.translated / status.total;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 7, 12, 7),
      color: theme.colorScheme.surface.withValues(alpha: 0.6),
      child: Row(
        children: [
          Icon(
            Icons.translate_rounded,
            size: 15,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      active
                          ? (translating
                                ? (translatingLabel.isEmpty
                                      ? '正在准备翻译…'
                                      : translatingLabel)
                                : '翻译中 ${activeTask!.progress.round()}%')
                          : (status == null
                                ? '翻译状态未知'
                                : '${status.translated}/${status.total} 句已译 · ${status.percent.round()}%'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10.5,
                        color: active
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.55,
                              ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '· 本地 AI',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.32,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: active
                        ? (activeTask != null
                              ? (activeTask!.progress / 100).clamp(0, 1)
                              : 0.1)
                        : percent.clamp(0, 1),
                    minHeight: 3,
                    backgroundColor: theme.colorScheme.onSurface.withValues(
                      alpha: 0.06,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (activeTask != null)
            IconButton(
              tooltip: '取消翻译',
              onPressed: onCancel,
              icon: const Icon(Icons.stop_circle_outlined, size: 20),
              visualDensity: VisualDensity.compact,
            )
          else if (translating)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            PopupMenuButton<String>(
              tooltip: '翻译',
              onSelected: (value) {
                if (value == 'retranslate') {
                  onRetranslate();
                } else {
                  onTranslate();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'translate', child: Text('翻译未完成部分')),
                PopupMenuItem(
                  value: 'retranslate',
                  child: Text('重新翻译本章（保护人工译文）'),
                ),
              ],
              icon: Icon(
                status != null &&
                        status.translated > 0 &&
                        status.translated < status.total
                    ? Icons.play_circle_outline
                    : Icons.translate_rounded,
                size: 20,
              ),
            ),
          IconButton(
            tooltip: '刷新章节',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 19),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _ChapterFooter extends StatelessWidget {
  const _ChapterFooter({
    required this.content,
    required this.chapters,
    required this.onNavigate,
  });
  final ChapterContent content;
  final List<ChapterSummary> chapters;
  final void Function(ChapterSummary chapter) onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    ChapterSummary? find(String? id) {
      if (id == null) return null;
      for (final chapter in chapters) {
        if (chapter.id == id) return chapter;
      }
      return null;
    }

    final previous = find(content.previousChapterId);
    final next = find(content.nextChapterId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 120),
      child: Column(
        children: [
          Row(
            children: const [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '终',
                  style: TextStyle(fontFamily: 'serif', fontSize: 13),
                ),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: previous == null
                    ? const SizedBox()
                    : OutlinedButton.icon(
                        onPressed: () => onNavigate(previous),
                        icon: const Icon(Icons.chevron_left, size: 18),
                        label: Text(
                          '上一章',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: next == null
                    ? const SizedBox()
                    : FilledButton.tonalIcon(
                        onPressed: () => onNavigate(next),
                        icon: const Icon(Icons.chevron_right, size: 18),
                        label: Text(
                          '下一章',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '原文与译文均保留出处 · ${content.bookTitle}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              fontSize: 9.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingFooter extends StatelessWidget {
  const _ReadingFooter({
    required this.progress,
    required this.index,
    required this.total,
  });
  final double progress;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 13,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
          const SizedBox(width: 6),
          Text(
            '第 ${index + 1}/$total 段',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9.5,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 2.5,
                backgroundColor: theme.colorScheme.onSurface.withValues(
                  alpha: 0.06,
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Text(
            '${(progress * 100).round()}%',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9.5,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
            ),
          ),
        ],
      ),
    );
  }
}
