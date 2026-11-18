import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local/local_errors.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../graph/graph_screen.dart';
import '../reader/reader_screen.dart';
import '../timeline/timeline_screen.dart';

class KnowledgeScreen extends ConsumerStatefulWidget {
  const KnowledgeScreen({super.key});

  @override
  ConsumerState<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends ConsumerState<KnowledgeScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search() {
    setState(() => _query = _searchController.text.trim());
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
              Text('知识库', style: theme.textTheme.titleLarge),
              Text(
                '人物、事件、关系与时间线',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '人物关系图谱',
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const GraphScreen())),
              icon: const Icon(Icons.hub_outlined),
            ),
            IconButton(
              tooltip: '历史时间线',
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const TimelineScreen())),
              icon: const Icon(Icons.timeline_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: '搜索人物、事件或史料关键词',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    onPressed: _search,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ),
              ),
            ),
            const TabBar(
              tabs: [
                Tab(text: '人物'),
                Tab(text: '历史事件'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _EntityTab(query: _query),
                  _EventTab(query: _query),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntityTab extends ConsumerWidget {
  const _EntityTab({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entitiesProvider(query));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _KnowledgeError(
        error: error,
        onRetry: () => ref.invalidate(entitiesProvider(query)),
      ),
      data: (entities) {
        if (entities.isEmpty) {
          return const _KnowledgeEmpty(
            icon: Icons.account_tree_outlined,
            title: '暂无人物资料',
            body: '在书籍章节中运行知识抽取，人物与关系会出现在这里。',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(entitiesProvider(query)),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 90),
            itemCount: entities.length,
            separatorBuilder: (_, _) => const SizedBox(height: 9),
            itemBuilder: (context, index) {
              final entity = entities[index];
              return _EntityCard(entity: entity);
            },
          ),
        );
      },
    );
  }
}

class _EntityCard extends StatelessWidget {
  const _EntityCard({required this.entity});
  final HistoricalEntity entity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EntityDetailScreen(entityId: entity.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  entity.name.isEmpty ? '?' : entity.name.substring(0, 1),
                  style: TextStyle(
                    fontSize: 20,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entity.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _StatusPill(status: entity.status),
                        const SizedBox(width: 5),
                        _KnowledgeTypePill(type: entity.knowledgeType),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        _entityKindLabel(entity.kind),
                        if (entity.dynasty != null) entity.dynasty!,
                        if (entity.aliases.isNotEmpty)
                          entity.aliases.take(2).join('、'),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.46,
                        ),
                      ),
                    ),
                    if (entity.summary != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        entity.summary!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.55,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.55,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.24),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventTab extends ConsumerWidget {
  const _EventTab({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(eventsProvider(query));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _KnowledgeError(
        error: error,
        onRetry: () => ref.invalidate(eventsProvider(query)),
      ),
      data: (events) {
        if (events.isEmpty) {
          return const _KnowledgeEmpty(
            icon: Icons.timeline_outlined,
            title: '暂无历史事件',
            body: '运行知识抽取后，带有纪年信息的历史事件会出现在这里。',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(eventsProvider(query)),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 90),
            itemCount: events.length,
            separatorBuilder: (_, _) => const SizedBox(height: 9),
            itemBuilder: (context, index) => _EventCard(event: events[index]),
          ),
        );
      },
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});
  final HistoricalEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EventDetailScreen(eventId: event.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      event.eventType,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  _StatusPill(status: event.status),
                  const SizedBox(width: 5),
                  _KnowledgeTypePill(type: event.knowledgeType),
                  const Spacer(),
                  if (event.timeStartYear != null)
                    Text(
                      _formatYear(event.timeStartYear!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                event.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                event.timeRaw ?? '时间未详',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
              if (event.description != null) ...[
                const SizedBox(height: 5),
                Text(
                  event.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.55,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
              if (event.participants.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    for (final participant in event.participants.take(4))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondary.withValues(
                            alpha: 0.06,
                          ),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          participant,
                          style: const TextStyle(fontSize: 9.5),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _formatYear(int year) => year < 0 ? '公元前 ${year.abs()} 年' : '公元 $year 年';

String _entityKindLabel(String kind) => switch (kind) {
  'person' => '人物',
  'place' => '地点',
  'dynasty' => '朝代/政权',
  'office' => '职官',
  'institution' => '机构',
  'work' => '典籍',
  'other' => '其他',
  _ => kind,
};

class _KnowledgeTypePill extends StatelessWidget {
  const _KnowledgeTypePill({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (type) {
      'explicit' => ('原文明确', theme.colorScheme.primary),
      'cross_source_supported' => ('多源支持', theme.colorScheme.secondary),
      'disputed' => ('存在争议', theme.colorScheme.error),
      'human_verified' => ('人工确认', theme.colorScheme.primary),
      _ => ('AI 推断', theme.colorScheme.tertiary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(label, style: TextStyle(fontSize: 9, color: color)),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (status) {
      'confirmed' => ('已确认', theme.colorScheme.primary),
      'rejected' => ('已驳回', theme.colorScheme.error),
      _ => ('待审核', theme.colorScheme.tertiary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label, style: TextStyle(fontSize: 8.5, color: color)),
    );
  }
}

class EntityDetailScreen extends ConsumerWidget {
  const EntityDetailScreen({super.key, required this.entityId});
  final String entityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entityProvider(entityId));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('人物资料'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == '__merge') {
                await _mergeIntoOther(context, ref);
                return;
              }
              if (value == '__history') {
                await _showReviewHistory(context, ref);
                return;
              }
              await ref
                  .read(knowledgeServiceProvider)
                  .setEntityStatus(entityId, value);
              ref.invalidate(entityProvider(entityId));
              ref.invalidate(entitiesProvider);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'confirmed', child: Text('确认收录')),
              PopupMenuItem(value: 'pending', child: Text('标记待审')),
              PopupMenuItem(value: 'rejected', child: Text('驳回')),
              PopupMenuDivider(),
              PopupMenuItem(value: '__merge', child: Text('合并到其他人物')),
              PopupMenuItem(value: '__history', child: Text('审核与修改记录')),
            ],
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _KnowledgeError(
          error: error,
          onRetry: () => ref.invalidate(entityProvider(entityId)),
        ),
        data: (entity) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 50),
          children: [
            Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    entity.name.isEmpty ? '?' : entity.name.substring(0, 1),
                    style: TextStyle(
                      fontSize: 27,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              entity.name,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          _StatusPill(status: entity.status),
                          const SizedBox(width: 5),
                          _KnowledgeTypePill(type: entity.knowledgeType),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          _entityKindLabel(entity.kind),
                          if (entity.dynasty != null) entity.dynasty!,
                          if (entity.identity != null) entity.identity!,
                        ].join(' · '),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.46,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (entity.aliases.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '别名：${entity.aliases.join('、')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
            if (entity.summary != null) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.035),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  entity.summary!,
                  style: const TextStyle(height: 1.8, fontSize: 13.5),
                ),
              ),
            ],
            const SizedBox(height: 22),
            Text('人物关系', style: theme.textTheme.titleMedium),
            const SizedBox(height: 9),
            if (entity.relations.isEmpty)
              Text(
                '暂无关系记录',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                ),
              )
            else
              for (final relation in entity.relations)
                _RelationCard(entityId: entity.id, relation: relation),
            const SizedBox(height: 22),
            Text(
              '原文提及 · ${entity.mentions.length}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 9),
            for (final mention in entity.mentions)
              _MentionCard(mention: mention, bookTitle: null),
          ],
        ),
      ),
    );
  }

  Future<void> _mergeIntoOther(BuildContext context, WidgetRef ref) async {
    final entities = await ref.read(knowledgeServiceProvider).listEntities();
    if (!context.mounted) return;
    final candidates = entities.where((item) => item.id != entityId).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有可合并的其他人物')));
      return;
    }
    final target = await showDialog<HistoricalEntity>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('合并到已有实体'),
        children: [
          for (final item in candidates.take(200))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, item),
              child: Text(
                [
                  item.name,
                  item.dynasty,
                  _entityKindLabel(item.kind),
                ].whereType<String>().join(' · '),
              ),
            ),
        ],
      ),
    );
    if (target == null || !context.mounted) return;
    await ref.read(knowledgeServiceProvider).mergeEntities(target.id, [
      entityId,
    ]);
    ref.invalidate(entitiesProvider);
    ref.invalidate(entityProvider(target.id));
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _showReviewHistory(BuildContext context, WidgetRef ref) async {
    final rows = await ref
        .read(knowledgeServiceProvider)
        .reviewHistory(targetType: 'entity', targetId: entityId);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('审核与修改记录'),
        content: SizedBox(
          width: 620,
          height: 420,
          child: rows.isEmpty
              ? const Center(child: Text('暂无记录'))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      dense: true,
                      title: Text('${row['action']}'),
                      subtitle: Text('${row['created_at']} · ${row['source']}'),
                      trailing: TextButton(
                        onPressed: () async {
                          await ref
                              .read(knowledgeServiceProvider)
                              .undoReview(row['id'] as String);
                          ref.invalidate(entityProvider(entityId));
                          ref.invalidate(entitiesProvider);
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: const Text('撤销'),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _RelationCard extends ConsumerWidget {
  const _RelationCard({required this.entityId, required this.relation});
  final String entityId;
  final EntityRelation relation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusPill(
                status: relation.status == 'confirmed'
                    ? 'confirmed'
                    : 'pending',
              ),
              const SizedBox(width: 5),
              _KnowledgeTypePill(type: relation.knowledgeType),
              const SizedBox(width: 6),
              Text(
                relation.relationType,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                relation.otherName ?? '',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (relation.description != null) ...[
            const SizedBox(height: 4),
            Text(
              relation.description!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
          for (final source in relation.sources.take(2)) ...[
            const SizedBox(height: 7),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(7),
                border: Border(
                  left: BorderSide(
                    color: theme.colorScheme.secondary.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.quote ?? '',
                    style: const TextStyle(fontSize: 11.5, height: 1.6),
                  ),
                  if (source.bookTitle != null)
                    Text(
                      '${source.bookTitle} · ${source.chapterTitle ?? ''}',
                      style: TextStyle(
                        fontSize: 9,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (relation.status != 'confirmed' || relation.status != 'rejected')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  if (relation.status != 'confirmed')
                    TextButton(
                      onPressed: () async {
                        await ref
                            .read(knowledgeServiceProvider)
                            .setRelationStatus(relation.id, 'confirmed');
                        ref.invalidate(entityProvider(entityId));
                      },
                      child: const Text('确认'),
                    ),
                  if (relation.status != 'rejected')
                    TextButton(
                      onPressed: () async {
                        await ref
                            .read(knowledgeServiceProvider)
                            .setRelationStatus(relation.id, 'rejected');
                        ref.invalidate(entityProvider(entityId));
                      },
                      child: const Text('驳回'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MentionCard extends StatelessWidget {
  const _MentionCard({required this.mention, this.bookTitle});
  final EntityMention mention;
  final String? bookTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: mention.chapterId == null || mention.bookId == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReaderScreen(
                  bookId: mention.bookId!,
                  chapterId: mention.chapterId!,
                  chapterTitle: mention.chapterTitle ?? '章节',
                  bookTitle: mention.bookTitle ?? bookTitle ?? '',
                ),
              ),
            ),
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mention.quote,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                height: 1.7,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${mention.bookTitle ?? bookTitle ?? ''} · ${mention.chapterTitle ?? ''}',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(eventProvider(eventId));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('历史事件')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _KnowledgeError(
          error: error,
          onRetry: () => ref.invalidate(eventProvider(eventId)),
        ),
        data: (event) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 50),
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    event.eventType,
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                _StatusPill(status: event.status),
                const SizedBox(width: 5),
                _KnowledgeTypePill(type: event.knowledgeType),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              event.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              [
                event.timeRaw ?? '时间未详',
                if (event.timeStartYear != null)
                  _formatYear(event.timeStartYear!),
                if (event.dynasty != null) event.dynasty!,
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.secondary,
              ),
            ),
            if (event.description != null) ...[
              const SizedBox(height: 18),
              Text(
                event.description!,
                style: const TextStyle(height: 1.85, fontSize: 14),
              ),
            ],
            if (event.participants.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('参与者', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final name in event.participants)
                    Chip(
                      label: Text(name, style: const TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 22),
            Text('史料来源', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (event.sources.isEmpty)
              Text(
                '暂无出处',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                ),
              )
            else
              for (final source in event.sources)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border(
                      left: BorderSide(
                        color: theme.colorScheme.secondary.withValues(
                          alpha: 0.45,
                        ),
                        width: 2,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.quote ?? '',
                        style: const TextStyle(fontSize: 12, height: 1.7),
                      ),
                      if (source.bookTitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            '${source.bookTitle} · ${source.chapterTitle ?? ''}',
                            style: TextStyle(
                              fontSize: 9,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.4,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _KnowledgeError extends StatelessWidget {
  const _KnowledgeError({required this.error, required this.onRetry});
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
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _KnowledgeEmpty extends StatelessWidget {
  const _KnowledgeEmpty({
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
              size: 42,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 14),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 7),
            Text(
              body,
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
}
