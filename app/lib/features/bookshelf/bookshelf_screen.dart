import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local/local_errors.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../book_detail/book_detail_screen.dart';

class BookshelfScreen extends ConsumerStatefulWidget {
  const BookshelfScreen({super.key});

  @override
  ConsumerState<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends ConsumerState<BookshelfScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _searchTimer;
  Timer? _importTimer;
  bool _importing = false;
  String? _importFilename;
  String? _importTitle;
  String? _importStage;
  String? _importError;
  double _importProgress = 0;
  int _importFileSize = 0;
  int _importElapsedSeconds = 0;
  DateTime? _importStartedAt;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _importTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _search(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), () {
      ref.read(bookshelfProvider.notifier).refresh(query: value);
    });
  }

  Future<void> _import() async {
    if (_importing) return;
    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'epub', 'docx', 'pdf'],
      );
    } catch (error) {
      _showError('无法打开文件选择器：$error');
      return;
    }
    if (files.isEmpty) return;
    final picked = files.first;
    var fileSize = 0;
    try {
      fileSize = await picked.length() ?? 0;
    } catch (_) {
      // Size is only informational; importing can continue without it.
    }
    final metadata = await _askImportMetadata(picked.name, fileSize);
    if (metadata == null) return;
    if (!mounted) return;

    _importTimer?.cancel();
    setState(() {
      _importing = true;
      _importError = null;
      _importFilename = picked.name;
      _importTitle = metadata['title'];
      _importStage = '正在读取文件';
      _importProgress = 0;
      _importFileSize = fileSize;
      _importElapsedSeconds = 0;
      _importStartedAt = DateTime.now();
    });
    _importTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final startedAt = _importStartedAt;
      if (!mounted || !_importing || startedAt == null) return;
      setState(() {
        _importElapsedSeconds = DateTime.now().difference(startedAt).inSeconds;
      });
    });
    _scrollToTop();

    Book? importedBook;
    try {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _importProgress = 0.02;
        _importStage = '文件读取完成，准备解析';
      });
      importedBook = await ref
          .read(bookshelfProvider.notifier)
          .importBook(
            filename: picked.name,
            bytes: bytes,
            title: metadata['title'],
            author: metadata['author'],
            dynasty: metadata['dynasty'],
            category: metadata['category'],
            tags: metadata['tags'],
            onProgress: (progress, message) {
              if (!mounted || !_importing) return;
              setState(() {
                _importProgress = progress.clamp(0, 1);
                _importStage = message;
              });
            },
          );
    } catch (error) {
      if (!mounted) return;
      final message = _friendlyImportError(error);
      _importTimer?.cancel();
      setState(() {
        _importing = false;
        _importError = message;
        _importProgress = 0;
      });
      _scrollToTop();
      return;
    }
    if (!mounted) return;
    _finishImport();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已导入《${importedBook.title}》 · '
          '${importedBook.chapterCount} 章 · ${importedBook.sentenceCount} 句',
        ),
      ),
    );
    await _openBook(importedBook);
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _finishImport() {
    _importTimer?.cancel();
    setState(() {
      _importing = false;
      _importError = null;
      _importFilename = null;
      _importTitle = null;
      _importStage = null;
      _importProgress = 0;
      _importElapsedSeconds = 0;
      _importStartedAt = null;
    });
  }

  void _clearImportError() {
    setState(() {
      _importError = null;
      _importFilename = null;
      _importTitle = null;
      _importStage = null;
      _importProgress = 0;
      _importFileSize = 0;
    });
  }

  String _friendlyImportError(Object error) {
    var text = error.toString().trim();
    text = text.replaceFirst(RegExp(r'^(Exception|Error):\s*'), '');
    if (text.length > 600) {
      text = '${text.substring(0, 600)}…';
    }
    return text.isEmpty ? '未知错误，请重新选择文件后再试。' : text;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  String _baseName(String? filename) {
    if (filename == null || filename.isEmpty) return '未知文件';
    return filename.replaceFirst(RegExp(r'\.[^.]+$'), '');
  }

  Future<Map<String, String?>?> _askImportMetadata(
    String filename,
    int fileSize,
  ) async {
    final title = TextEditingController();
    final author = TextEditingController();
    final dynasty = TextEditingController();
    final category = TextEditingController();
    final tags = TextEditingController();
    final result = await showDialog<Map<String, String?>?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入书籍'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.description_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$filename · ${_formatBytes(fileSize)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text('可留空，系统会从文件和正文中自动识别书名、作者与朝代。'),
                const SizedBox(height: 12),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: '书名（可选）'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: author,
                        decoration: const InputDecoration(labelText: '作者（可选）'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: dynasty,
                        decoration: const InputDecoration(labelText: '朝代（可选）'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: category,
                        decoration: const InputDecoration(labelText: '分类（可选）'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: tags,
                        decoration: const InputDecoration(
                          labelText: '标签（顿号分隔）',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              'title': title.text.trim().isEmpty ? null : title.text.trim(),
              'author': author.text.trim().isEmpty ? null : author.text.trim(),
              'dynasty': dynasty.text.trim().isEmpty
                  ? null
                  : dynasty.text.trim(),
              'category': category.text.trim().isEmpty
                  ? null
                  : category.text.trim(),
              'tags': tags.text.trim().isEmpty ? null : tags.text.trim(),
            }),
            child: const Text('开始导入'),
          ),
        ],
      ),
    );
    title.dispose();
    author.dispose();
    dynasty.dispose();
    category.dispose();
    tags.dispose();
    return result;
  }

  Future<void> _openBook(Book book) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BookDetailScreen(bookId: book.id)),
    );
    if (mounted) ref.read(bookshelfProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookshelfProvider);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(bookshelfProvider.notifier).refresh();
          },
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '古籍典藏',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    letterSpacing: 2.2,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.42),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '我的书架',
                                  style: theme.textTheme.headlineMedium,
                                ),
                              ],
                            ),
                          ),
                          const _LocalBadge(),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '原文完整保留，译文逐句对应。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _searchController,
                        onChanged: _search,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: '搜索书名、作者或简介',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () {
                                    _searchController.clear();
                                    _search('');
                                  },
                                ),
                        ),
                      ),
                      if (_importError != null) ...[
                        const SizedBox(height: 14),
                        _ImportErrorCard(
                          filename: _importFilename ?? '未知文件',
                          stage: _importStage,
                          message: _importError!,
                          onClose: _clearImportError,
                          onRetry: () {
                            _clearImportError();
                            _import();
                          },
                        ),
                      ] else if (_importing) ...[
                        const SizedBox(height: 14),
                        _ImportProgressCard(
                          title: (_importTitle?.trim().isNotEmpty ?? false)
                              ? _importTitle!.trim()
                              : _baseName(_importFilename),
                          filename: _importFilename ?? '未知文件',
                          fileSize: _importFileSize,
                          progress: _importProgress,
                          stage: _importStage ?? '正在准备',
                          elapsedSeconds: _importElapsedSeconds,
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              state.when(
                loading: () => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stack) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ErrorState(
                    error: error,
                    onRetry: () =>
                        ref.read(bookshelfProvider.notifier).refresh(),
                  ),
                ),
                data: (snapshot) {
                  if (snapshot.books.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyBookshelf(
                        onImport: _importing ? null : _import,
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 178,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            childAspectRatio: 0.62,
                          ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _BookCard(
                          book: snapshot.books[index],
                          onTap: () => _openBook(snapshot.books[index]),
                        ),
                        childCount: snapshot.books.length,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        icon: _importing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add_rounded),
        label: Text(
          _importing
              ? (_importProgress > 0
                    ? '导入 ${(_importProgress * 100).round()}%'
                    : '正在导入')
              : '导入古籍',
        ),
      ),
    );
  }
}

