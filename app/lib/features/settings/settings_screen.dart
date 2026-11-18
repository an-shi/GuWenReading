import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../core/local/app_database.dart';
import '../../core/local/backup_service.dart';
import '../../core/local/data_directory_service.dart';
import '../../core/local/local_models.dart';
import 'provider_editor.dart';
import '../../core/providers.dart';
import '../../core/storage/settings_controller.dart';
import '../../providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _tab = 0;
  List<AiProviderRecord> _providers = const [];
  List<AiModelRecord> _models = const [];
  List<PromptRecord> _prompts = const [];
  List<BackupInfo> _backups = const [];
  String? _selectedPromptKey;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final ai = ref.read(aiSettingsProvider);
    final store = ref.read(localStoreProvider);
    final backups = ref.read(backupServiceProvider);
    final providers = await ai.providers();
    final models = await ai.models();
    final prompts = await store.allPrompts();
    final files = await backups.listBackups();
    if (!mounted) return;
    setState(() {
      _providers = providers;
      _models = models;
      _prompts = prompts;
      _backups = files;
      _selectedPromptKey ??= prompts.isEmpty ? null : prompts.first.key;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '偏好设置',
                            style: theme.textTheme.labelSmall?.copyWith(
                              letterSpacing: 2,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.42,
                              ),
                            ),
                          ),
                          Text('设置', style: theme.textTheme.headlineMedium),
                        ],
                      ),
                      const Spacer(),
                      _LocalPill(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 4,
                    children: [
                      for (var index = 0; index < 5; index++)
                        ChoiceChip(
                          label: Text(
                            const ['AI 模型', '提示词', '阅读', '数据备份', '关于'][index],
                          ),
                          selected: _tab == index,
                          onSelected: (_) => setState(() => _tab = index),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      _aiTab(theme),
                      _promptTab(theme),
                      _readingTab(theme),
                      _backupTab(theme),
                      _aboutTab(theme),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- AI tab
  Widget _aiTab(ThemeData theme) {
    final settings = ref.watch(settingsProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        _SectionCard(
          title: '模型服务商',
          subtitle:
              '支持 OpenAI 兼容、Anthropic、Gemini 与 Ollama；可读取服务商模型列表并识别多模态能力。',
          action: FilledButton.tonalIcon(
            onPressed: () => _editProvider(null),
            icon: const Icon(Icons.add),
            label: const Text('添加服务商'),
          ),
          child: _providers.isEmpty
              ? _EmptyLine(text: '尚未添加服务商。')
              : Column(
                  children: [
                    for (final provider in _providers)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primary.withValues(
                            alpha: 0.09,
                          ),
                          child: const Icon(Icons.hub_outlined, size: 18),
                        ),
                        title: Text(provider.name),
                        subtitle: Text(
                          '${_providerKindLabel(provider.kind)} · ${provider.baseUrl}'
                          '${provider.apiKey.isEmpty ? ' · 未配置密钥' : ' · 已配置密钥'}'
                          ' · ${_models.where((model) => model.providerId == provider.id).length} 个模型',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: '测试连接',
                              onPressed: () => _testProvider(provider),
                              icon: const Icon(Icons.wifi_tethering, size: 19),
                            ),
                            IconButton(
                              tooltip: '编辑',
                              onPressed: () => _editProvider(provider),
                              icon: const Icon(Icons.edit_outlined, size: 19),
                            ),
                            IconButton(
                              tooltip: '删除',
                              onPressed: () => _deleteProvider(provider),
                              icon: const Icon(Icons.delete_outline, size: 19),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: '模型',
          subtitle: '为翻译与问答分别指定默认模型。翻译批量和超时会按模型配置执行。',
          action: FilledButton.tonalIcon(
            onPressed: _providers.isEmpty ? null : () => _editModel(null),
            icon: const Icon(Icons.add),
            label: const Text('添加模型'),
          ),
          child: _models.isEmpty
              ? _EmptyLine(text: '添加模型后，翻译、知识抽取和 AI 助手才能工作。')
              : Column(
                  children: [
                    for (final model in _models)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(model.displayName),
                        subtitle: Text(
                          '${model.name} · ${model.contextWindow} 上下文 · ${model.maxOutputTokens} 输出'
                          '${model.supports('vision') ? ' · 多模态' : ''}'
                          '${model.isDefaultTranslation ? ' · 默认翻译' : ''}'
                          '${model.isDefaultChat ? ' · 默认问答' : ''}'
                          '${model.isDefaultExtraction ? ' · 默认抽取' : ''}',
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: '编辑',
                              onPressed: () => _editModel(model),
                              icon: const Icon(Icons.edit_outlined, size: 19),
                            ),
                            IconButton(
                              tooltip: '删除',
                              onPressed: () => _deleteModel(model),
                              icon: const Icon(Icons.delete_outline, size: 19),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: '成本控制',
          subtitle: '单次 AI 任务的实际或估算费用达到上限时自动暂停；0 表示不限制。',
          action: OutlinedButton.icon(
            onPressed: _editTaskBudget,
            icon: const Icon(Icons.savings_outlined),
            label: const Text('修改上限'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(
                label: '单次任务上限',
                value: settings.aiTaskBudget > 0
                    ? settings.aiTaskBudget.toStringAsFixed(4)
                    : '不限',
              ),
              Text(
                '费用按模型配置的每百万 Token 单价和 Provider 返回的 usage 估算；'
                '未配置单价的模型费用按 0 计算。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- prompts tab
  Widget _promptTab(ThemeData theme) {
    final grouped = <String, List<PromptRecord>>{};
    for (final prompt in _prompts) {
      grouped.putIfAbsent(prompt.key, () => []).add(prompt);
    }
    final keys = grouped.keys.toList()..sort();
    if (_selectedPromptKey == null && keys.isNotEmpty) {
      _selectedPromptKey = keys.first;
    }
    final detail = _promptDetail(theme, grouped);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedPromptKey,
                decoration: const InputDecoration(labelText: '提示词'),
                items: [
                  for (final key in keys)
                    DropdownMenuItem(
                      value: key,
                      child: Text(
                        grouped[key]!.first.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _selectedPromptKey = value),
              ),
              const SizedBox(height: 12),
              detail,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 320,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 40),
                children: [
                  for (final key in keys)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: key == _selectedPromptKey
                          ? theme.colorScheme.primary.withValues(alpha: 0.08)
                          : null,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        title: Text(
                          grouped[key]!.first.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text('版本 ${grouped[key]!.first.version}'),
                        ),
                        onTap: () => setState(() => _selectedPromptKey = key),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 40),
                children: [detail],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _promptDetail(
    ThemeData theme,
    Map<String, List<PromptRecord>> grouped,
  ) {
    final versions = grouped[_selectedPromptKey] ?? const <PromptRecord>[];
    final active =
        versions.where((item) => item.isActive).firstOrNull ??
        versions.firstOrNull;
    if (active == null) return const _EmptyLine(text: '暂无提示词');
    return _SectionCard(
      title: active.name,
      subtitle: active.description ?? '当前生效版本 v${active.version}',
      action: FilledButton.tonalIcon(
        onPressed: () => _createPromptVersion(active, versions),
        icon: const Icon(Icons.add),
        label: const Text('创建新版本'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            active.template,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12.5,
              height: 1.75,
            ),
          ),
          const SizedBox(height: 18),
          Text('历史版本', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final version in versions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('v${version.version} · ${version.name}'),
              subtitle: Text(_formatDate(version.createdAt)),
              trailing: version.isActive
                  ? const Chip(label: Text('当前'))
                  : TextButton(
                      onPressed: () async {
                        await ref
                            .read(localStoreProvider)
                            .activatePrompt(version.key, version.version);
                        await _reload();
                      },
                      child: const Text('启用'),
                    ),
            ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- reading tab
  Widget _readingTab(ThemeData theme) {
    final settings = ref.watch(settingsProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        _SectionCard(
          title: '阅读外观',
          subtitle: '设置保存在本机，并立即应用于阅读器。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('阅读主题', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'paper', label: Text('纸张')),
                  ButtonSegment(value: 'light', label: Text('浅色')),
                  ButtonSegment(value: 'dark', label: Text('深色')),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (value) =>
                    ref.read(settingsProvider.notifier).setTheme(value.first),
              ),
              const SizedBox(height: 18),
              Text(
                '正文字号：${settings.fontSize.round()} 像素',
                style: theme.textTheme.titleSmall,
              ),
              Slider(
                value: settings.fontSize,
                min: 14,
                max: 32,
                divisions: 18,
                onChanged: (value) =>
                    ref.read(settingsProvider.notifier).setFontSize(value),
              ),
              Text(
                '行距：${settings.lineHeight.toStringAsFixed(1)}',
                style: theme.textTheme.titleSmall,
              ),
              Slider(
                value: settings.lineHeight,
                min: 1.4,
                max: 2.8,
                divisions: 14,
                onChanged: (value) =>
                    ref.read(settingsProvider.notifier).setLineHeight(value),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: settings.defaultReadingMode,
                decoration: const InputDecoration(labelText: '默认阅读模式'),
                items: const [
                  DropdownMenuItem(value: 'alternating', child: Text('原文译文交替')),
                  DropdownMenuItem(value: 'original', child: Text('原文优先')),
                  DropdownMenuItem(
                    value: 'independent',
                    child: Text('原文/译文切换'),
                  ),
                  DropdownMenuItem(value: 'sentence', child: Text('逐句对照')),
                  DropdownMenuItem(value: 'columns', child: Text('双栏对照（桌面）')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    ref
                        .read(settingsProvider.notifier)
                        .setDefaultReadingMode(value);
                  }
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('打开章节时自动翻译'),
                subtitle: const Text('仅在已配置默认翻译模型且存在未译句子时触发。'),
                value: settings.autoTranslate,
                onChanged: (value) =>
                    ref.read(settingsProvider.notifier).setAutoTranslate(value),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- backup tab
  Widget _backupTab(ThemeData theme) {
    final paths = ref.read(appDatabaseProvider).paths;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        _SectionCard(
          title: '数据备份',
          subtitle: '备份包含数据库、原始书籍、封面与全部本地数据。恢复会覆盖当前数据。',
          action: FilledButton.tonalIcon(
            onPressed: _busy ? null : _createBackup,
            icon: const Icon(Icons.backup_outlined),
            label: const Text('创建备份'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(label: '数据根目录', value: paths.root.path),
              _InfoRow(label: '书籍与备份', value: paths.libraryDir.path),
              _InfoRow(label: '数据库', value: paths.dbPath),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _restoreBackup,
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('从备份恢复'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _changeDataDirectory,
                    icon: const Icon(Icons.drive_file_move_outline),
                    label: const Text('更改数据目录'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '默认存放在安装目录的 data/ 下：书籍与备份在 library/，数据库在 database/。更改目录会整体迁移并重启应用。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 16),
              if (_backups.isEmpty)
                const _EmptyLine(text: '暂无本地备份。')
              else
                for (final backup in _backups)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(backup.filename),
                    subtitle: Text(
                      '${_formatSize(backup.size)} · ${_formatDate(backup.createdAt)}',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: '导出',
                          onPressed: () => _exportBackup(backup),
                          icon: const Icon(Icons.save_alt_rounded, size: 19),
                        ),
                        IconButton(
                          tooltip: '删除',
                          onPressed: () => _deleteBackup(backup),
                          icon: const Icon(Icons.delete_outline, size: 19),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- about tab
  Widget _aboutTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        _SectionCard(
          title: '古文阅读器',
          subtitle: '本地优先的古籍阅读、翻译与历史知识研究工具。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _InfoRow(label: '版本', value: '0.1.0'),
              const _InfoRow(label: '运行方式', value: '单机本地运行，不依赖后端服务'),
              const _InfoRow(label: '支持格式', value: 'TXT、EPUB、DOCX、文本型 PDF'),
              const _InfoRow(label: '数据存储', value: 'SQLite 本地数据库'),
              const SizedBox(height: 12),
              Text(
                '原文完整保留 · 译文精确关联 · 知识有据可查 · 桌面与移动端独立可用',
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.8,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '扫描版 PDF 的文字识别（OCR）尚未实现；这类文件会被明确拒绝，而不是静默生成错误文本。AI 抽取的实体、关系与事件默认处于待审核状态。',
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.7,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- dialogs
  Future<void> _editTaskBudget() async {
    final current = ref.read(settingsProvider).aiTaskBudget;
    final controller = TextEditingController(
      text: current > 0 ? current.toString() : '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('单次任务费用上限'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '费用上限',
            hintText: '留空或 0 表示不限制',
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
    );
    if (saved == true) {
      final value = double.tryParse(controller.text.trim()) ?? 0;
      await ref.read(settingsProvider.notifier).setAiTaskBudget(value);
      if (mounted) setState(() {});
    }
    controller.dispose();
  }

  Future<void> _editProvider(AiProviderRecord? provider) async {
    final ai = ref.read(aiSettingsProvider);
    final result = await showDialog<ProviderEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProviderEditorDialog(
        ai: ai,
        provider: provider,
        existingModels: provider == null
            ? const []
            : _models
                  .where((model) => model.providerId == provider.id)
                  .toList(),
      ),
    );
    if (result == null) return;
    try {
      await ai.saveProvider(result.provider);
      if (result.models.isNotEmpty) {
        final allModels = await ai.models();
        var hasTranslation = allModels.any(
          (model) => model.isDefaultTranslation,
        );
        var hasChat = allModels.any((model) => model.isDefaultChat);
        final existingNames = {
          for (final model in allModels)
            if (model.providerId == result.provider.id) model.name,
        };
        for (final remote in result.models) {
          if (!existingNames.add(remote.id)) continue;
          final defaultTranslation = !hasTranslation;
          final defaultChat = !hasChat;
          await ai.saveModel(
            AiModelRecord(
              id: newLocalId('model'),
              providerId: result.provider.id,
              name: remote.id,
              displayName: remote.displayName,
              contextWindow: remote.contextWindow ?? 8192,
              maxOutputTokens: remote.maxOutputTokens ?? 2048,
              timeoutSeconds: 120,
              capabilities: [
                'translation',
                'chat',
                if (remote.supportsVision) 'vision',
              ],
              supportsJson: true,
              isDefaultTranslation: defaultTranslation,
              isDefaultChat: defaultChat,
              enabled: true,
            ),
          );
          if (defaultTranslation) hasTranslation = true;
          if (defaultChat) hasChat = true;
        }
      }
      await _reload();
      _toast(
        result.models.isEmpty
            ? '服务商已保存'
            : '服务商与 ${result.models.length} 个模型已保存',
      );
    } catch (error) {
      _toast('保存失败：$error', error: true);
    }
  }

  Future<void> _deleteProvider(AiProviderRecord provider) async {
    if (!await _confirm(
      '删除服务商？',
      '将删除「${provider.name}」及其下的模型。已有译文与知识数据不会删除。',
    )) {
      return;
    }
    await ref.read(aiSettingsProvider).deleteProvider(provider.id);
    await _reload();
  }

  Future<void> _testProvider(AiProviderRecord provider) async {
    final models = _models
        .where((model) => model.providerId == provider.id)
        .toList();
    if (models.isEmpty) {
      _toast('请先为该服务商添加模型');
      return;
    }
    try {
      setState(() => _busy = true);
      await ref.read(aiSettingsProvider).testProvider(provider, models.first);
      _toast('连接成功');
    } catch (error) {
      _toast('$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editModel(AiModelRecord? model) async {
    final theme = Theme.of(context);
    final providerId =
        model?.providerId ?? (_providers.isEmpty ? null : _providers.first.id);
    if (providerId == null) return;
    final name = TextEditingController(text: model?.name ?? '');
    final displayName = TextEditingController(text: model?.displayName ?? '');
    final contextWindow = TextEditingController(
      text: '${model?.contextWindow ?? 8192}',
    );
    final maxOutput = TextEditingController(
      text: '${model?.maxOutputTokens ?? 2048}',
    );
    final timeout = TextEditingController(
      text: '${model?.timeoutSeconds ?? 120}',
    );
    final inputPrice = TextEditingController(text: '${model?.inputPrice ?? 0}');
    final outputPrice = TextEditingController(
      text: '${model?.outputPrice ?? 0}',
    );
    final cacheReadPrice = TextEditingController(
      text: '${model?.cacheReadPrice ?? 0}',
    );
    final cacheWritePrice = TextEditingController(
      text: '${model?.cacheWritePrice ?? 0}',
    );
    final tokenizer = TextEditingController(text: model?.tokenizer ?? '');
    var selectedProvider = providerId;
    var supportsJson = model?.supportsJson ?? true;
    var defaultTranslation = model?.isDefaultTranslation ?? false;
    var defaultChat = model?.isDefaultChat ?? false;
    var defaultExtraction = model?.isDefaultExtraction ?? false;
    var enabled = model?.enabled ?? true;
    var capabilities = [
      ...(model?.capabilities ?? const ['translation', 'chat']),
    ];
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(model == null ? '添加模型' : '编辑模型'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedProvider,
                  decoration: const InputDecoration(labelText: '服务商'),
                  items: [
                    for (final provider in _providers)
                      DropdownMenuItem(
                        value: provider.id,
                        child: Text(provider.name),
                      ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => selectedProvider = value ?? selectedProvider,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: '模型标识',
                    hintText: 'deepseek-chat',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: displayName,
                  decoration: const InputDecoration(labelText: '显示名称'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tokenizer,
                  decoration: const InputDecoration(
                    labelText: 'Tokenizer（可选）',
                    hintText: 'cl100k_base / o200k_base / qwen / deepseek / anthropic',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '未安装精确词表时按模型系列保守估算；Token 来源会在用量记录中标记。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.45,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: contextWindow,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '上下文长度'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: maxOutput,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '最大输出'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: timeout,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '超时（秒）'),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '计费单价（每百万 Token，币种自行统一）',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: inputPrice,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: '输入单价'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: outputPrice,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: '输出单价'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: cacheReadPrice,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: '缓存读取单价'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: cacheWritePrice,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: '缓存写入单价'),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '留 0 表示未配置；缓存单价留 0 时按输入单价估算。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.42,
                      ),
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('支持结构化 JSON 输出'),
                  value: supportsJson,
                  onChanged: (value) =>
                      setDialogState(() => supportsJson = value),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final capability in const [
                      'translation',
                      'chat',
                      'vision',
                    ])
                      FilterChip(
                        label: Text(switch (capability) {
                          'translation' => '翻译',
                          'chat' => '问答与抽取',
                          _ => '图片理解',
                        }),
                        selected: capabilities.contains(capability),
                        onSelected: (selected) => setDialogState(() {
                          if (selected) {
                            capabilities.add(capability);
                          } else {
                            capabilities.remove(capability);
                          }
                        }),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '多模态能力来自服务商的模型列表；勾选后可识别该模型是否支持图片输入。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.45,
                      ),
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('设为默认翻译模型'),
                  value: defaultTranslation,
                  onChanged: (value) =>
                      setDialogState(() => defaultTranslation = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('设为默认问答模型'),
                  value: defaultChat,
                  onChanged: (value) =>
                      setDialogState(() => defaultChat = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('设为默认知识抽取模型'),
                  subtitle: const Text('未设置时使用默认问答模型'),
                  value: defaultExtraction,
                  onChanged: (value) =>
                      setDialogState(() => defaultExtraction = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用该模型'),
                  value: enabled,
                  onChanged: (value) => setDialogState(() => enabled = value),
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
    if (saved != true) return;
    final record = AiModelRecord(
      id: model?.id ?? newLocalId('model'),
      providerId: selectedProvider,
      name: name.text.trim(),
      displayName: displayName.text.trim().isEmpty
          ? name.text.trim()
          : displayName.text.trim(),
      contextWindow: int.tryParse(contextWindow.text) ?? 8192,
      maxOutputTokens: int.tryParse(maxOutput.text) ?? 2048,
      timeoutSeconds: int.tryParse(timeout.text) ?? 120,
      inputPrice: double.tryParse(inputPrice.text.trim()) ?? 0,
      outputPrice: double.tryParse(outputPrice.text.trim()) ?? 0,
      cacheReadPrice: double.tryParse(cacheReadPrice.text.trim()) ?? 0,
      cacheWritePrice: double.tryParse(cacheWritePrice.text.trim()) ?? 0,
      tokenizer: tokenizer.text.trim().isEmpty ? null : tokenizer.text.trim(),
      capabilities: capabilities,
      supportsJson: supportsJson,
      isDefaultTranslation: defaultTranslation,
      isDefaultChat: defaultChat,
      isDefaultExtraction: defaultExtraction,
      enabled: enabled,
    );
    await ref.read(aiSettingsProvider).saveModel(record);
    await _reload();
  }

  Future<void> _deleteModel(AiModelRecord model) async {
    if (!await _confirm('删除模型？', '将移除「${model.displayName}」配置。已有译文不会删除。')) {
      return;
    }
    await ref.read(aiSettingsProvider).deleteModel(model.id);
    await _reload();
  }

  Future<void> _createPromptVersion(
    PromptRecord active,
    List<PromptRecord> versions,
  ) async {
    final name = TextEditingController(text: '${active.name} 修订版');
    final description = TextEditingController();
    final template = TextEditingController(text: active.template);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建提示词新版本'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '版本名称'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: '说明'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: template,
                  maxLines: 14,
                  decoration: const InputDecoration(labelText: '模板内容'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('创建并启用'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final version =
        (versions
            .map((item) => item.version)
            .fold<int>(0, (a, b) => a > b ? a : b)) +
        1;
    final record = PromptRecord(
      id: newLocalId('prompt'),
      key: active.key,
      version: version,
      name: name.text.trim().isEmpty ? active.name : name.text.trim(),
      description: description.text.trim().isEmpty
          ? null
          : description.text.trim(),
      template: template.text,
      variables: active.variables,
      isActive: false,
    );
    await ref.read(localStoreProvider).insertPrompt(record);
    await ref.read(localStoreProvider).activatePrompt(active.key, version);
    await _reload();
  }

  // ------------------------------------------------------------------ backup
  Future<void> _createBackup() async {
    try {
      setState(() => _busy = true);
      await ref.read(backupServiceProvider).createBackup();
      await _reload();
      _toast('备份已创建');
    } catch (error) {
      _toast('备份失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportBackup(BackupInfo backup) async {
    try {
      final bytes = await File(backup.path).readAsBytes();
      final path = await FilePicker.saveFile(
        dialogTitle: '导出备份',
        fileName: backup.filename,
        bytes: bytes,
      );
      if (path != null) {
        final target = File(path.toFilePath());
        if (!await target.exists() || await target.length() == 0) {
          await target.writeAsBytes(bytes, flush: true);
        }
      }
    } catch (error) {
      _toast('导出失败：$error', error: true);
    }
  }

  Future<void> _changeDataDirectory() async {
    String? selected;
    try {
      selected = await FilePicker.getDirectoryPath(dialogTitle: '选择新的数据目录');
    } catch (error) {
      _toast('无法打开目录选择器：$error', error: true);
      return;
    }
    if (selected == null || selected.trim().isEmpty) return;
    final current = ref.read(appDatabaseProvider).paths;
    final source = p.normalize(p.absolute(current.root.path));
    final target = p.normalize(p.absolute(selected));
    if (p.equals(source, target)) {
      _toast('新目录与当前数据目录相同');
      return;
    }
    if (p.isWithin(source, target) || p.isWithin(target, source)) {
      _toast('新旧数据目录不能互相包含');
      return;
    }
    final targetDir = Directory(target);
    final nonEmpty =
        await targetDir.exists() &&
        (await targetDir.list().take(1).toList()).isNotEmpty;
    if (nonEmpty &&
        !await _confirm('目标目录非空', '所选目录已有文件。继续会合并文件，并覆盖同名数据库与书籍文件。是否继续？')) {
      return;
    }
    if (!await _confirm(
      '迁移数据目录？',
      '将把数据库、原始书籍、封面、备份和临时文件迁移到：\n$target\n\n迁移完成后应用会重启，旧目录中的应用数据会被清理。',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      final database = ref.read(appDatabaseProvider);
      await database.close();
      await DataDirectoryService().migrate(
        current: current,
        targetPath: target,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('迁移完成'),
          content: Text('数据已迁移到：\n$target\n\n应用即将重启，请稍候。'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('立即重启'),
            ),
          ],
        ),
      );
      await DataDirectoryService().restartApp();
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('迁移失败'),
          content: Text('$error\n\n应用将重启并继续使用原数据目录。'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('重启应用'),
            ),
          ],
        ),
      );
      await DataDirectoryService().restartApp();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (picked.isEmpty || picked.first.path == null) return;
    if (!await _confirm('从备份恢复？', '当前数据库、书籍与批注会被备份内容覆盖。恢复前会自动保留一份当前数据库副本。')) {
      return;
    }
    try {
      setState(() => _busy = true);
      await ref.read(backupServiceProvider).restoreBackup(picked.first.path!);
      await _reload();
      ref.invalidate(bookshelfProvider);
      ref.invalidate(tasksProvider);
      _toast('备份已恢复，请重新进入书架或阅读页');
    } catch (error) {
      _toast('恢复失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteBackup(BackupInfo backup) async {
    if (!await _confirm('删除备份？', '将删除「${backup.filename}」。')) return;
    await ref.read(backupServiceProvider).deleteBackup(backup.path);
    await _reload();
  }

  Future<bool> _confirm(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确定'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  String _providerKindLabel(String kind) => switch (kind) {
    'openai' => 'OpenAI',
    'anthropic' => 'Anthropic',
    'ollama' => 'Ollama',
    _ => 'OpenAI 兼容',
  };

  String _formatDate(String? value) {
    if (value == null) return '';
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final titleBlock = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                        height: 1.6,
                      ),
                    ),
                  ],
                );
                if (action == null) return titleBlock;
                if (constraints.maxWidth < 520) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [titleBlock, const SizedBox(height: 10), action!],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: titleBlock),
                    const SizedBox(width: 12),
                    action!,
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}

class _LocalPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.offline_bolt_outlined,
            size: 14,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 5),
          Text(
            '本机运行',
            style: TextStyle(fontSize: 11, color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }
}
