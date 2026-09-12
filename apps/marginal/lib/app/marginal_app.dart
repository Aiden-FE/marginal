import 'package:flutter/material.dart';

import 'marginal_theme.dart';
import 'platform_services.dart';
import '../features/library/library_page.dart';
import '../features/settings/settings_page.dart';

class MarginalApp extends StatelessWidget {
  const MarginalApp({super.key, required this.services});

  final PlatformServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Marginal',
      theme: MarginalTheme.light(),
      darkTheme: MarginalTheme.dark(),
      routes: {
        '/settings': (_) => const SettingsPage(),
        '/entities': (_) => const EntitiesPage(),
        '/illustrations': (_) => const IllustrationsPage(),
      },
      home: LibraryPage(services: services),
    );
  }
}
