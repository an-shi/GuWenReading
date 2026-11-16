import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/db/local_database.dart';
import 'core/providers.dart';
import 'core/storage/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await LocalDatabase.open();
  final container = ProviderContainer(overrides: [
    localDatabaseProvider.overrideWithValue(database),
  ]);
  await container.read(settingsProvider.notifier).load();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const GuWenApp(),
    ),
  );
}
