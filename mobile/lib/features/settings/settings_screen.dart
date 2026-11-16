import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/providers.dart';
import '../../core/storage/settings_controller.dart';
import '../../providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _apiController;
  late final TextEditingController _directBaseController;
  late final TextEditingController _directModelController;
  late final TextEditingController _directKeyController;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _savingApi = false;
  bool _savingAi = false;
  bool _authLoading = false;
  bool _registerMode = false;
  bool _syncing = false;
  bool _clearing = false;
  String? _connectionMessage;
  bool? _connected;
  int _cachedBooks = 0;
  int _pendingWrites = 0;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _apiController = TextEditingController(text: settings.apiBase);
    _directBaseController = TextEditingController(text: settings.directBaseUrl);
    _directModelController = TextEditingController(text: settings.directModel);
    _directKeyController = TextEditingController(text: settings.directApiKey);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
  }

  @override
  void dispose() {
    _apiController.dispose();
    _directBaseController.dispose();
    _directModelController.dispose();
    _directKeyController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final db = ref.read(localDatabaseProvider);
    final library = ref.read(libraryRepositoryProvider);
    final cached = await library.cachedBookCount();
    final pending = await db.pendingWriteCount();
    if (mounted) {
      setState(() {
        _cachedBooks = cached;
        _pendingWrites = pending;
      });
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _saveApiBase() async {
    setState(() {
      _savingApi = true;
      _connectionMessage = null;
      _connected = null;
    });
    try {
      await ref.read(settingsProvider.notifier).setApiBase(_apiController.text);
      await Future<void>.delayed(Duration.zero);
      final api = ref.read(apiClientProvider);
      final ok = await api.health();
      if (ok) {
        final settings = ref.read(settingsProvider);
        try {
          await api.registerDevice(
            deviceId: settings.deviceId,
            name: Platform.isAndroid ? 'Android 手机' : 'iPhone',
            platform: Platform.isAndroid ? 'android' : 'ios',
            appVersion: '0.1.0',
          );
        } catch (_) {}
      }
      setState(() {
        _connected = ok;
        _connectionMessage = ok ? '连接成功，书籍与知识库接口可用' : '无法连接。请确认后端已启动并允许局域网访问。';
      });
      ref.invalidate(bookshelfProvider);
      ref.invalidate(tasksProvider);
      ref.invalidate(systemInfoProvider);
      ref.invalidate(entitiesProvider);
      ref.invalidate(eventsProvider);
      await _loadStats();
    } finally {
      if (mounted) setState(() => _savingApi = false);
    }
  }

  Future<void> _saveDirectAi() async {
    setState(() => _savingAi = true);
    try {
      await ref.read(settingsProvider.notifier).setDirectAi(
            baseUrl: _directBaseController.text,
            model: _directModelController.text,
            apiKey: _directKeyController.text,
          );
      _snack('移动端 AI 配置已保存（密钥存于系统安全存储）');
    } finally {
      if (mounted) setState(() => _savingAi = false);
    }
  }

  Future<void> _submitAuth() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      _snack('请输入用户名和密码', error: true);
      return;
    }
    setState(() => _authLoading = true);
    try {
      final api = ref.read(apiClientProvider);
      final result = _registerMode
          ? await api.register(username, password, username)
          : await api.login(username, password);
      await ref.read(settingsProvider.notifier).saveAuth(
            token: result.token,
            username: result.username,
          );
      _snack(_registerMode ? '账户已创建并登录' : '登录成功');
      ref.invalidate(bookshelfProvider);
      ref.invalidate(tasksProvider);
      ref.invalidate(systemInfoProvider);
      ref.invalidate(entitiesProvider);
      ref.invalidate(eventsProvider);
      await _loadStats();
    } catch (error) {
      _snack(error is ApiException ? error.message : '$error', error: true);
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(settingsProvider.notifier).logout();
    _snack('已退出登录');
    ref.invalidate(bookshelfProvider);
    ref.invalidate(tasksProvider);
    ref.invalidate(systemInfoProvider);
  }

  Future<void> _syncPending() async {
    setState(() => _syncing = true);
    try {
      final count = await ref.read(readerRepositoryProvider).flushPending();
      _snack(count > 0 ? '已同步 $count 条本地记录' : '没有待同步记录');
      await _loadStats();
    } catch (error) {
      _snack('同步失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除阅读缓存？'),
        content: const Text('将删除已下载的书籍章节和移动端直连译文缓存。批注、书签与阅读进度会保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _clearing = true);
    try {
      await ref.read(libraryRepositoryProvider).clearCache();
      await _loadStats();
      _snack('阅读缓存已清除');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final info = ref.watch(systemInfoProvider);
    final theme = Theme.of(context);
    final serverAuthRequired = info.value?['auth_required'] == true;
    final mode = info.value?['mode']?.toString() ?? 'embedded';
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('我的', style: theme.textTheme.titleLarge),
            Text('设置与本地数据',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                )),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 100),
        children: [
          _SectionCard(
            title: '后端服务',
            subtitle: '手机应用独立运行，但书籍解析与共享翻译需要一个古文阅读器后端。',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _apiController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: '接口基础地址',
                    hintText: 'http://192.168.1.10:8765/api/v1',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  Platform.isAndroid
                      ? 'Android 模拟器访问电脑：10.0.2.2；真机请填写电脑局域网地址。'
                      : 'iOS 模拟器可用 127.0.0.1；真机请填写电脑局域网地址。',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9.5,
                    height: 1.5,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton(
                      onPressed: _savingApi ? null : _saveApiBase,
                      child: _savingApi
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('保存并测试连接'),
                    ),
                    const SizedBox(width: 10),
                    if (_connected != null)
                      Icon(
                        _connected! ? Icons.check_circle : Icons.error,
                        size: 18,
                        color: _connected! ? theme.colorScheme.primary : theme.colorScheme.error,
                      ),
                  ],
                ),
                if (_connectionMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _connectionMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _connected == true ? theme.colorScheme.primary : theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    _InfoPill(label: '模式', value: mode == 'server' ? '服务端' : '内嵌'),
                    const SizedBox(width: 7),
                    _InfoPill(label: '版本', value: info.value?['version']?.toString() ?? '—'),
                    const SizedBox(width: 7),
                    _InfoPill(label: '认证', value: serverAuthRequired ? '必须登录' : '免登录'),
                  ],
                ),
              ],
            ),
          ),
          _SectionCard(
            title: '账户',
            subtitle: serverAuthRequired
                ? '当前后端为服务端模式，需要登录后访问书架与同步数据。'
                : '本地模式无需账户。部署服务端后可登录并共享数据。',
            child: settings.authenticated
                ? Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                        child: Text(
                          (settings.username ?? 'U').substring(0, 1),
                          style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(settings.username ?? '已登录',
                                style: theme.textTheme.titleSmall),
                            Text('令牌保存在系统安全存储',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 9.5,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                                )),
                          ],
                        ),
                      ),
                      TextButton(onPressed: _logout, child: const Text('退出')),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!serverAuthRequired)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '无需登录即可阅读与使用本地缓存。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                      TextField(
                        controller: _usernameController,
                        decoration: const InputDecoration(labelText: '用户名'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: '密码（至少 8 位）'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => setState(() => _registerMode = !_registerMode),
                            child: Text(_registerMode ? '已有账户？登录' : '注册首个账户'),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: _authLoading ? null : _submitAuth,
                            child: _authLoading
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(_registerMode ? '注册' : '登录'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          _SectionCard(
            title: '移动端 AI',
            subtitle: '共享翻译使用后端模型；手机直连时由手机端直接调用 OpenAI 兼容接口。人工译文始终不会被自动覆盖。',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'shared', label: Text('后端共享')),
                    ButtonSegment(value: 'direct', label: Text('手机直连')),
                    ButtonSegment(value: 'hybrid', label: Text('混合')),
                  ],
                  selected: {settings.translationMode},
                  onSelectionChanged: (value) => controller.setTranslationMode(value.first),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  switch (settings.translationMode) {
                    'direct' => '翻译在手机上执行，离线后网络恢复即可继续。译文只保存在本机。',
                    'hybrid' => '优先请求后端翻译；网络不可用时改用手机直连模型。',
                    _ => '翻译任务由后端执行，可在多设备查看进度和结果。',
                  },
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.6,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.48),
                  ),
                ),
                if (settings.translationMode != 'shared') ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _directBaseController,
                    decoration: const InputDecoration(
                      labelText: '直连接口地址',
                      hintText: 'https://api.openai.com/v1',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _directModelController,
                    decoration: const InputDecoration(
                      labelText: '模型名称',
                      hintText: 'gpt-4o-mini / deepseek-chat',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _directKeyController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: '接口密钥',
                      hintText: settings.directApiKey.isNotEmpty ? '已保存，留空则保持不变' : 'sk-...',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (settings.directAiConfigured)
                        Row(
                          children: [
                            Icon(Icons.lock_outline, size: 13, color: theme.colorScheme.primary),
                            const SizedBox(width: 4),
                            Text('已配置',
                                style: TextStyle(fontSize: 10.5, color: theme.colorScheme.primary)),
                          ],
                        ),
                      const Spacer(),
                      FilledButton.tonal(
                        onPressed: _savingAi ? null : _saveDirectAi,
                        child: _savingAi
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('保存直连配置'),
                      ),
                    ],
                  ),
                  if (!settings.directAiConfigured)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '直连模式需要填写接口地址、模型和密钥。密钥存储于系统安全存储，不写入日志。',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 9.5,
                          color: theme.colorScheme.tertiary,
                          height: 1.5,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          _SectionCard(
            title: '阅读偏好',
            subtitle: '这些设置会立即应用于阅读器。',
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('主题'),
                    const Spacer(),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'paper', label: Text('纸张')),
                        ButtonSegment(value: 'light', label: Text('浅色')),
                        ButtonSegment(value: 'dark', label: Text('深色')),
                      ],
                      selected: {settings.themeMode},
                      onSelectionChanged: (value) => controller.setTheme(value.first),
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('字号'),
                    Expanded(
                      child: Slider(
                        value: settings.fontSize,
                        min: 14,
                        max: 28,
                        divisions: 14,
                        label: settings.fontSize.round().toString(),
                        onChanged: controller.setFontSize,
                      ),
                    ),
                    SizedBox(
                      width: 28,
                      child: Text(settings.fontSize.round().toString(),
                          textAlign: TextAlign.right,
                          style: theme.textTheme.labelMedium),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('行距'),
                    Expanded(
                      child: Slider(
                        value: settings.lineHeight,
                        min: 1.4,
                        max: 2.6,
                        divisions: 12,
                        label: settings.lineHeight.toStringAsFixed(1),
                        onChanged: controller.setLineHeight,
                      ),
                    ),
                    SizedBox(
                      width: 28,
                      child: Text(settings.lineHeight.toStringAsFixed(1),
                          textAlign: TextAlign.right,
                          style: theme.textTheme.labelMedium),
                    ),
                  ],
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('打开章节时自动翻译'),
                  subtitle: const Text('仅供已配置翻译方式时使用'),
                  value: settings.autoTranslate,
                  onChanged: controller.setAutoTranslate,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('默认阅读模式'),
                  trailing: DropdownButton<String>(
                    value: settings.defaultReadingMode,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'alternating', child: Text('原文译文交替')),
                      DropdownMenuItem(value: 'original', child: Text('原文优先')),
                      DropdownMenuItem(value: 'independent', child: Text('原文/译文切换')),
                      DropdownMenuItem(value: 'sentence', child: Text('逐句对照')),
                    ],
                    onChanged: (value) {
                      if (value != null) controller.setDefaultReadingMode(value);
                    },
                  ),
                ),
              ],
            ),
          ),
          _SectionCard(
            title: '本地数据',
            subtitle: '本地优先。已下载章节可离线阅读，批注与进度先写入本机。',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _StatBox(value: '$_cachedBooks', label: '缓存书目'),
                    const SizedBox(width: 10),
                    _StatBox(value: '$_pendingWrites', label: '待同步记录'),
                    const Spacer(),
                    TextButton(
                      onPressed: _syncing ? null : _syncPending,
                      child: Text(_syncing ? '同步中…' : '立即同步'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _clearing ? null : _clearCache,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: const Text('清除阅读缓存'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('设备编号', style: theme.textTheme.labelSmall),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        settings.deviceId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 9.5,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: settings.deviceId));
                        _snack('设备编号已复制');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          _SectionCard(
            title: '关于古文阅读器',
            subtitle: 'AI 古籍阅读、文言文翻译与历史知识研究工具。',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '原文完整保留 · 译文精确关联 · 知识有据可查 · 双端独立可用 · 本地优先',
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.7,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '当前版本 0.1.0。扫描版 PDF 的文字识别尚未实现；AI 抽取的人物关系与事件默认处于待审核状态，不能视为确定史实。',
                  style: theme.textTheme.labelSmall?.copyWith(
                    height: 1.7,
                    fontSize: 9.5,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(
            fontFamily: 'serif',
            fontWeight: FontWeight.w600,
          )),
          const SizedBox(height: 3),
          Text(subtitle,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9.5,
                height: 1.55,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              )),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text('$label · $value',
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 9,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          )),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: 'serif',
                fontWeight: FontWeight.w700,
              )),
          Text(label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
              )),
        ],
      ),
    );
  }
}
