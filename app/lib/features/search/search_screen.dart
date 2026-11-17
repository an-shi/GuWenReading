import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local/local_models.dart';
import '../../core/providers.dart';
import '../knowledge/knowledge_screen.dart';
import '../reader/reader_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _scope = 'all';
  bool _loading = false;
  LocalSearchResults? _results;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() => _results = null);
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await ref
          .read(searchServiceProvider)
          .search(query, scope: _scope);
      if (!mounted) return;
      setState(() => _results = results);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 60),
              children: [
                Text(
                  '知识检索',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 2,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                  ),
                ),
                Text('检索', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(
                  '在原文、译文、人物与历史事件中检索，并回到具体史料位置。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: '搜索原文、译文、人物或事件，例如：轩辕、贞观、淝水之战',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      onPressed: _search,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final scope in const [
                      ('all', '全部'),
                      ('original', '原文'),
                      ('translation', '译文'),
                    ])
                      ChoiceChip(
                        label: Text(scope.$2),
                        selected: _scope == scope.$1,
                        onSelected: (_) {
                          setState(() => _scope = scope.$1);
                          if (_controller.text.trim().isNotEmpty) _search();
                        },
                      ),
                  ],
                ),
                if (_loading) ...[
                  const SizedBox(height: 24),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (!_loading && _results != null) ...[
                  const SizedBox(height: 20),
                  _sectionHeader(theme, '原文匹配', _results!.sentences.length),
                  for (final hit in _results!.sentences)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text.rich(
                          _highlight(hit.text, _controller.text.trim(), theme),
                          style: const TextStyle(
                            fontFamily: 'serif',
                            fontSize: 15,
                            height: 1.7,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '《${hit.bookTitle}》 · ${hit.chapterTitle} · ${hit.docType == 'translation' ? '译文' : '原文'}'
                            '${hit.docType == 'translation' && hit.originalText != null ? '\n${hit.originalText}' : ''}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.45,
                              ),
                              height: 1.5,
                            ),
                          ),
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ReaderScreen(
                                bookId: hit.bookId,
                                chapterId: hit.chapterId,
                                chapterTitle: hit.chapterTitle,
                                bookTitle: hit.bookTitle,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  if (_results!.entities.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _sectionHeader(theme, '人物与实体', _results!.entities.length),
                    for (final entity in _results!.entities)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.primary
                                .withValues(alpha: 0.09),
                            child: Text(
                              entity.name.characters.first,
                              style: const TextStyle(fontFamily: 'serif'),
                            ),
                          ),
                          title: Text(
                            entity.name,
                            style: const TextStyle(fontFamily: 'serif'),
                          ),
                          subtitle: Text(
                            '${_kindLabel(entity.kind)}${entity.dynasty == null ? '' : ' · ${entity.dynasty}'}${entity.summary == null ? '' : '\n${entity.summary}'}',
                          ),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    EntityDetailScreen(entityId: entity.id),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                  if (_results!.events.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _sectionHeader(theme, '历史事件', _results!.events.length),
                    for (final event in _results!.events)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.event_note_outlined),
                          title: Text(
                            event.name,
                            style: const TextStyle(fontFamily: 'serif'),
                          ),
                          subtitle: Text(
                            '${event.eventType}${event.timeRaw == null ? '' : ' · ${event.timeRaw}'}',
                          ),
                        ),
                      ),
                  ],
                  if (_results!.total == 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 30),
                      child: Text(
                        '没有找到相关内容。尝试更短的关键词或切换检索范围。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.45,
                          ),
                        ),
                      ),
                    ),
                ],
                if (!_loading && _results == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 30),
                    child: Text(
                      '输入关键词开始检索。所有结果都来自本机数据库。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.45,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 6),
      child: Row(
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
            ),
          ),
        ],
      ),
    );
  }

  String _kindLabel(String kind) => switch (kind) {
    'person' => '人物',
    'place' => '地点',
    'dynasty' => '朝代/政权',
    'office' => '职官',
    'institution' => '机构',
    'work' => '典籍',
    _ => '其他',
  };

  TextSpan _highlight(String text, String query, ThemeData theme) {
    if (query.isEmpty) return TextSpan(text: text);
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    final needle = query.toLowerCase();
    var start = 0;
    while (start < text.length) {
      final index = lower.indexOf(needle, start);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: TextStyle(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = index + query.length;
    }
    return TextSpan(children: spans);
  }
}
