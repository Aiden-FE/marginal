import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/agent_execution_service.dart';
import '../../app/ids.dart';
import '../../app/platform_services.dart';
import '../../app/reading_tools.dart';
import '../../core/agent/agent_events.dart';
import '../../core/agent/agent_runtime.dart';
import '../../core/provider/demo_transport.dart';
import '../../core/provider/provider_transport.dart';
import '../../core/types.dart';

class AgentPage extends StatefulWidget {
  const AgentPage({super.key, required this.services, required this.work});
  final PlatformServices services;
  final Work work;
  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  late final AgentRuntime _runtime;
  late final AgentExecutionSession _session;
  late final StreamSubscription<AgentEvent> _subscription;
  final _input = TextEditingController();
  final _events = <String>[];
  bool _waitingApproval = false;

  @override
  void initState() {
    super.initState();
    final transport = DemoTransport(
      fallback: (request) async => ChatResponse.text(
        '演示 Agent 已读取你的请求：${request.messages.last.content ?? ''}',
      ),
    );
    final runId = newId('run');
    _runtime = AgentRuntime(
      transport: transport,
      toolRegistry: readingTools(
        repository: widget.services.repository,
        workId: widget.work.id,
        runId: runId,
      ),
      systemPrompt: '你是 Marginal 阅读助手。只使用书稿工具；写入必须先形成提案并等待用户确认。',
    );
    _session = AgentExecutionSession(
      repository: widget.services.repository,
      workId: widget.work.id,
      runtime: _runtime,
      runId: runId,
    );
    _subscription = _session.events.listen((event) {
      if (!mounted) return;
      setState(() {
        _events.add(event.toString());
        _waitingApproval = event is ApprovalRequiredEvent;
      });
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    _input.dispose();
    _runtime.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    setState(() => _events.add('用户：$text'));
    await _session.run(text);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Agent · ${widget.work.title}')),
    body: Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _events.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_events[i]),
            ),
          ),
        ),
        if (_waitingApproval)
          Card(
            margin: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Expanded(child: Text('Agent 请求执行写入工具，是否批准？')),
                TextButton(
                  onPressed: () {
                    _session.rejectToolCalls();
                    setState(() => _waitingApproval = false);
                  },
                  child: const Text('拒绝'),
                ),
                FilledButton(
                  onPressed: () {
                    _session.approveToolCalls();
                    setState(() => _waitingApproval = false);
                  },
                  child: const Text('批准'),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  onSubmitted: (_) => _run(),
                  decoration: const InputDecoration(
                    hintText: '询问当前书稿…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(onPressed: _run, icon: const Icon(Icons.send)),
            ],
          ),
        ),
      ],
    ),
  );
}
