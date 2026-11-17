import 'package:flutter/material.dart';

import '../../core/local/ai_service.dart';
import '../../core/local/app_database.dart';
import '../../core/local/local_models.dart';

class ProviderPreset {
  const ProviderPreset({
    required this.name,
    required this.kind,
    required this.baseUrl,
    this.description = '',
    this.keyHint = 'sk-...',
  });

  final String name;
  final String kind;
  final String baseUrl;
  final String description;
  final String keyHint;
}

const providerPresets = <ProviderPreset>[
  ProviderPreset(
    name: 'OpenAI',
    kind: 'openai',
    baseUrl: 'https://api.openai.com/v1',
    description: 'GPT 系列与 o 系列模型',
    keyHint: 'sk-...',
  ),
  ProviderPreset(
    name: 'DeepSeek',
    kind: 'openai_compatible',
    baseUrl: 'https://api.deepseek.com/v1',
    description: 'DeepSeek Chat 与推理模型',
    keyHint: 'sk-...',
  ),
  ProviderPreset(
    name: '通义千问',
    kind: 'openai_compatible',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    description: '阿里云百炼 OpenAI 兼容接口',
    keyHint: 'sk-...',
  ),
  ProviderPreset(
    name: '豆包 · 火山方舟',
    kind: 'openai_compatible',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    description: '火山方舟 OpenAI 兼容接口',
    keyHint: 'API Key',
  ),
  ProviderPreset(
    name: 'Kimi · 月之暗面',
    kind: 'openai_compatible',
    baseUrl: 'https://api.moonshot.cn/v1',
    description: 'Moonshot 开放平台',
    keyHint: 'sk-...',
  ),
  ProviderPreset(
    name: '智谱 GLM',
    kind: 'openai_compatible',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    description: 'GLM 系列模型',
    keyHint: 'API Key',
  ),
  ProviderPreset(
    name: '硅基流动',
    kind: 'openai_compatible',
    baseUrl: 'https://api.siliconflow.cn/v1',
    description: '多种开源模型聚合',
    keyHint: 'sk-...',
  ),
  ProviderPreset(
    name: '腾讯混元',
    kind: 'openai_compatible',
    baseUrl: 'https://api.hunyuan.cloud.tencent.com/v1',
    description: '腾讯混元 OpenAI 兼容接口',
    keyHint: 'API Key',
  ),
  ProviderPreset(
    name: '百度千帆',
    kind: 'openai_compatible',
    baseUrl: 'https://qianfan.baidubce.com/v2',
    description: '文心系列模型',
    keyHint: 'API Key',
  ),
  ProviderPreset(
    name: 'MiniMax',
    kind: 'openai_compatible',
    baseUrl: 'https://api.minimax.chat/v1',
    description: 'MiniMax 开放平台',
    keyHint: 'API Key',
  ),
  ProviderPreset(
    name: 'Google Gemini',
    kind: 'openai_compatible',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    description: 'OpenAI 兼容接口，支持图片理解',
    keyHint: 'AIza...',
  ),
  ProviderPreset(
    name: 'Anthropic Claude',
    kind: 'anthropic',
    baseUrl: 'https://api.anthropic.com/v1',
    description: 'Anthropic Messages API',
    keyHint: 'sk-ant-...',
  ),
  ProviderPreset(
    name: 'OpenRouter',
    kind: 'openai_compatible',
    baseUrl: 'https://openrouter.ai/api/v1',
    description: '聚合多家模型的统一接口',
    keyHint: 'sk-or-...',
  ),
  ProviderPreset(
    name: 'xAI Grok',
    kind: 'openai_compatible',
    baseUrl: 'https://api.x.ai/v1',
    description: 'Grok 系列模型',
    keyHint: 'xai-...',
  ),
  ProviderPreset(
    name: 'Mistral',
    kind: 'openai_compatible',
    baseUrl: 'https://api.mistral.ai/v1',
    description: 'Mistral 与 Pixtral 模型',
    keyHint: 'API Key',
  ),
  ProviderPreset(
    name: 'Groq',
    kind: 'openai_compatible',
    baseUrl: 'https://api.groq.com/openai/v1',
    description: '高速推理服务',
    keyHint: 'gsk_...',
  ),
  ProviderPreset(
    name: 'Ollama',
    kind: 'ollama',
    baseUrl: 'http://127.0.0.1:11434',
    description: '本机运行的离线模型',
    keyHint: '本地服务通常无需密钥',
  ),
  ProviderPreset(
    name: '自定义 OpenAI 兼容',
    kind: 'openai_compatible',
    baseUrl: '',
    description: '适用于任何兼容 /chat/completions 的服务',
    keyHint: 'API Key',
  ),
];