class _BookCard extends ConsumerWidget {
  const _BookCard({required this.book, required this.onTap});
  final Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cover = book.coverPath ?? '';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.045),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover.isNotEmpty)
                    Image.file(
                      File(cover),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _CoverFallback(title: book.title),
                    )
                  else
                    _CoverFallback(title: book.title),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        book.sourceFormat.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      book.author ?? '作者未详',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.48,
                        ),
                        fontSize: 11,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: (book.translationPercent / 100).clamp(
                                0,
                                1,
                              ),
                              minHeight: 4,
                              backgroundColor: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.07),
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          '${book.translationPercent.round()}%',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.45,
                            ),
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${book.chapterCount} 章 · ${book.sentenceCount} 句',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.38,
                        ),
                        fontSize: 9.5,
                      ),
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

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5145), Color(0xFF2A6654), Color(0xFF8B653B)],
        ),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            title.length > 12 ? title.substring(0, 12) : title,
            style: const TextStyle(
              color: Color(0xFFF4EBDD),
              fontSize: 34,
              height: 1.05,
              letterSpacing: 5,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _LocalBadge extends StatelessWidget {
  const _LocalBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.storage_outlined,
            size: 13,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            '本地存储',
            style: TextStyle(
              fontSize: 10.5,
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyBookshelf extends StatelessWidget {
  const _EmptyBookshelf({required this.onImport});
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.auto_stories_outlined, size: 34),
            ),
            const SizedBox(height: 18),
            Text('书架还是空的', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '导入 TXT、EPUB、DOCX 或文本型 PDF。\n书籍、译文和批注都保存在本机。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                height: 1.7,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add),
              label: const Text('导入第一本书'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = error is ApiException
        ? (error as ApiException).message
        : '$error';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storage_rounded,
              size: 42,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 14),
            Text('无法读取本地书架', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportProgressCard extends StatelessWidget {
  const _ImportProgressCard({
    required this.title,
    required this.filename,
    required this.fileSize,
    required this.progress,
    required this.stage,
    required this.elapsedSeconds,
  });

  final String title;
  final String filename;
  final int fileSize;
  final double progress;
  final String stage;
  final int elapsedSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (progress.clamp(0, 1) * 100).round();
    final active = progress <= 0.001;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 38,
                height: 38,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  value: active ? null : progress.clamp(0, 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '正在导入《$title》',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$filename · ${_formatBytes(fileSize)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                active ? '准备中' : '$percent%',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: active ? null : progress.clamp(0, 1),
              minHeight: 8,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  stage,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '已用时 ${_formatElapsed(elapsedSeconds)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
          if (elapsedSeconds >= 20)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '文件较大时解析会久一些，应用仍在工作，进度和用时每秒更新。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImportErrorCard extends StatelessWidget {
  const _ImportErrorCard({
    required this.filename,
    required this.stage,
    required this.message,
    required this.onClose,
    required this.onRetry,
  });

  final String filename;
  final String? stage;
  final String message;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: theme.colorScheme.error,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '导入失败',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (stage != null && stage!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '失败阶段：$stage',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
          const SizedBox(height: 8),
          SelectableText(
            message,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              TextButton(onPressed: onClose, child: const Text('关闭')),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('重新选择文件'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '大小未知';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatElapsed(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '$minutes 分 $rest 秒';
}
