import 'package:flutter/material.dart';

import '../../features/bookshelf/bookshelf_screen.dart';
import '../../features/knowledge/knowledge_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/tasks/tasks_screen.dart';

class _ShellDestination {
  const _ShellDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const _destinations = [
  _ShellDestination(
    icon: Icons.menu_book_outlined,
    selectedIcon: Icons.menu_book,
    label: '书架',
  ),
  _ShellDestination(
    icon: Icons.search_rounded,
    selectedIcon: Icons.manage_search_rounded,
    label: '检索',
  ),
  _ShellDestination(
    icon: Icons.hub_outlined,
    selectedIcon: Icons.hub_rounded,
    label: '知识',
  ),
  _ShellDestination(
    icon: Icons.task_alt_outlined,
    selectedIcon: Icons.task_alt,
    label: '任务',
  ),
  _ShellDestination(
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune,
    label: '我的',
  ),
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
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;
    final pages = const [
      BookshelfScreen(),
      SearchScreen(),
      KnowledgeScreen(),
      TasksScreen(),
      SettingsScreen(),
    ];
    final content = IndexedStack(index: _index, children: pages);
    if (!wide) {
      return Scaffold(
        body: content,
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
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            extended: width >= 1180,
            minExtendedWidth: 210,
            labelType: width >= 1180
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            onDestinationSelected: (value) => setState(() => _index = value),
            leading: Padding(
              padding: const EdgeInsets.fromLTRB(10, 18, 10, 22),
              child: Column(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Center(
                      child: Text(
                        '古',
                        style: TextStyle(
                          fontFamily: 'serif',
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (width >= 1180) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '古文阅读器',
                      style: TextStyle(
                        fontFamily: 'serif',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            destinations: [
              for (final destination in _destinations)
                NavigationRailDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: Text(destination.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: content),
        ],
      ),
    );
  }
}
