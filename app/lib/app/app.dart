import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/settings_controller.dart';
import 'theme.dart';
import 'shell/app_shell.dart';

class GuWenApp extends ConsumerWidget {
  const GuWenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: '古文阅读器',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(settings),
      home: const AppShell(),
    );
  }
}
