import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local/local_errors.dart';
import '../../core/local/local_models.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../reader/reader_screen.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
    });
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      final current = ref.read(tasksProvider).value;
      if (current == null || current.any((task) => task.isActive)) {
        _refresh();
      } else {
        ref.invalidate(aiUsageSummaryProvider);
      }
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(aiUsageSummaryProvider);
    await ref.read(tasksProvider.notifier).refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tasksProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('任务中心', style: theme.textTheme.titleLarge),
            Text(
              '翻译与知识抽取状态',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _UsageSummaryCard(summary: ref.watch(aiUsageSummaryProvider)),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 38,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        error is ApiException ? error.message : '$error',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      FilledButton.tonal(
                        onPressed: _refresh,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (tasks) {
                if (tasks.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(36),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.task_alt_rounded,
                            size: 42,
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text('暂无任务', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 7),
                          Text(
                            '翻译与知识抽取任务会显示在这里。任务保存在本机，应用进入后台也不会丢失进度。',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.7,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.46,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 90),
                    itemCount: tasks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return _TaskCard(
                        task: task,
                        onCancel: task.isActive
                            ? () async {
                                try {
                                  await ref
                                      .read(tasksProvider.notifier)
                                      .cancel(task.id);
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('取消失败：$error')),
                                    );
                                  }
                                }
                              }
                            : null,
                        onResume: task.status == 'interrupted'
                            ? () async {
                                try {
                                  await ref
                                      .read(taskRecoveryServiceProvider)
                                      .resume(task);
                                  await _refresh();
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('恢复失败：$error')),
                                    );
                                  }
                                }
                              }
                            : null,
                        onOpen: task.bookId != null && task.chapterId != null
                            ? () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ReaderScreen(
                                    bookId: task.bookId!,
                                    chapterId: task.chapterId!,
                                    chapterTitle: '章节',
                                    bookTitle: '阅读',
                                  ),
                                ),
                              )
                            : null,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageSummaryCard extends StatelessWidget {
  const _UsageSummaryCard({required this.summary});

  final AsyncValue<AiUsageSummary> summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = summary.value;
    if (data == null) {
      return const SizedBox.shrink();
    }
    final totalInput =
        data.inputTokens + data.cacheReadTokens + data.cacheWriteTokens;
    return Card(
      margin: const EdgeInsets.fromLTRB(18, 10, 18, 0),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        leading: Icon(
          Icons.insights_rounded,
          size: 20,
          color: theme.colorScheme.primary,
        ),
        title: Text('AI 用量', style: theme.textTheme.titleSmall),
        subtitle: Text(
          '${_formatInt(data.requests)} 次调用 · 累计费用 ${_formatCost(data.cost)}'
          '${data.estimatedRequests > 0 ? ' · ${_formatInt(data.estimatedRequests)} 次为估算' : ''}'
          '${data.cost == 0 && data.requests > 0 ? '（未配置模型单价）' : ''}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _UsageMetric(label: '输入', value: _formatTokens(totalInput)),
              _UsageMetric(
                label: '输出',
                value: _formatTokens(data.outputTokens),
              ),
              _UsageMetric(
                label: '缓存读取',
                value: _formatTokens(data.cacheReadTokens),
              ),
              _UsageMetric(
                label: '缓存写入',
                value: _formatTokens(data.cacheWriteTokens),
              ),
              _UsageMetric(label: '费用', value: _formatCost(data.cost)),
            ],
          ),
          if (data.byType.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '按任务类型',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ),
            const SizedBox(height: 4),
            for (final group in data.byType)
              _UsageGroupRow(label: _taskTypeLabel(group.label), group: group),
          ],
          if (data.byModel.isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '按模型',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ),
            const SizedBox(height: 4),
            for (final group in data.byModel)
              _UsageGroupRow(label: group.label, group: group),
          ],
        ],
      ),
    );
  }
}

