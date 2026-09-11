import 'package:flutter/material.dart';

import 'platform_services.dart';
import '../features/library/library_page.dart';

class MarginalApp extends StatelessWidget {
  const MarginalApp({super.key, required this.services});

  final PlatformServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Marginal',
      theme: ThemeData.from(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4B5563),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData.from(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9CA3AF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: LibraryPage(services: services),
    );
  }
}
