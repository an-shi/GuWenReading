import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guwenreader/app/app.dart';
import 'package:guwenreader/core/local/app_database.dart';
import 'package:guwenreader/core/providers.dart';
import 'package:guwenreader/core/storage/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app shell starts on mobile layout', (tester) async {
    late AppDatabase database;
    late ProviderContainer container;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      database = await AppDatabase.openInMemory();
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      await container.read(settingsProvider.notifier).load();
      await container.read(aiSettingsProvider).seedPrompts();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const GuWenApp()),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pump();
    expect(find.text('我的书架'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.runAsync(database.close);
    container.dispose();
  });

  testWidgets('wide screens use the desktop navigation rail', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late AppDatabase database;
    late ProviderContainer container;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      database = await AppDatabase.openInMemory();
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      await container.read(settingsProvider.notifier).load();
      await container.read(aiSettingsProvider).seedPrompts();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const GuWenApp()),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pump();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('书架'), findsOneWidget);
    expect(find.text('检索'), findsOneWidget);
    await tester.runAsync(database.close);
    container.dispose();
  });
}
