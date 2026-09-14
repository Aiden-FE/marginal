import 'package:flutter/material.dart';

import '../../app/marginal_theme.dart';
import '../../app/platform_services.dart';
import '../../app/provider_store.dart';
import '../../core/types.dart';
import '../agent/agent_page.dart';
import '../approvals/approvals_page.dart';

class AiWorkspacePage extends StatefulWidget {
  const AiWorkspacePage({super.key, required this.services, this.initialWork});

  final PlatformServices services;
  final Work? initialWork;

  @override
  State<AiWorkspacePage> createState() => _AiWorkspacePageState();
}

class _AiWorkspacePageState extends State<AiWorkspacePage> {
  List<Work> _works = const [];
  Map<String, int> _pendingByWork = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final works = await widget.services.repository.listWorks();
    final pending = <String, int>{};
    for (final work in works) {
      pending[work.id] = (await widget.services.repository.listProposals(
        work.id,
      )).where((proposal) => proposal.status == 'pending').length;
    }
    if (!mounted) return;
    setState(() {
      _works = works;
      _pendingByWork = pending;
      _loading = false;
    });
  }

  List<ProviderEntry> get _providers => widget.services.providerStore.providers;

  ProviderEntry? get _activeProvider {
    for (final provider in _providers) {
      if (provider.id != 'demo') return provider;
    }
    return _providers.isEmpty ? null : _providers.first;
  }

  Future<void> _openWorkPicker({required bool approvals}) async {
    if (widget.initialWork != null) {
      await _openWork(widget.initialWork!, approvals: approvals);
      return;
    }
    if (_works.isEmpty) {
      _snack('请先在书库导入一本书稿');
      return;
    }
    final work = await showModalBottomSheet<Work>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const ListTile(
              title: Text('选择书稿'),
              subtitle: Text('AI 操作始终绑定到单本书稿'),
            ),
            for (final item in _works)
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(item.title),
                trailing: (_pendingByWork[item.id] ?? 0) == 0
                    ? null
                    : Chip(label: Text('${_pendingByWork[item.id]}')),
                onTap: () => Navigator.of(sheetContext).pop(item),
              ),
          ],
        ),
      ),
    );
    if (!mounted || work == null) return;
    await _openWork(work, approvals: approvals);
  }

  Future<void> _openWork(Work work, {required bool approvals}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => approvals
            ? ApprovalsPage(services: widget.services, work: work)
            : AgentPage(services: widget.services, work: work),
      ),
    );
    _load();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final provider = _activeProvider;
    final hasRealProvider = provider != null && provider.id != 'demo';
    final pendingCount = _pendingByWork.values.fold<int>(0, (a, b) => a + b);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 工作区'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _ProviderCard(
                    provider: provider,
                    connected: hasRealProvider,
                    onConfigure: () =>
                        Navigator.of(context).pushNamed('/settings'),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.fact_check_outlined,
                          title: '待处理提案',
                          value: '$pendingCount',
                          onTap: () => _openWorkPicker(approvals: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.forum_outlined,
                          title: '阅读 Agent',
                          value: _works.isEmpty ? '暂无书稿' : '选择书稿',
                          onTap: () => _openWorkPicker(approvals: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'AI 能力边界',
                    style: MarginalTheme.serif.copyWith(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: MarginalColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _CapabilityRow(
                    icon: Icons.menu_book_outlined,
                    title: '章节 / 正文修复',
                    detail: '先生成提案，批准后才写入修订',
                  ),
                  const _CapabilityRow(
                    icon: Icons.style_outlined,
                    title: '实体卡',
                    detail: '从当前书稿章节提取人物、场景与物品',
                  ),
                  const _CapabilityRow(
                    icon: Icons.image_outlined,
                    title: '段落插图',
                    detail: '以正典实体和段落锚点保持一致性',
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '当前书稿',
                    style: MarginalTheme.serif.copyWith(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: MarginalColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_works.isEmpty)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.menu_book_outlined),
                        title: Text('还没有书稿'),
                        subtitle: Text('先到书库导入 TXT 或 .mabk，再从这里使用 AI。'),
                      ),
                    )
                  else
                    for (final work in _works)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        leading: const CircleAvatar(
                          backgroundColor: MarginalColors.accentSoft,
                          child: Icon(
                            Icons.menu_book_rounded,
                            color: MarginalColors.accent,
                          ),
                        ),
                        title: Text(work.title),
                        subtitle: Text(
                          (_pendingByWork[work.id] ?? 0) == 0
                              ? '暂无待处理提案'
                              : '${_pendingByWork[work.id]} 个待处理提案',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _openWorkPicker(approvals: true),
                      ),
                ],
              ),
            ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.connected,
    required this.onConfigure,
  });

  final ProviderEntry? provider;
  final bool connected;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                connected
                    ? Icons.check_circle_rounded
                    : Icons.info_outline_rounded,
                color: connected ? MarginalColors.ok : MarginalColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                'AI 供应商',
                style: MarginalTheme.serif.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: MarginalColors.ink,
                ),
              ),
              const Spacer(),
              TextButton(onPressed: onConfigure, child: const Text('配置')),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            provider == null
                ? '未配置 · 仅可使用本地演示'
                : connected
                ? '${provider!.name} · ${provider!.model}'
                : '内置演示 · AI 写入功能需要配置 provider',
            style: const TextStyle(color: MarginalColors.muted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: MarginalColors.accent),
            const SizedBox(height: 18),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 12, color: MarginalColors.muted),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: MarginalColors.accent),
    title: Text(title),
    subtitle: Text(detail),
  );
}