class ProviderEditorResult {
  const ProviderEditorResult({required this.provider, required this.models});

  final AiProviderRecord provider;
  final List<RemoteAiModel> models;
}

class ProviderEditorDialog extends StatefulWidget {
  const ProviderEditorDialog({
    super.key,
    required this.ai,
    required this.existingModels,
    this.provider,
  });

  final AiSettingsService ai;
  final List<AiModelRecord> existingModels;
  final AiProviderRecord? provider;

  @override
  State<ProviderEditorDialog> createState() => _ProviderEditorDialogState();
}

class _ProviderEditorDialogState extends State<ProviderEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _notes;
  final _search = TextEditingController();

  late String _kind;
  late bool _enabled;
  var _obscureKey = true;
  var _clearKey = false;
  var _fetching = false;
  String? _fetchError;
  String? _formError;
  ProviderPreset? _preset;
  List<RemoteAiModel> _remoteModels = const [];
  final Set<String> _selected = {};

  String get _effectiveKey {
    if (_clearKey) return '';
    final typed = _apiKey.text.trim();
    return typed.isEmpty ? (widget.provider?.apiKey ?? '') : typed;
  }

  bool get _hasSavedKey =>
      widget.provider?.apiKey.isNotEmpty == true && !_clearKey;

  Set<String> get _existingNames => {
    for (final model in widget.existingModels)
      if (model.providerId == (widget.provider?.id ?? _draftProvider().id))
        model.name,
  };

  @override
  void initState() {
    super.initState();
    final provider = widget.provider;
    _name = TextEditingController(text: provider?.name ?? '');
    _baseUrl = TextEditingController(text: provider?.baseUrl ?? '');
    _apiKey = TextEditingController();
    _notes = TextEditingController(text: provider?.notes ?? '');
    _kind = provider?.kind ?? 'openai_compatible';
    _enabled = provider?.enabled ?? true;
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _notes.dispose();
    _search.dispose();
    super.dispose();
  }

  AiProviderRecord _draftProvider() => AiProviderRecord(
    id: widget.provider?.id ?? 'draft-provider',
    name: _name.text.trim().isEmpty ? '未命名服务商' : _name.text.trim(),
    kind: _kind,
    baseUrl: _baseUrl.text.trim(),
    apiKey: _effectiveKey,
    enabled: _enabled,
  );

  void _applyPreset(ProviderPreset? preset) {
    if (preset == null) return;
    setState(() {
      _preset = preset;
      if (_name.text.trim().isEmpty || _name.text.trim() == '未命名服务商') {
        _name.text = preset.name;
      } else if (preset.name != '自定义 OpenAI 兼容') {
        _name.text = preset.name;
      }
      if (preset.baseUrl.isNotEmpty) _baseUrl.text = preset.baseUrl;
      _kind = preset.kind;
      _fetchError = null;
    });
  }

  Future<void> _fetchModels() async {
    final base = _baseUrl.text.trim();
    if (base.isEmpty) {
      setState(() => _fetchError = '请先填写接口基础地址');
      return;
    }
    final draft = _draftProvider();
    if ((_kind == 'anthropic' ||
            _baseUrl.text.contains('generativelanguage.googleapis.com')) &&
        draft.apiKey.isEmpty) {
      setState(() => _fetchError = '请先填写 API Key');
      return;
    }
    setState(() {
      _fetching = true;
      _fetchError = null;
    });
    try {
      final models = await widget.ai.fetchModels(draft);
      if (!mounted) return;
      setState(() {
        _remoteModels = models;
        _selected.retainWhere((id) => models.any((model) => model.id == id));
        if (models.isEmpty) {
          _fetchError = '没有读取到可用的对话模型';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _fetchError = '$error');
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  void _save() {
    final base = _baseUrl.text.trim();
    final uri = Uri.tryParse(base);
    if (base.isEmpty || uri == null || uri.host.isEmpty) {
      setState(() => _formError = '请填写有效的接口基础地址');
      return;
    }
    final provider = AiProviderRecord(
      id: widget.provider?.id ?? newLocalId('provider'),
      name: _name.text.trim().isEmpty ? '未命名服务商' : _name.text.trim(),
      kind: _kind,
      baseUrl: base,
      apiKey: _clearKey
          ? ''
          : (_apiKey.text.trim().isEmpty
                ? (widget.provider?.apiKey ?? '')
                : _apiKey.text.trim()),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      enabled: _enabled,
    );
    final models = [
      for (final model in _remoteModels)
        if (_selected.contains(model.id)) model,
    ];
    Navigator.pop(
      context,
      ProviderEditorResult(provider: provider, models: models),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 760, maxHeight: size.height - 48),
        child: Material(
          color: theme.colorScheme.surface,
          elevation: 28,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(theme),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionLabel(
                        theme,
                        Icons.auto_awesome_outlined,
                        '快速预设',
                        '选择常见服务商，自动填写接口地址与协议类型。',
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<ProviderPreset>(
                        initialValue: _preset,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          hintText: '选择服务商预设（可选）',
                          prefixIcon: Icon(Icons.travel_explore_rounded),
                        ),
                        items: [
                          for (final preset in providerPresets)
                            DropdownMenuItem(
                              value: preset,
                              child: Text(
                                preset.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _applyPreset,
                      ),
                      if ((_preset?.description ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Text(
                            _preset!.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.55,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 22),
                      _sectionLabel(
                        theme,
                        Icons.tune_rounded,
                        '连接信息',
                        '密钥只保存在本机安全存储中。',
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final nameField = TextField(
                            controller: _name,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: '名称',
                              hintText: '例如：DeepSeek',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                          );
                          final typeField = DropdownButtonFormField<String>(
                            initialValue: _kind,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '协议类型',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'openai_compatible',
                                child: Text('OpenAI 兼容'),
                              ),
                              DropdownMenuItem(
                                value: 'openai',
                                child: Text('OpenAI'),
                              ),
                              DropdownMenuItem(
                                value: 'anthropic',
                                child: Text('Anthropic'),
                              ),
                              DropdownMenuItem(
                                value: 'ollama',
                                child: Text('Ollama'),
                              ),
                            ],
                            onChanged: (value) => setState(() {
                              _kind = value ?? _kind;
                              _fetchError = null;
                            }),
                          );
                          if (constraints.maxWidth < 520) {
                            return Column(
                              children: [
                                nameField,
                                const SizedBox(height: 12),
                                typeField,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: nameField),
                              const SizedBox(width: 12),
                              Expanded(flex: 2, child: typeField),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _baseUrl,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: '接口基础地址',
                          hintText: 'https://api.example.com/v1',
                          prefixIcon: Icon(Icons.link_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _apiKey,
                        obscureText: _obscureKey,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          hintText: _hasSavedKey
                              ? '已保存，留空则保持不变'
                              : (_preset?.keyHint ?? 'sk-...'),
                          prefixIcon: const Icon(Icons.key_rounded),
                          suffixIcon: IconButton(
                            tooltip: _obscureKey ? '显示密钥' : '隐藏密钥',
                            onPressed: () =>
                                setState(() => _obscureKey = !_obscureKey),
                            icon: Icon(
                              _obscureKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (widget.provider?.apiKey.isNotEmpty == true)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () =>
                                setState(() => _clearKey = !_clearKey),
                            icon: Icon(
                              _clearKey
                                  ? Icons.undo_rounded
                                  : Icons.delete_outline_rounded,
                              size: 18,
                            ),
                            label: Text(_clearKey ? '保留原密钥' : '清除已保存的密钥'),
                          ),
                        ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _notes,
                        maxLines: 2,
                        minLines: 1,
                        decoration: const InputDecoration(
                          labelText: '备注（可选）',
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('启用该服务商'),
                        subtitle: const Text('禁用后不会用于翻译、知识抽取和问答'),
                        value: _enabled,
                        onChanged: (value) => setState(() => _enabled = value),
                      ),
                      const SizedBox(height: 16),
                      _modelSection(theme),
                      if (_formError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _formError!,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _footer(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.14),
            theme.colorScheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.hub_rounded,
              color: theme.colorScheme.onPrimary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.provider == null ? '添加 AI 服务商' : '编辑 AI 服务商',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  '连接模型服务，读取模型列表并选择要使用的模型。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _footer(ThemeData theme) {
    final newCount = _selected.length;
    final existingCount = _remoteModels
        .where((model) => _existingNames.contains(model.id))
        .length;
    final summary = _remoteModels.isEmpty
        ? '可先保存服务商，稍后再添加模型'
        : '已选 $newCount 个新模型'
              '${existingCount > 0 ? '，$existingCount 个已添加' : ''}';
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 20, 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              summary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _fetching ? null : _save,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _modelSection(ThemeData theme) {
    final existingNames = _existingNames;
    final query = _search.text.trim().toLowerCase();
    final visible = _remoteModels
        .where(
          (model) =>
              query.isEmpty ||
              model.id.toLowerCase().contains(query) ||
              model.displayName.toLowerCase().contains(query),
        )
        .toList();
    final selectable = visible.where(
      (model) => !existingNames.contains(model.id),
    );
    final allSelected =
        selectable.isNotEmpty &&
        selectable.every((model) => _selected.contains(model.id));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Row(
                children: [
                  Icon(
                    Icons.memory_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('模型列表', style: theme.textTheme.titleSmall),
                        Text(
                          '通过服务商接口读取，支持多模态能力识别。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final button = OutlinedButton.icon(
                onPressed: _fetching ? null : _fetchModels,
                icon: _fetching
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_outlined, size: 18),
                label: Text(
                  _fetching ? '读取中' : (_remoteModels.isEmpty ? '获取模型' : '刷新列表'),
                ),
              );
              if (constraints.maxWidth < 430) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: button),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 8),
                  button,
                ],
              );
            },
          ),
          if (_fetchError != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _fetchError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          if (_fetching) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (!_fetching && _remoteModels.isEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  Icons.cloud_queue_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '填写地址与密钥后点击“获取模型”，再勾选要使用的模型。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_remoteModels.isNotEmpty) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: '搜索模型',
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        onPressed: _search.clear,
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${visible.length} 个模型',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: selectable.isEmpty
                      ? null
                      : () => setState(() {
                          if (allSelected) {
                            for (final model in selectable) {
                              _selected.remove(model.id);
                            }
                          } else {
                            _selected.addAll(
                              selectable.map((model) => model.id),
                            );
                          }
                        }),
                  child: Text(allSelected ? '取消全选' : '全选'),
                ),
              ],
            ),
            Container(
              height: 270,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
                ),
              ),
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        '没有匹配的模型',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.45,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        indent: 48,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.05,
                        ),
                      ),
                      itemBuilder: (context, index) {
                        final model = visible[index];
                        return _modelTile(
                          theme,
                          model,
                          alreadyAdded: existingNames.contains(model.id),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _modelTile(
    ThemeData theme,
    RemoteAiModel model, {
    required bool alreadyAdded,
  }) {
    final selected = alreadyAdded || _selected.contains(model.id);
    final badges = <Widget>[
      if (model.supportsVision)
        _Badge(
          icon: Icons.image_outlined,
          text: '图片理解',
          color: theme.colorScheme.tertiary,
        ),
      if (model.contextWindow != null)
        _Badge(
          icon: Icons.memory_rounded,
          text: '${_formatTokens(model.contextWindow!)} 上下文',
          color: theme.colorScheme.primary,
        ),
      if (model.maxOutputTokens != null)
        _Badge(
          icon: Icons.output_rounded,
          text: '${_formatTokens(model.maxOutputTokens!)} 输出',
          color: theme.colorScheme.secondary,
        ),
    ];
    return InkWell(
      onTap: alreadyAdded
          ? null
          : () => setState(() {
              if (selected) {
                _selected.remove(model.id);
              } else {
                _selected.add(model.id);
              }
            }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: selected,
              onChanged: alreadyAdded
                  ? null
                  : (value) => setState(() {
                      if (value == true) {
                        _selected.add(model.id);
                      } else {
                        _selected.remove(model.id);
                      }
                    }),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          model.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (alreadyAdded)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '已添加',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    model.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 11.5,
                    ),
                  ),
                  if (badges.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Wrap(spacing: 5, runSpacing: 4, children: badges),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(
    ThemeData theme,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTokens(int value) {
  if (value >= 1000000) {
    final millions = value / 1000000;
    return '${millions % 1 == 0 ? millions.toStringAsFixed(0) : millions.toStringAsFixed(1)}M';
  }
  if (value >= 1000) {
    final thousands = value / 1000;
    return '${thousands % 1 == 0 ? thousands.toStringAsFixed(0) : thousands.toStringAsFixed(1)}K';
  }
  return '$value';
}
