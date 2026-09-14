import 'package:flutter/material.dart';

import '../../app/marginal_theme.dart';
import '../../app/platform_services.dart';
import '../../app/provider_store.dart';
import '../../app/reading_prefs.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.services});

  final PlatformServices? services;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final ProviderStore _store =
      widget.services?.providerStore ?? ProviderStore();
  bool _ownStore = false;
  ReaderTheme _theme = ReaderTheme.paper;
  double _fontSize = defaultFontSize;
  double _lineHeight = 1.8;
  bool _autoRead = false;

  @override
  void initState() {
    super.initState();
    _ownStore = widget.services == null;
    if (_ownStore) _store.load();
  }

  @override
  void dispose() {
    if (_ownStore) _store.dispose();
    super.dispose();
  }

  Future<void> _editProvider([ProviderEntry? existing]) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final url = TextEditingController(
      text: existing?.baseUrl ?? 'https://api.example.com/v1',
    );
    final key = TextEditingController(text: existing?.apiKey ?? '');
    final model = TextEditingController(text: existing?.model ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? '添加供应商' : '编辑供应商'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              TextField(
                controller: url,
                decoration: const InputDecoration(labelText: 'Base URL'),
              ),
              TextField(
                controller: key,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'API Key'),
              ),
              TextField(
                controller: model,
                decoration: const InputDecoration(labelText: '模型'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != true || name.text.trim().isEmpty) return;
    final id =
        existing?.id ?? 'provider-${DateTime.now().microsecondsSinceEpoch}';
    await _store.upsert(
      ProviderEntry(
        id: id,
        name: name.text.trim(),
        baseUrl: url.text.trim(),
        apiKey: key.text,
        model: model.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('我的')),
    body: AnimatedBuilder(
      animation: _store,
      builder: (_, _) => ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 48),
        children: [
          _section('阅读偏好', '全局默认值；阅读器内仍可临时调整当前书稿。'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('默认主题'),
                  trailing: DropdownButton<ReaderTheme>(
                    value: _theme,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                        value: ReaderTheme.paper,
                        child: Text('纸张'),
                      ),
                      DropdownMenuItem(
                        value: ReaderTheme.eyecare,
                        child: Text('护眼'),
                      ),
                      DropdownMenuItem(
                        value: ReaderTheme.dark,
                        child: Text('深色'),
                      ),
                    ],
                    onChanged: (value) => setState(() => _theme = value!),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.format_size_outlined),
                  title: const Text('默认字号'),
                  subtitle: Slider(
                    value: _fontSize,
                    min: minFontSize,
                    max: maxFontSize,
                    divisions: 16,
                    label: _fontSize.round().toString(),
                    onChanged: (value) => setState(() => _fontSize = value),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.format_line_spacing_outlined),
                  title: const Text('默认行距'),
                  subtitle: Slider(
                    value: _lineHeight,
                    min: 1.6,
                    max: 2.2,
                    divisions: 6,
                    label: _lineHeight.toStringAsFixed(1),
                    onChanged: (value) => setState(() => _lineHeight = value),
                  ),
                ),
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.play_circle_outline_rounded),
                  title: const Text('默认开启自动阅读'),
                  value: _autoRead,
                  onChanged: (value) => setState(() => _autoRead = value),
                ),
              ],
            ),
          ),
          _section('AI 供应商', '为修复、实体提取和插图配置模型服务。'),
          ..._store.providers.map(
            (provider) => _ProviderCard(
              store: _store,
              entry: provider,
              onEdit: provider.id == 'demo'
                  ? null
                  : () => _editProvider(provider),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              onPressed: _editProvider,
              icon: const Icon(Icons.add),
              label: const Text('添加 OpenAI-compatible 供应商'),
            ),
          ),
          _section('数据与安全', '书稿数据保存在本地；供应商凭据使用平台安全存储。'),
          const Card(
            child: ListTile(
              leading: Icon(Icons.security_outlined),
              title: Text('本地优先'),
              subtitle: Text('无 provider 时仍可正常导入、阅读和保存进度。'),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.import_export_outlined),
              title: Text('全书包导入 / 导出'),
              subtitle: Text('单本书稿的文本、修订、实体卡与插图可通过 .mabk 携带。'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _section(String title, String description) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: MarginalTheme.serif.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: MarginalColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: const TextStyle(fontSize: 12, color: MarginalColors.muted),
        ),
      ],
    ),
  );
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.store, required this.entry, this.onEdit});

  final ProviderStore store;
  final ProviderEntry entry;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: entry.id == 'demo'
            ? MarginalColors.accentSoft
            : Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          entry.id == 'demo' ? Icons.auto_awesome : Icons.cloud_outlined,
        ),
      ),
      title: Text(entry.name),
      subtitle: Text(
        '${entry.model}\n${entry.baseUrl}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: Wrap(
        children: [
          IconButton(
            tooltip: '连通性诊断',
            onPressed: () async {
              final result = await store.diagnose(entry);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result == 'direct' ? '供应商可直连' : '需要代理或检查配置'),
                ),
              );
            },
            icon: Icon(
              entry.diagnostic == 'direct'
                  ? Icons.check_circle
                  : Icons.network_check,
              color: entry.diagnostic == 'direct' ? MarginalColors.ok : null,
            ),
          ),
          if (onEdit != null)
            IconButton(
              tooltip: '编辑',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (entry.id != 'demo')
            IconButton(
              tooltip: '删除',
              onPressed: () => store.remove(entry.id),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
    ),
  );
}
