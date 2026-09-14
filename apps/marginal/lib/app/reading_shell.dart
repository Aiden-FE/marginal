import 'package:flutter/material.dart';

import '../features/ai/ai_workspace_page.dart';
import '../features/library/library_page.dart';
import '../features/settings/settings_page.dart';
import 'marginal_theme.dart';
import 'platform_services.dart';

class ReadingShell extends StatefulWidget {
  const ReadingShell({super.key, required this.services});

  final PlatformServices services;

  @override
  State<ReadingShell> createState() => _ReadingShellState();
}

class _ReadingShellState extends State<ReadingShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      LibraryPage(
        services: widget.services,
        showWorkspaceFeatures: true,
        showAppBar: false,
      ),
      AiWorkspacePage(services: widget.services),
      SettingsPage(services: widget.services),
    ];
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? MarginalColors.nightSurface
            : MarginalColors.surface,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: '书库',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
