import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphview/GraphView.dart';

import '../../core/local/local_models.dart';
import '../../providers.dart';
import '../knowledge/knowledge_screen.dart';

class GraphScreen extends ConsumerStatefulWidget {
  const GraphScreen({super.key});

  @override
  ConsumerState<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends ConsumerState<GraphScreen> {
  LocalGraphData? _data;
  bool _loading = true;
  String? _error;
  String? _centerId;
  String _relationType = '';
  int _depth = 2;
  bool _includePending = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref
          .read(knowledgeServiceProvider)
          .graph(
            centerId: _centerId,
            depth: _depth,
            includePending: _includePending,
          );
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entitiesAsync = ref.watch(entitiesProvider(''));
    final all = _data;
    final nodes = all?.nodes ?? const <GraphNode>[];
    final edges = (all?.edges ?? const <GraphEdge>[])
        .where(
          (edge) => _relationType.isEmpty || edge.relationType == _relationType,
        )
        .toList();
    final visibleIds = <String>{};
    for (final edge in edges) {
      visibleIds.add(edge.source);
      visibleIds.add(edge.target);
    }
    if (edges.isEmpty) visibleIds.addAll(nodes.map((node) => node.id));
    final visibleNodes = nodes
        .where((node) => visibleIds.contains(node.id))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('人物关系图谱'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _centerId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '以人物为中心',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('全部人物'),
                      ),
                      for (final entity in entitiesAsync.value ?? const [])
                        DropdownMenuItem<String?>(
                          value: entity.id,
                          child: Text(
                            entity.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() => _centerId = value);
                      _load();
                    },
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<String>(
                    initialValue: _relationType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '关系类型',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('全部')),
                      DropdownMenuItem(value: '父子', child: Text('父子')),
                      DropdownMenuItem(value: '母子', child: Text('母子')),
                      DropdownMenuItem(value: '兄弟', child: Text('兄弟')),
                      DropdownMenuItem(value: '夫妻', child: Text('夫妻')),
                      DropdownMenuItem(value: '君臣', child: Text('君臣')),
                      DropdownMenuItem(value: '主从', child: Text('主从')),
                      DropdownMenuItem(value: '同盟', child: Text('同盟')),
                      DropdownMenuItem(value: '敌对', child: Text('敌对')),
                      DropdownMenuItem(value: '师生', child: Text('师生')),
                      DropdownMenuItem(value: '任职', child: Text('任职')),
                      DropdownMenuItem(value: '其他', child: Text('其他')),
                    ],
                    onChanged: (value) =>
                        setState(() => _relationType = value ?? ''),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<int>(
                    initialValue: _depth,
                    decoration: const InputDecoration(
                      labelText: '层级',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1')),
                      DropdownMenuItem(value: 2, child: Text('2')),
                      DropdownMenuItem(value: 3, child: Text('3')),
                    ],
                    onChanged: (value) {
                      setState(() => _depth = value ?? 2);
                      _load();
                    },
                  ),
                ),
                FilterChip(
                  label: const Text('包含待审关系'),
                  selected: _includePending,
                  onSelected: (value) {
                    setState(() => _includePending = value);
                    _load();
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _Legend(color: theme.colorScheme.primary, label: '已确认/原文明确'),
                const SizedBox(width: 14),
                _Legend(color: theme.colorScheme.tertiary, label: 'AI 推断（待审核）'),
                const Spacer(),
                Text(
                  '${visibleNodes.length} 人 · ${edges.length} 条关系',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildGraph(theme, visibleNodes, edges)),
        ],
      ),
    );
  }

  Widget _buildGraph(
    ThemeData theme,
    List<GraphNode> nodes,
    List<GraphEdge> edges,
  ) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('图谱加载失败：$_error'));
    if (nodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hub_outlined, size: 48),
            const SizedBox(height: 12),
            Text('关系图谱尚未建立', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('先对章节运行知识抽取。AI 推断的关系会以待审状态显示。'),
          ],
        ),
      );
    }
    final graph = Graph();
    final graphNodes = <String, Node>{};
    for (final node in nodes) {
      final item = Node.Id(node.id);
      graphNodes[node.id] = item;
      graph.addNode(item);
    }
    for (final edge in edges) {
      final source = graphNodes[edge.source];
      final target = graphNodes[edge.target];
      if (source == null || target == null) continue;
      graph.addEdge(
        source,
        target,
        paint: Paint()
          ..color = edge.status == 'inferred'
              ? theme.colorScheme.tertiary.withValues(alpha: 0.55)
              : theme.colorScheme.primary.withValues(alpha: 0.6)
          ..strokeWidth = 1.4,
      );
    }
    final byId = {for (final node in nodes) node.id: node};
    return ClipRect(
      child: GraphView.builder(
        graph: graph,
        algorithm: FruchtermanReingoldAlgorithm(
          FruchtermanReingoldConfiguration(),
        ),
        autoZoomToFit: true,
        builder: (node) {
          final id = node.key?.value as String?;
          final item = id == null ? null : byId[id];
          if (item == null) return const SizedBox.shrink();
          return InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EntityDetailScreen(entityId: item.id),
                ),
              );
            },
            borderRadius: BorderRadius.circular(99),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: item.kind == 'person'
                      ? theme.colorScheme.primary.withValues(alpha: 0.35)
                      : theme.colorScheme.secondary.withValues(alpha: 0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 18, height: 2, color: color),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
