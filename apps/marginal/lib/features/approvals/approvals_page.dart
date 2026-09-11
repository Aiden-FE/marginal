import 'dart:convert';

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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('提案审批')),
    body: _items.isEmpty
        ? const Center(child: Text('还没有提案。'))
        : ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final p in _items)
                Card(
                  child: ListTile(
                    title: Text('${p.type} · ${p.status}'),
                    subtitle: Text(
                      const JsonEncoder.withIndent('  ')
                          .convert(jsonDecode(p.payload)),
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
