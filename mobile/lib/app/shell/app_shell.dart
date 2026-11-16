import '../../features/bookshelf/bookshelf_screen.dart';
import '../../features/knowledge/knowledge_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/tasks/tasks_screen.dart';
import 'package:flutter/material.dart';

class _ShellDestination {
  const _ShellDestination({required this.icon, required this.selectedIcon, required this.label});
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const _destinations = [
  _ShellDestination(icon: Icons.menu_book_outlined, selectedIcon: Icons.menu_book, label: '书架'),
  _ShellDestination(icon: Icons.travel_explore_outlined, selectedIcon: Icons.travel_explore, label: '知识'),
  _ShellDestination(icon: Icons.sync_outlined, selectedIcon: Icons.sync, label: '任务'),
  _ShellDestination(icon: Icons.tune_outlined, selectedIcon: Icons.tune, label: '我的'),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          BookshelfScreen(),
          KnowledgeScreen(),
          TasksScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          for (final destination in _destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}
