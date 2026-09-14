import 'package:flutter/material.dart';

import '../../app/approval_service.dart';
import '../../app/platform_services.dart';
import '../../core/types.dart';

class ApprovalsPage extends StatefulWidget {
  const ApprovalsPage({super.key, required this.services, required this.work});
  final PlatformServices services;
  final Work work;
  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> {
  List<Proposal> _items = [];
  final Set<String> _selected = {};
  late final ApprovalService _service;
  @override
  void initState() {
    super.initState();
    _service = ApprovalService(widget.services.repository);
    _load();
  }

  Future<void> _load() async {
    final items = await widget.services.repository.listProposals(
      widget.work.id,
    );
    if (mounted) setState(() => _items = items);
  }

  List<String> _diff(Proposal p) {
    try {
      final j = decodeMap(p.payload);
      if (p.type == 'text_repair') {
        final patches = (j['patches'] as List? ?? const []);
        return [
          '章节：${j['chapterId'] ?? '未知'}',
          for (final raw in patches)
            '段落 ${(raw as Map)['paraIndex']}: “${raw['original']}” → “${raw['replacement']}”',
        ];
      }
      return ['类型：${p.type}', '操作：${j['operation'] ?? j['action'] ?? '结构化提案'}'];
    } catch (_) {
      return ['无效提案数据'];
    }
  }

  Future<void> _approveBatch() async {
    final batch = _items
        .where(
          (p) =>
              _selected.contains(p.id) &&
              p.status == 'pending' &&
              p.type == 'text_repair',
        )
        .toList();
    if (batch.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认批量批准？'),
        content: Text('将批准 ${batch.length} 条正文修复提案，正文会生成新的修订记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认批准'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    var approved = 0;
    for (final p in batch) {
      try {
        await _service.approve(p);
        approved++;
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('提案 ${p.id} 批准失败：$error')));
        }
      }
    }
    if (mounted) {
      setState(() => _selected.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已批准 $approved/${batch.length} 条提案')),
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('提案审批'),
      actions: [
        if (_selected.isNotEmpty)
          TextButton(onPressed: _approveBatch, child: const Text('批量批准安全类型')),
      ],
    ),
    body: _items.isEmpty
        ? const Center(child: Text('还没有提案。'))
        : ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final p in _items)
                Card(
                  child: ListTile(
                    leading: p.status == 'pending' && p.type == 'text_repair'
                        ? Checkbox(
                            value: _selected.contains(p.id),
                            onChanged: (v) => setState(
                              () => v == true
                                  ? _selected.add(p.id)
                                  : _selected.remove(p.id),
                            ),
                          )
                        : null,
                    title: Text('${p.type} · ${p.status}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [for (final line in _diff(p)) Text(line)],
                    ),
                    isThreeLine: true,
                    trailing: p.status != 'pending'
                        ? null
                        : Wrap(
                            children: [
                              TextButton(
                                onPressed: () async {
                                  await _service.reject(p);
                                  _load();
                                },
                                child: const Text('拒绝'),
                              ),
                              FilledButton(
                                onPressed: () async {
                                  await _service.approve(p);
                                  _load();
                                },
                                child: const Text('批准'),
                              ),
                            ],
                          ),
                  ),
                ),
            ],
          ),
  );
}
