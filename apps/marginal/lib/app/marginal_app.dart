import 'package:flutter/material.dart';

import 'marginal_theme.dart';
import 'platform_services.dart';
import '../features/home/home_prototype_page.dart';
import '../features/settings/settings_page.dart';
import 'reading_shell.dart';

class MarginalApp extends StatelessWidget {
  const MarginalApp({super.key, required this.services});

  final PlatformServices services;

  HomeVariant? _prototypeVariant() {
    final query = Uri.base.queryParameters['variant']?.toUpperCase();
    return switch (query) {
      'A' => HomeVariant.continueFirst,
      'B' => HomeVariant.libraryDesk,
      'C' => HomeVariant.readingRhythm,
      'D' => HomeVariant.aiCoReader,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final prototypeVariant = _prototypeVariant();
    return MaterialApp(
      title: 'Marginal',
      theme: MarginalTheme.light(),
      darkTheme: MarginalTheme.dark(),
      routes: {
        '/prototype/home': (_) => HomePrototypePage(
          services: services,
          initialVariant: prototypeVariant,
        ),
        '/settings': (_) => SettingsPage(services: services),
      },
      home: prototypeVariant == null
          ? ReadingShell(services: services)
          : HomePrototypePage(
              services: services,
              initialVariant: prototypeVariant,
            ),
    );
  }
}
