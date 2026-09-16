import 'package:flutter/material.dart';

import '../features/ai/ai_workspace_page.dart';
import '../features/library/library_page.dart';
import '../features/settings/settings_page.dart';
import 'marginal_theme.dart';
import 'platform_services.dart';
import 'vector_icons.dart';

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
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? MarginalColors.nightSurface
              : MarginalColors.surface,
          indicatorColor: MarginalColors.accentSoft,
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected
                  ? MarginalColors.accent
                  : (Theme.of(context).brightness == Brightness.dark
                        ? MarginalColors.nightInk
                        : MarginalColors.ink),
              size: 23,
            );
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              color: selected ? MarginalColors.accent : MarginalColors.muted,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) =>
              setState(() => _selectedIndex = index),
          destinations: const [
            NavigationDestination(
              icon: VectorIcon(VectorIconKind.library),
              selectedIcon: VectorIcon(VectorIconKind.library),
              label: '书库',
            ),
            NavigationDestination(
              icon: VectorIcon(VectorIconKind.ai),
              selectedIcon: VectorIcon(VectorIconKind.ai),
              label: 'AI',
            ),
            NavigationDestination(
              icon: VectorIcon(VectorIconKind.person),
              selectedIcon: VectorIcon(VectorIconKind.person),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}
