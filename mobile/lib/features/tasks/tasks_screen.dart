import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
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
      ref.read(tasksProvider.notifier).refresh();
    });
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      final current = ref.read(tasksProvider).value;
      if (current == null || current.any((task) => task.isActive)) {
        ref.read(tasksProvider.notifier).refresh();
      }
    });
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
            Text('翻译与知识抽取状态',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                )),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => ref.read(tasksProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded, size: 38, color: theme.colorScheme.error),
                const SizedBox(height: 12),
                Text(error is ApiException ? error.message : '$error',
                    textAlign: TextAlign.center),
                const SizedBox(height: 14),
                FilledButton.tonal(
                  onPressed: () => ref.read(tasksProvider.notifier).refresh(),
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
                    Icon(Icons.task_alt_rounded,
                        size: 42, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
                    const SizedBox(height: 14),
                    Text('暂无任务', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 7),
                    Text(
                      '翻译与知识抽取任务会显示在这里。任务在服务端持久化，应用进入后台也不会丢失进度。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.7,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.46),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(tasksProvider.notifier).refresh(),
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
                            await ref.read(tasksProvider.notifier).cancel(task.id);
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('取消失败：$error')),
                              );
                            }
                          }
                        }
                      : null,
                  onOpen: task.bookId != null && task.chapterId != null
                      ? () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ReaderScreen(
                              bookId: task.bookId!,
                              chapterId: task.chapterId!,
                              chapterTitle: '章节',
                              bookTitle: '阅读',
                            ),
                          ))
                      : null,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, this.onCancel, this.onOpen});
  final TaskInfo task;
  final VoidCallback? onCancel;
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
      'cancelled' => ('已取消', theme.colorScheme.onSurface.withValues(alpha: 0.45)),
      _ => (task.status, theme.colorScheme.onSurface),
    };
    final typeLabel = switch (task.type) {
      'translation' => 'AI 翻译',
      'knowledge_extraction' => '知识抽取',
      _ => task.type,
    };
    final value = task.total > 0 ? (task.completed / task.total).clamp(0, 1).toDouble() : task.progress / 100;
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
                  child: task.isActive
                      ? Padding(
                          padding: const EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2, color: statusColor),
                        )
                      : Icon(
                          task.status == 'failed'
                              ? Icons.error_outline
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
                      Text(task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontFamily: 'serif')),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(statusLabel,
                                style: TextStyle(fontSize: 9, color: statusColor)),
                          ),
                          const SizedBox(width: 6),
                          Text(typeLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 9.5,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                              )),
                          const Spacer(),
                          Text('${task.progress.round()}%',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 9.5,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                              )),
                        ],
                      ),
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
                backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
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
                if (onOpen != null)
                  TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: const Text('打开', style: TextStyle(fontSize: 11)),
                  ),
                if (onCancel != null)
                  TextButton(
                    onPressed: onCancel,
                    style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    child: const Text('取消', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
            if (task.error != null) ...[
              const SizedBox(height: 7),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(task.error!,
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.error, height: 1.6)),
              ),
            ],
            if (task.result.isNotEmpty && task.isFinished) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  for (final entry in _resultRows(task))
                    Text('${entry.key} ${entry.value}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 9.5,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.46),
                        )),
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
      'relations_created': '关系',
      'events_created': '事件',
    };
    return task.result.entries
        .where((entry) => labels.containsKey(entry.key))
        .map((entry) => MapEntry(labels[entry.key]!, entry.value))
        .toList();
  }
}