class _UsageMetric extends StatelessWidget {
  const _UsageMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(
        TextSpan(
          text: '$label ',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          children: [
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageGroupRow extends StatelessWidget {
  const _UsageGroupRow({required this.label, required this.group});

  final String label;
  final AiUsageGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens =
        group.inputTokens +
        group.outputTokens +
        group.cacheReadTokens +
        group.cacheWriteTokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          Text(
            '${_formatInt(group.requests)} 次 · ${_formatTokens(tokens)} tokens · '
            '${_formatCost(group.cost)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

String _taskTypeLabel(String type) => switch (type) {
  'translation' => '章节翻译',
  'knowledge_extraction' => '知识抽取',
  'entity_extraction' => '实体抽取',
  'relation_extraction' => '关系抽取',
  'event_extraction' => '事件抽取',
  'connection_test' => '连接测试',
  'disambiguation' => '实体消歧',
  'quality_check' => '质量检查',
  _ => '其他',
};

String _formatInt(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

String _formatTokens(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return _formatInt(value);
}

String _formatCost(double value) {
  if (value <= 0) return '0';
  if (value < 0.0001) return value.toStringAsExponential(2);
  if (value < 1) return value.toStringAsFixed(4);
  return value.toStringAsFixed(2);
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    this.onCancel,
    this.onResume,
    this.onOpen,
  });
  final TaskInfo task;
  final VoidCallback? onCancel;
  final VoidCallback? onResume;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (statusLabel, statusColor) = switch (task.status) {
      'queued' => ('排队中', theme.colorScheme.tertiary),
      'running' => ('进行中', theme.colorScheme.primary),
      'completed' => ('已完成', theme.colorScheme.primary),
      'partial' => ('部分完成', theme.colorScheme.tertiary),
      'failed' => ('失败', theme.colorScheme.error),
      'paused' => ('已暂停', theme.colorScheme.tertiary),
      'interrupted' => ('已中断', theme.colorScheme.error),
      'cancelled' => (
        '已取消',
        theme.colorScheme.onSurface.withValues(alpha: 0.45),
      ),
      _ => (task.status, theme.colorScheme.onSurface),
    };
    final typeLabel = switch (task.type) {
      'translation' => 'AI 翻译',
      'knowledge_extraction' => '知识抽取',
      _ => task.type,
    };
    final value = task.total > 0
        ? (task.completed / task.total).clamp(0, 1).toDouble()
        : task.progress / 100;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: task.status == 'queued' || task.status == 'running'
                      ? Padding(
                          padding: const EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: statusColor,
                          ),
                        )
                      : Icon(
                          task.status == 'failed'
                              ? Icons.error_outline
                              : task.status == 'paused'
                              ? Icons.pause_circle_outline
                              : task.status == 'interrupted'
                              ? Icons.restore_rounded
                              : task.status == 'cancelled'
                              ? Icons.stop_circle_outlined
                              : Icons.check_rounded,
                          size: 18,
                          color: statusColor,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(fontSize: 9, color: statusColor),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            typeLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 9.5,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.42,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${task.progress.round()}%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 9.5,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.42,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (task.stage != null && task.stage!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          task.stage!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9.5,
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.65,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 4,
                color: statusColor,
                backgroundColor: theme.colorScheme.onSurface.withValues(
                  alpha: 0.06,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  task.total > 0
                      ? '${task.completed}/${task.total} 完成${task.failedCount > 0 ? ' · ${task.failedCount} 失败' : ''}'
                      : '进度 ${task.progress.round()}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9.5,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                const Spacer(),
                if (onResume != null)
                  TextButton.icon(
                    onPressed: onResume,
                    icon: const Icon(Icons.restore_rounded, size: 14),
                    label: const Text('恢复', style: TextStyle(fontSize: 11)),
                  ),
                if (onOpen != null)
                  TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: const Text('打开', style: TextStyle(fontSize: 11)),
                  ),
                if (onCancel != null)
                  TextButton(
                    onPressed: onCancel,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    child: const Text('取消', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
            if (task.requests > 0) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  Text(
                    '${task.requests} 次调用',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9.5,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.46,
                      ),
                    ),
                  ),
                  Text(
                    '输入 ${_formatTokens(task.inputTokens + task.cacheReadTokens + task.cacheWriteTokens)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9.5,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.46,
                      ),
                    ),
                  ),
                  Text(
                    '输出 ${_formatTokens(task.outputTokens)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9.5,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.46,
                      ),
                    ),
                  ),
                  if (task.cacheReadTokens > 0)
                    Text(
                      '缓存 ${_formatTokens(task.cacheReadTokens)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9.5,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.46,
                        ),
                      ),
                    ),
                  if (task.estimatedUsage > 0)
                    Text(
                      '估算 ${task.estimatedUsage} 次',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9.5,
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  Text(
                    '费用 ${_formatCost(task.cost)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9.5,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.46,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (task.error != null) ...[
              const SizedBox(height: 7),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  task.error!,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.error,
                    height: 1.6,
                  ),
                ),
              ),
            ],
            if (task.result.isNotEmpty && task.isFinished) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  for (final entry in _resultRows(task))
                    Text(
                      '${entry.key} ${entry.value}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9.5,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.46,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<MapEntry<String, dynamic>> _resultRows(TaskInfo task) {
    const labels = {
      'completed': '完成',
      'failed': '失败',
      'cached': '缓存',
      'entities_created': '人物',
      'entities_matched': '复用人物',
      'relations_created': '关系',
      'relations_matched': '复用关系',
      'events_created': '事件',
      'events_matched': '合并事件',
      'cached_chunks': '缓存块',
      'chunks': '文本块',
    };
    return task.result.entries
        .where((entry) => labels.containsKey(entry.key))
        .map((entry) => MapEntry(labels[entry.key]!, entry.value))
        .toList();
  }
}
