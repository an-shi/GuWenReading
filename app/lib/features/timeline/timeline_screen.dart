import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../providers.dart';

class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  bool _includeExtracted = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(timelineProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史时间线'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => ref.invalidate(timelineProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('时间线加载失败：$error')),
        data: (all) {
          final events = all
              .where(
                (event) => _includeExtracted || event.status != 'extracted',
              )
              .toList();
          final dated =
              events.where((event) => event.timeStartYear != null).toList()
                ..sort((a, b) => a.timeStartYear!.compareTo(b.timeStartYear!));
          final undated = events
              .where((event) => event.timeStartYear == null)
              .toList();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 50),
                children: [
                  Row(
                    children: [
                      Text(
                        '${dated.length} 条有明确年份 · ${undated.length} 条时间待考',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.48,
                          ),
                        ),
                      ),
                      const Spacer(),
                      FilterChip(
                        label: const Text('包含 AI 抽取（待审）'),
                        selected: _includeExtracted,
                        onSelected: (value) =>
                            setState(() => _includeExtracted = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (dated.isNotEmpty)
                    _YearAxis(events: dated, onTap: _openEvent),
                  if (dated.isEmpty && undated.isEmpty)
                    _empty(theme)
                  else ...[
                    for (var index = 0; index < dated.length; index++)
                      _TimelineRow(
                        event: dated[index],
                        first: index == 0,
                        last: index == dated.length - 1,
                        onTap: () => _openEvent(dated[index]),
                      ),
                    if (undated.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text('时间待考', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      for (final event in undated)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.help_outline_rounded),
                            title: Text(
                              event.name,
                              style: const TextStyle(fontFamily: 'serif'),
                            ),
                            subtitle: Text(
                              '${event.eventType} · ${event.timeRaw ?? '原文未给出可换算时间'}',
                            ),
                            trailing: _StatusChip(status: event.status),
                            onTap: () => _openEvent(event),
                          ),
                        ),
                    ],
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _empty(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(
            Icons.timeline_rounded,
            size: 48,
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text('暂无可定位到年的时间线', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('先对章节运行知识抽取，AI 抽取的事件会以待审状态显示。'),
        ],
      ),
    );
  }

  Future<void> _openEvent(HistoricalEvent event) async {
    final detail = await ref.read(knowledgeServiceProvider).event(event.id);
    if (!mounted || detail == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.66,
        maxChildSize: 0.94,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    detail.name,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontFamily: 'serif'),
                  ),
                ),
                _StatusChip(status: detail.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${detail.eventType} · ${detail.dynasty ?? '朝代未详'} · ${detail.timeRaw ?? '时间待考'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.5),
              ),
            ),
            if (detail.description != null) ...[
              const SizedBox(height: 16),
              Text(detail.description!, style: const TextStyle(height: 1.8)),
            ],
            if (detail.participants.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('参与者', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final name in detail.participants)
                    Chip(label: Text(name)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text('史料出处', style: Theme.of(context).textTheme.titleSmall),
            if (detail.sources.isEmpty)
              const Text('暂无出处。')
            else
              for (final source in detail.sources)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary
                        .withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.quote ?? '',
                        style: const TextStyle(
                          fontFamily: 'serif',
                          height: 1.7,
                        ),
                      ),
                      if (source.bookTitle != null)
                        Text(
                          '${source.bookTitle} · ${source.chapterTitle ?? ''}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                    ],
                  ),
                ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (detail.status != 'confirmed')
                  FilledButton.tonal(
                    onPressed: () async {
                      await ref
                          .read(knowledgeServiceProvider)
                          .setEventStatus(detail.id, 'confirmed');
                      ref.invalidate(timelineProvider);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('确认史实'),
                  ),
                const SizedBox(width: 8),
                if (detail.status != 'rejected')
                  TextButton(
                    onPressed: () async {
                      await ref
                          .read(knowledgeServiceProvider)
                          .setEventStatus(detail.id, 'rejected');
                      ref.invalidate(timelineProvider);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('驳回'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _YearAxis extends StatelessWidget {
  const _YearAxis({required this.events, required this.onTap});
  final List<HistoricalEvent> events;
  final ValueChanged<HistoricalEvent> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final years = events.map((event) => event.timeStartYear!).toList();
    final minYear = years.reduce((a, b) => a < b ? a : b);
    final maxYear = years.reduce((a, b) => a > b ? a : b);
    final span = maxYear - minYear;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 38,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 18,
                      child: Container(
                        height: 1,
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.25,
                        ),
                      ),
                    ),
                    for (final event in events)
                      Positioned(
                        left: span == 0
                            ? constraints.maxWidth / 2 - 5
                            : (event.timeStartYear! - minYear) /
                                  span *
                                  (constraints.maxWidth - 10),
                        top: 13,
                        child: Tooltip(
                          message: '${event.name} · ${event.timeStartYear}',
                          child: InkWell(
                            onTap: () => onTap(event),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.colorScheme.surface,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Row(
            children: [
              Text(
                minYear < 0 ? '前${minYear.abs()}' : '$minYear',
                style: theme.textTheme.labelSmall,
              ),
              const Spacer(),
              Text(
                maxYear < 0 ? '前${maxYear.abs()}' : '$maxYear',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.event,
    required this.first,
    required this.last,
    required this.onTap,
  });
  final HistoricalEvent event;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 86,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                _formatYear(event.timeStartYear),
                textAlign: TextAlign.right,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 1,
                  height: 14,
                  color: first
                      ? Colors.transparent
                      : theme.colorScheme.outlineVariant,
                ),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 1,
                    color: last
                        ? Colors.transparent
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Card(
                child: ListTile(
                  title: Text(
                    event.name,
                    style: const TextStyle(fontFamily: 'serif', fontSize: 16),
                  ),
                  subtitle: Text(
                    '${event.eventType}${event.timeRaw == null ? '' : ' · ${event.timeRaw}'}'
                    '${event.description == null ? '' : '\n${event.description}'}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: _StatusChip(status: event.status),
                  onTap: onTap,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatYear(int? year) {
    if (year == null) return '时间待考';
    return year < 0 ? '前${year.abs()}' : '$year';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'confirmed' => '已确认',
      'rejected' => '已驳回',
      _ => '待审核',
    };
    return Chip(label: Text(label, style: const TextStyle(fontSize: 10)));
  }
}
