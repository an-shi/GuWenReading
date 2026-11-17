import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app/app.dart';
import 'core/local/app_database.dart';
import 'core/providers.dart';
import 'core/storage/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await pdfrxFlutterInitialize();
  } catch (_) {
    // PDF importing will surface a clear error if PDFium is unavailable.
  }
  late final AppDatabase database;
  try {
    database = await AppDatabase.open();
  } catch (error) {
    runApp(_StartupErrorApp(error: '$error'));
    return;
  }
  final container = ProviderContainer(
    overrides: [appDatabaseProvider.overrideWithValue(database)],
  );
  await container.read(settingsProvider.notifier).load();
  await container.read(aiSettingsProvider).seedPrompts();
  runApp(
    UncontrolledProviderScope(container: container, child: const GuWenApp()),
  );
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '古文阅读器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'NotoSansSC',
        fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC'],
      ),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storage_rounded, size: 52),
                  const SizedBox(height: 16),
                  const Text(
                    '无法打开本地数据库',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(error, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  const Text(
                    '请确认应用数据目录可写。如果问题持续，可删除数据目录后重新启动。',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
