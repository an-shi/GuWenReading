import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../providers.dart';
import 'relation_editor.dart';

class EventEditorDialog extends ConsumerStatefulWidget {
  const EventEditorDialog({super.key, required this.event});

  final HistoricalEvent event;

  @override
  ConsumerState<EventEditorDialog> createState() => _EventEditorDialogState();
}

class _EventEditorDialogState extends ConsumerState<EventEditorDialog> {
  late TextEditingController _name;
  late TextEditingController _description;
  late TextEditingController _timeRaw;
  late TextEditingController _year;
  late TextEditingController _timeEndRaw;
  late TextEditingController _endYear;
  late TextEditingController _location;
  late String _type;
  late String _precision;
  late String _status;
  List<Map<String, Object?>> _evidence = const [];

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    _name = TextEditingController(text: event.name);
    _description = TextEditingController(text: event.description ?? '');
    _timeRaw = TextEditingController(text: event.timeRaw ?? '');
    _year = TextEditingController(text: event.timeStartYear?.toString() ?? '');
    _timeEndRaw = TextEditingController(text: event.timeEndRaw ?? '');
    _endYear = TextEditingController(text: event.timeEndYear?.toString() ?? '');
    _location = TextEditingController(text: event.location ?? '');
    _type = eventTypes.contains(event.eventType) ? event.eventType : 'other';
    _precision = timePrecisions.contains(event.timePrecision)
        ? event.timePrecision
        : 'unknown';
    _status = event.status == 'confirmed'
        ? 'confirmed'
        : event.status == 'rejected'
        ? 'rejected'
        : 'pending';
    _loadEvidence();
  }

  Future<void> _loadEvidence() async {
    final rows = await ref
        .read(knowledgeServiceProvider)
        .eventEvidence(widget.event.id);
    if (mounted) setState(() => _evidence = rows);
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _description,
      _timeRaw,
      _year,
      _timeEndRaw,
      _endYear,
      _location,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    await ref
        .read(knowledgeServiceProvider)
        .updateEvent(
          widget.event.id,
          name: _name.text.trim(),
          type: _type,
          description: _description.text.trim(),
          timeRaw: _timeRaw.text.trim(),
          year: int.tryParse(_year.text.trim()),
          timeEndRaw: _timeEndRaw.text.trim(),
          endYear: int.tryParse(_endYear.text.trim()),
          location: _location.text.trim(),
          precision: _precision,
          status: _status,
        );
    ref.invalidate(eventsProvider);
    ref.invalidate(timelineProvider);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('编辑事件 · ${widget.event.name}'),
      content: SizedBox(
        width: 760,
        height: 620,
        child: ListView(
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '事件名称'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: '事件类型'),
                    items: [
                      for (final type in eventTypes)
                        DropdownMenuItem(
                          value: type,
                          child: Text(eventTypeLabel(type)),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _type = value ?? _type),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    initialValue: _precision,
                    decoration: const InputDecoration(labelText: '时间精度'),
                    items: [
                      for (final precision in timePrecisions)
                        DropdownMenuItem(
                          value: precision,
                          child: Text(precision),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _precision = value ?? _precision),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: '审核状态'),
                    items: const [
                      DropdownMenuItem(value: 'confirmed', child: Text('确认')),
                      DropdownMenuItem(value: 'pending', child: Text('待审')),
                      DropdownMenuItem(value: 'rejected', child: Text('驳回')),
                    ],
                    onChanged: (value) =>
                        setState(() => _status = value ?? _status),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '事件描述'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _timeRaw,
                    decoration: const InputDecoration(labelText: '开始时间（原文）'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _year,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '开始年份'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _timeEndRaw,
                    decoration: const InputDecoration(labelText: '结束时间（原文）'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _endYear,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '结束年份'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _location,
              decoration: const InputDecoration(labelText: '发生地点'),
            ),
            if (widget.event.participants.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '参与者：${widget.event.participants.join('、')}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Text('原文证据', style: theme.textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addEvidence,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加证据'),
                ),
              ],
            ),
            if (_evidence.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('暂无证据。'),
              )
            else
              for (final row in _evidence)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    row['source_kind'] == 'manual'
                        ? Icons.edit_note_rounded
                        : Icons.auto_awesome_rounded,
                    size: 18,
                  ),
                  title: Text('${row['quote'] ?? ''}'),
                  subtitle: Text(
                    [
                      '${row['book_title'] ?? '未知书籍'}',
                      '${row['chapter_title'] ?? ''}',
                      evidenceTypeLabel(
                        '${row['evidence_type'] ?? 'supporting'}',
                      ),
                      row['source_kind'] == 'manual' ? '人工' : 'AI',
                    ].where((item) => item.isNotEmpty).join(' · '),
                  ),
                  trailing: IconButton(
                    tooltip: '删除证据',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () async {
                      await ref
                          .read(knowledgeServiceProvider)
                          .deleteEventEvidence(row['id'] as String);
                      await _loadEvidence();
                    },
                  ),
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _merge, child: const Text('合并事件')),
        TextButton(onPressed: () => _delete(context), child: const Text('删除')),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  Future<void> _addEvidence() async {
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => const EvidencePickerDialog(),
    );
    if (result == null) return;
    await ref
        .read(knowledgeServiceProvider)
        .addEventEvidence(
          widget.event.id,
          sentenceId: result['sentence_id'] as String?,
          bookId: result['book_id'] as String?,
          chapterId: result['chapter_id'] as String?,
          paragraphId: result['paragraph_id'] as String?,
          quote: '${result['quote']}',
          evidenceType: '${result['evidence_type']}',
          note: result['note'] as String?,
          sourceKind: '${result['source_kind']}',
        );
    await _loadEvidence();
  }

  Future<void> _merge() async {
    final events = await ref.read(knowledgeServiceProvider).listEvents();
    if (!mounted) return;
    final target = await showDialog<HistoricalEvent>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('合并到事件'),
        children: [
          for (final event in events.where(
            (item) => item.id != widget.event.id,
          ))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, event),
              child: Text(event.name),
            ),
        ],
      ),
    );
    if (target == null) return;
    await ref.read(knowledgeServiceProvider).mergeEvents(target.id, [
      widget.event.id,
    ]);
    ref.invalidate(eventsProvider);
    ref.invalidate(timelineProvider);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除事件'),
        content: const Text('删除后事件及其证据关联将被移除，可在审核记录中查看。'),
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
    if (confirmed != true) return;
    await ref.read(knowledgeServiceProvider).deleteEvent(widget.event.id);
    ref.invalidate(eventsProvider);
    ref.invalidate(timelineProvider);
    if (!context.mounted) return;
    Navigator.pop(context, true);
  }
}
