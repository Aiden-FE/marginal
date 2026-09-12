import 'package:flutter/material.dart';

/// 轻量占位页：/settings、/entities、/illustrations 命名路由先行占位，
/// 后续功能落地时替换为真实实现。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => const _PlaceholderScaffold(title: '设置');
}

class EntitiesPage extends StatelessWidget {
  const EntitiesPage({super.key});

  @override
  Widget build(BuildContext context) => const _PlaceholderScaffold(title: '实体');
}

class IllustrationsPage extends StatelessWidget {
  const IllustrationsPage({super.key});

  @override
  Widget build(BuildContext context) => const _PlaceholderScaffold(title: '插图');
}

class _PlaceholderScaffold extends StatelessWidget {
  const _PlaceholderScaffold({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(child: Text('$title（即将上线）')),
  );
}
