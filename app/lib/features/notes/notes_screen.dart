import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local/local_errors.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../reader/reader_screen.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key, required this.bookId, this.bookTitle});
  final String bookId;
  final String? bookTitle;

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  List<Annotation> _annotations = const [];
  List<Bookmark> _bookmarks = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(readerRepositoryProvider);
      final annotations = await repository.annotations(widget.bookId);
      final bookmarks = await repository.bookmarks(widget.bookId);
      if (!mounted) return;
      setState(() {
        _annotations = annotations;
        _bookmarks = bookmarks;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is ApiException ? error.message : '$error';
      });
    }
  }

  Future<void> _removeAnnotation(Annotation annotation) async {
    final confirmed = await _confirm('删除这条批注？', annotation.content);
    if (!confirmed) return;
    try {
      await ref.read(readerRepositoryProvider).deleteAnnotation(annotation);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  Future<void> _removeBookmark(Bookmark bookmark) async {
    final confirmed = await _confirm('删除这个书签？', bookmark.label ?? '');
    if (!confirmed) return;
    try {
      await ref.read(readerRepositoryProvider).deleteBookmark(bookmark);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  Future<bool> _confirm(String title, String body) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body, maxLines: 4, overflow: TextOverflow.ellipsis),
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
        ) ??
        false;
  }

  void _open({String? chapterId}) {
    if (chapterId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          bookId: widget.bookId,
          chapterId: chapterId,
          chapterTitle: '章节',
          bookTitle: widget.bookTitle ?? '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('笔记与书签', style: theme.textTheme.titleLarge),
              if (widget.bookTitle != null)
                Text(
                  widget.bookTitle!,
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
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: '批注 ${_annotations.length}'),
              Tab(text: '书签 ${_bookmarks.length}'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _NotesError(message: _error!, onRetry: _load)
            : TabBarView(
                children: [
                  _annotations.isEmpty
                      ? const _NotesEmpty(
                          icon: Icons.edit_note_outlined,
                          title: '还没有批注',
                          body: '阅读时点击句子，在句子详情中添加批注。',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 80),
                          itemCount: _annotations.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 9),
                          itemBuilder: (context, index) {
                            final annotation = _annotations[index];
                            return Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () =>
                                    _open(chapterId: annotation.chapterId),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.comment_outlined,
                                            size: 15,
                                            color: theme.colorScheme.primary,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '批注',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color:
                                                      theme.colorScheme.primary,
                                                ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            _date(annotation.createdAt),
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  fontSize: 9,
                                                  color: theme
                                                      .colorScheme
                                                      .onSurface
                                                      .withValues(alpha: 0.36),
                                                ),
                                          ),
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () =>
                                                _removeAnnotation(annotation),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              size: 17,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (annotation.quote != null)
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.fromLTRB(
                                            9,
                                            7,
                                            9,
                                            7,
                                          ),
                                          margin: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.secondary
                                                .withValues(alpha: 0.05),
                                            borderRadius: BorderRadius.circular(
                                              7,
                                            ),
                                            border: Border(
                                              left: BorderSide(
                                                color: theme
                                                    .colorScheme
                                                    .secondary
                                                    .withValues(alpha: 0.4),
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            annotation.quote!,
                                            style: const TextStyle(
                                              fontFamily: 'serif',
                                              fontSize: 12.5,
                                              height: 1.65,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        annotation.content,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          height: 1.7,
                                        ),
                                      ),
                                      if (annotation.dirty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          '等待同步',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: theme.colorScheme.tertiary,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                  _bookmarks.isEmpty
                      ? const _NotesEmpty(
                          icon: Icons.bookmark_outline,
                          title: '还没有书签',
                          body: '阅读时从右上角菜单添加书签，位置会保存在当前设备。',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 80),
                          itemCount: _bookmarks.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final bookmark = _bookmarks[index];
                            return Card(
                              child: ListTile(
                                onTap: () =>
                                    _open(chapterId: bookmark.chapterId),
                                leading: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.secondary
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.bookmark,
                                    size: 18,
                                    color: theme.colorScheme.secondary,
                                  ),
                                ),
                                title: Text(
                                  bookmark.label ?? '未命名书签',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: Text(
                                  '${bookmark.chapterId.substring(0, 8)}…',
                                  style: const TextStyle(fontSize: 10),
                                ),
                                trailing: IconButton(
                                  onPressed: () => _removeBookmark(bookmark),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
      ),
    );
  }

  String _date(String? value) {
    if (value == null) return '';
    final date = DateTime.tryParse(value);
    if (date == null) return '';
    return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _NotesEmpty extends StatelessWidget {
  const _NotesEmpty({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(35),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 13),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 7),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.7,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotesError extends StatelessWidget {
  const _NotesError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('无法加载笔记', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
