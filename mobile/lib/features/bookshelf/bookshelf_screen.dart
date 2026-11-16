import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/storage/settings_controller.dart';
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
  Timer? _searchTimer;
  bool _importing = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPending());
  }

  Future<void> _syncPending() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await ref.read(readerRepositoryProvider).flushPending();
    } catch (_) {
      // Sync is best-effort; local state remains authoritative.
    } finally {
      _syncing = false;
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _search(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), () {
      ref.read(bookshelfProvider.notifier).refresh(query: value);
    });
  }

  Future<void> _import() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'epub', 'docx', 'pdf'],
    );
    if (files.isEmpty) return;
    final picked = files.first;
    late final List<int> bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (_) {
      _showError('无法读取所选文件');
      return;
    }
    setState(() => _importing = true);
    try {
      final book = await ref.read(bookshelfProvider.notifier).importBook(
            filename: picked.name,
            bytes: bytes,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入《${book.title}》')),
      );
      await _openBook(book);
    } on OfflineException catch (error) {
      _showError('${error.message}。书籍导入需要后端解析服务。');
    } catch (error) {
      _showError('导入失败：$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Theme.of(context).colorScheme.error),
    );
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
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _syncPending();
            await ref.read(bookshelfProvider.notifier).refresh();
          },
          child: CustomScrollView(
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
                                Text('古籍典藏',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      letterSpacing: 2.2,
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                                      fontWeight: FontWeight.w700,
                                    )),
                                const SizedBox(height: 5),
                                Text('我的书架', style: theme.textTheme.headlineMedium),
                              ],
                            ),
                          ),
                          _OfflineBadge(
                            offline: state.value?.fromCache ?? false,
                            onSync: _syncPending,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '原文完整保留，译文逐句对应。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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
                      if (_importing) ...[
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: const LinearProgressIndicator(minHeight: 4),
                        ),
                        const SizedBox(height: 6),
                        Text('正在上传并解析书籍…',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            )),
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
                    onRetry: () => ref.read(bookshelfProvider.notifier).refresh(),
                    backendHint: settings.apiBase,
                  ),
                ),
                data: (snapshot) {
                  if (snapshot.books.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyBookshelf(onImport: _import),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
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
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.add_rounded),
        label: const Text('导入古籍'),
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
    final api = ref.watch(apiClientProvider);
    final cover = api.absoluteUrl(book.coverPath);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.06)),
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
                    Image.network(
                      cover,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _CoverFallback(title: book.title),
                    )
                  else
                    _CoverFallback(title: book.title),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        book.sourceFormat.toUpperCase(),
                        style: const TextStyle(fontSize: 9, color: Colors.white, letterSpacing: 0.8),
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
                        fontFamily: 'serif',
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
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.48),
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
                              value: (book.translationPercent / 100).clamp(0, 1),
                              minHeight: 4,
                              backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.07),
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text('${book.translationPercent.round()}%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                              fontSize: 9.5,
                            )),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${book.chapterCount} 章 · ${book.sentenceCount} 句',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
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
              fontFamily: 'serif',
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

class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge({required this.offline, required this.onSync});
  final bool offline;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: offline ? onSync : null,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: (offline ? theme.colorScheme.error : theme.colorScheme.primary).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              offline ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
              size: 13,
              color: offline ? theme.colorScheme.error : theme.colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              offline ? '离线缓存' : '已连接',
              style: TextStyle(
                fontSize: 10.5,
                color: offline ? theme.colorScheme.error : theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBookshelf extends StatelessWidget {
  const _EmptyBookshelf({required this.onImport});
  final VoidCallback onImport;

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
              '导入 TXT、EPUB、DOCX 或文本型 PDF。\n书籍会由后端解析并同步到手机。',
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
  const _ErrorState({required this.error, required this.onRetry, required this.backendHint});
  final Object error;
  final VoidCallback onRetry;
  final String backendHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = error is ApiException ? (error as ApiException).message : '$error';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 42, color: theme.colorScheme.error),
            const SizedBox(height: 14),
            Text('无法加载书架', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('接口：$backendHint',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                )),
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
