import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local/local_engine/lexicon.dart';
import '../../providers.dart';

class LocalLexiconScreen extends ConsumerStatefulWidget {
  const LocalLexiconScreen({super.key});

  @override
  ConsumerState<LocalLexiconScreen> createState() => _LocalLexiconScreenState();
}

class _LocalLexiconScreenState extends ConsumerState<LocalLexiconScreen> {
  List<Map<String, Object?>> _entries = const [];
  bool _loading = true;
  String _query = '';
  String _kind = '全部';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await ref.read(localLexiconProvider).list();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  List<Map<String, Object?>> get _filtered {
    final query = _query.trim();
    return _entries.where((entry) {
      if (_kind != '全部' && entry['kind'] != _kind) return false;
      if (query.isEmpty) return true;
      return '${entry['word']}'.contains(query) ||
          '${entry['meanings']}'.contains(query);
    }).toList();
  }

  Map<String, int> get _kindCounts {
    final result = <String, int>{};
    for (final entry in _entries) {
      final kind = '${entry['kind'] ?? '其他'}';
      result[kind] = (result[kind] ?? 0) + 1;
    }
    return result;
  }

  static const _kinds = ['实词', '虚词', '专名', '代词', '其他'];

  List<Widget> _groupedTiles(ThemeData theme) {
    final widgets = <Widget>[];
    final filtered = _filtered;
    final groups = <String, List<Map<String, Object?>>>{};
    for (final entry in filtered) {
      groups.putIfAbsent('${entry['kind'] ?? '其他'}', () => []).add(entry);
    }
    final orderedKinds = [
      ..._kinds.where(groups.containsKey),
      ...groups.keys.where((kind) => !_kinds.contains(kind)),
    ];
    for (final kind in orderedKinds) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
          child: Row(
            children: [
              Text(
                kind,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${groups[kind]!.length} 条',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Divider(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                ),
              ),
            ],
          ),
        ),
      );
      for (final entry in groups[kind]!) {
        widgets.add(_tile(entry, theme));
      }
    }
    return widgets;
  }

  Widget _tile(Map<String, Object?> entry, ThemeData theme) {
    final values = (entry['meanings'] as List? ?? const [])
        .map((item) => '$item')
        .join('、');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 18,
        child: Text(
          '${entry['word']}'.isEmpty ? '?' : '${entry['word']}'.substring(0, 1),
          style: const TextStyle(fontSize: 13),
        ),
      ),
      title: Row(
        children: [
          Text(
            '${entry['word']}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color:
                  (entry['is_custom'] == 1
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.primary)
                      .withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${entry['kind']} · '
              '${entry['is_custom'] == 1 ? '自定义' : '内置'}',
              style: TextStyle(
                fontSize: 9.5,
                color: entry['is_custom'] == 1
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        '$values\n来源：${entry['source'] ?? '用户自定义'}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: Wrap(
        spacing: 2,
        children: [
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit_outlined, size: 19),
            onPressed: () => _edit(entry),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline, size: 19),
            onPressed: () => _delete(entry),
          ),
        ],
      ),
    );
  }

  Future<void> _edit([Map<String, Object?>? entry]) async {
    final word = TextEditingController(text: '${entry?['word'] ?? ''}');
    final meanings = TextEditingController(
      text: entry == null
          ? ''
          : (entry['meanings'] as List? ?? const []).join('\n'),
    );
    final source = TextEditingController(
      text: '${entry?['source'] ?? '用户自定义'}',
    );
    var kind = '${entry?['kind'] ?? '实词'}';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(entry == null ? '新增本地词条' : '编辑词条'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: word,
                  decoration: const InputDecoration(
                    labelText: '词语',
                    hintText: '如：走、妻子、之',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: '词性/类型'),
                  items: const [
                    DropdownMenuItem(value: '实词', child: Text('实词')),
                    DropdownMenuItem(value: '虚词', child: Text('虚词')),
                    DropdownMenuItem(value: '专名', child: Text('专名')),
                    DropdownMenuItem(value: '代词', child: Text('代词')),
                    DropdownMenuItem(value: '其他', child: Text('其他')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => kind = value ?? kind),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: meanings,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '现代释义（每行一个）',
                    hintText: '跑\n逃跑',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: source,
                  decoration: const InputDecoration(
                    labelText: '来源（可选）',
                    hintText: '用户自定义',
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('自定义词条优先于内置词条，但不会覆盖内置原始数据。'),
                ),
              ],
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
      ),
    );
    if (saved == true) {
      final values = meanings.text
          .split('\n')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (word.text.trim().isNotEmpty && values.isNotEmpty) {
        final service = ref.read(localLexiconProvider);
        final isCustom = entry?['is_custom'] == 1;
        if (isCustom && entry != null && entry['word'] != word.text.trim()) {
          await service.remove('${entry['id']}');
        }
        await service.upsert(
          word: word.text.trim(),
          kind: kind,
          meanings: values,
          source: source.text.trim().isEmpty ? '用户自定义' : source.text.trim(),
        );
        await _load();
      }
    }
    for (final controller in [word, meanings, source]) {
      controller.dispose();
    }
  }

  Future<void> _delete(Map<String, Object?> entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除词条'),
        content: Text('确定删除“${entry['word']}”吗？删除后本地翻译将回退到内置词条或原字。'),
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
      await ref.read(localLexiconProvider).remove('${entry['id']}');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('本地词库', style: theme.textTheme.headlineSmall),
              ),
              FilledButton.icon(
                onPressed: _edit,
                icon: const Icon(Icons.add),
                label: const Text('新增词条'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '词库共 ${_entries.length} 条（自定义 ${_entries.where((item) => item['is_custom'] == 1).length} 条）。'
            '编辑内置词条会创建个人覆盖，不修改内置原始记录。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索词语或释义',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: Text('全部 ${_entries.length}'),
                selected: _kind == '全部',
                onSelected: (_) => setState(() => _kind = '全部'),
              ),
              for (final kind in _kinds)
                ChoiceChip(
                  label: Text('$kind ${_kindCounts[kind] ?? 0}'),
                  selected: _kind == kind,
                  onSelected: (_) => setState(() => _kind = kind),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                ? Center(
                    child: Text(
                      _entries.isEmpty ? '词库为空。' : '没有匹配的词条。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.45,
                        ),
                      ),
                    ),
                  )
                : ListView(children: _groupedTiles(theme)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '内置词库版本：$lexiconVersion。本地推测结果仅作规则参考。',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
