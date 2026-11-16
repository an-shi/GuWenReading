import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/storage/settings_controller.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../notes/notes_screen.dart';
import '../reader/reader_screen.dart';

class BookDetailScreen extends ConsumerStatefulWidget {
  const BookDetailScreen({super.key, required this.bookId});
  final String bookId;

  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  bool _downloading = false;
  int _downloadDone = 0;
  int _downloadTotal = 0;
  bool? _downloaded;

  @override
  void initState() {
    super.initState();
    _checkDownloaded();
  }

  Future<void> _checkDownloaded() async {
    final value = await ref.read(libraryRepositoryProvider).isDownloaded(widget.bookId);
    if (mounted) setState(() => _downloaded = value);
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _downloadDone = 0;
      _downloadTotal = 0;
    });
    try {
      await ref.read(libraryRepositoryProvider).downloadBook(
        widget.bookId,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _downloadDone = done;
              _downloadTotal = total;
            });
          }
        },
      );
      await _checkDownloaded();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('整本书已下载，可离线阅读')),
      );
    } on OfflineException catch (error) {
      _showError('${error.message}。请联网后再下载。');
    } catch (error) {
      _showError('下载失败：$error');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }

  Future<void> _openChapter(ChapterSummary chapter, Book book) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReaderScreen(
        bookId: widget.bookId,
        chapterId: chapter.id,
        chapterTitle: chapter.title,
        bookTitle: book.title,
      ),
    ));
    if (!mounted) return;
    ref.invalidate(bookProvider(widget.bookId));
    ref.invalidate(chaptersProvider(widget.bookId));
    ref.invalidate(progressProvider(widget.bookId));
  }

  @override
  Widget build(BuildContext context) {
    final bookAsync = ref.watch(bookProvider(widget.bookId));
    final chaptersAsync = ref.watch(chaptersProvider(widget.bookId));
    final progressAsync = ref.watch(progressProvider(widget.bookId));
    final theme = Theme.of(context);
    final api = ref.watch(apiClientProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(bookAsync.value?.title ?? '书籍'),
        actions: [
          IconButton(
            tooltip: '笔记与书签',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => NotesScreen(
                bookId: widget.bookId,
                bookTitle: bookAsync.value?.title,
              ),
            )),
            icon: const Icon(Icons.sticky_note_2_outlined),
          ),
          if (_downloaded == true)
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: Center(child: _OfflineTag()),
            ),
        ],
      ),
      body: bookAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _FullError(
          error: error,
          onRetry: () {
            ref.invalidate(bookProvider(widget.bookId));
            ref.invalidate(chaptersProvider(widget.bookId));
          },
        ),
        data: (book) {
          final chapters = chaptersAsync.value ?? const <ChapterSummary>[];
          final progress = progressAsync.value;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(bookProvider(widget.bookId));
              ref.invalidate(chaptersProvider(widget.bookId));
              ref.invalidate(progressProvider(widget.bookId));
              await ref.read(chaptersProvider(widget.bookId).future);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _BookHeader(
                    book: book,
                    api: api,
                    downloaded: _downloaded,
                    downloading: _downloading,
                    downloadDone: _downloadDone,
                    downloadTotal: _downloadTotal,
                    progress: progress,
                    chapters: chapters,
                    onDownload: _download,
                    onContinue: () {
                      if (chapters.isEmpty) return;
                      final target = chapters.firstWhere(
                        (chapter) => chapter.id == progress?.chapterId,
                        orElse: () => chapters.firstWhere(
                          (chapter) => chapter.sentenceCount > 0,
                          orElse: () => chapters.first,
                        ),
                      );
                      _openChapter(target, book);
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
                    child: Row(
                      children: [
                        Text('章节目录', style: theme.textTheme.titleLarge),
                        const Spacer(),
                        Text('${chapters.length} 章',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                            )),
                      ],
                    ),
                  ),
                ),
                if (chaptersAsync.isLoading && chapters.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (chaptersAsync.hasError && chapters.isEmpty)
                  SliverToBoxAdapter(
                    child: _InlineError(
                      message: '${chaptersAsync.error}',
                      onRetry: () => ref.invalidate(chaptersProvider(widget.bookId)),
                    ),
                  )
                else
                  SliverList.separated(
                    itemCount: chapters.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      indent: 20,
                      endIndent: 20,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                    ),
                    itemBuilder: (context, index) {
                      final chapter = chapters[index];
                      return _ChapterTile(
                        chapter: chapter,
                        isCurrent: progress?.chapterId == chapter.id,
                        onTap: () => _openChapter(chapter, book),
                      );
                    },
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BookHeader extends StatelessWidget {
  const _BookHeader({
    required this.book,
    required this.api,
    required this.downloaded,
    required this.downloading,
    required this.downloadDone,
    required this.downloadTotal,
    required this.progress,
    required this.chapters,
    required this.onDownload,
    required this.onContinue,
  });

  final Book book;
  final ApiClient api;
  final bool? downloaded;
  final bool downloading;
  final int downloadDone;
  final int downloadTotal;
  final ReaderProgress? progress;
  final List<ChapterSummary> chapters;
  final VoidCallback onDownload;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = api.absoluteUrl(book.coverPath);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.07),
            theme.colorScheme.surface.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: SizedBox(
                  width: 102,
                  height: 142,
                  child: cover.isNotEmpty
                      ? Image.network(cover, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _MiniCover(title: book.title))
                      : _MiniCover(title: book.title),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (book.category != null) _Tag(text: book.category!),
                        if (book.dynasty != null) _Tag(text: book.dynasty!),
                        _Tag(text: book.sourceFormat.toUpperCase()),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(book.title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontFamily: 'serif',
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: 4),
                    Text(book.author ?? '作者未详',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                        )),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _MiniStat(value: '${book.chapterCount}', label: '章'),
                        const SizedBox(width: 18),
                        _MiniStat(value: '${book.sentenceCount}', label: '句'),
                        const SizedBox(width: 18),
                        _MiniStat(value: '${book.translationPercent.round()}', label: '% 已译'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (book.description != null && book.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              book.description!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.56),
                height: 1.65,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: chapters.isEmpty ? null : onContinue,
                  icon: const Icon(Icons.menu_book_rounded, size: 19),
                  label: Text(progress == null ? '开始阅读' : '继续阅读'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: downloading ? null : (downloaded == true ? null : onDownload),
                  icon: downloading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(downloaded == true ? Icons.offline_pin : Icons.download_rounded, size: 19),
                  label: Text(
                    downloading
                        ? (downloadTotal == 0 ? '准备中' : '$downloadDone/$downloadTotal')
                        : (downloaded == true ? '已可离线' : '下载整本'),
                  ),
                ),
              ),
            ],
          ),
          if (downloading && downloadTotal > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: downloadDone / downloadTotal,
                minHeight: 4,
              ),
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.history_rounded,
                    size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                const SizedBox(width: 5),
                Text(
                  '上次读到第 ${chapters.indexWhere((c) => c.id == progress!.chapterId) + 1} 章',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({required this.chapter, required this.isCurrent, required this.onTap});
  final ChapterSummary chapter;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${chapter.ordinal + 1}'.padLeft(2, '0'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          chapter.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontFamily: 'serif',
                            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 7),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: (chapter.translationPercent / 100).clamp(0, 1),
                            minHeight: 3,
                            backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Text(
                        '${chapter.translationPercent.round()}%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 9.5,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.chevron_right_rounded,
                size: 19, color: theme.colorScheme.onSurface.withValues(alpha: 0.26)),
          ],
        ),
      ),
    );
  }
}

class _MiniCover extends StatelessWidget {
  const _MiniCover({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5145), Color(0xFF8B653B)],
        ),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            title.length > 8 ? title.substring(0, 8) : title,
            style: const TextStyle(
              fontFamily: 'serif',
              color: Color(0xFFF4EBDD),
              fontSize: 26,
              height: 1.1,
              letterSpacing: 3,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: 'serif',
              fontWeight: FontWeight.w700,
              fontSize: 18,
            )),
        const SizedBox(width: 2),
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9.5,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            )),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 9.5,
            color: theme.colorScheme.primary,
          )),
    );
  }
}

class _OfflineTag extends StatelessWidget {
  const _OfflineTag();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.offline_pin, size: 15, color: theme.colorScheme.primary),
        const SizedBox(width: 3),
        Text('离线可读',
            style: TextStyle(fontSize: 11, color: theme.colorScheme.primary)),
      ],
    );
  }
}

class _FullError extends StatelessWidget {
  const _FullError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = error is ApiException ? (error as ApiException).message : '$error';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
