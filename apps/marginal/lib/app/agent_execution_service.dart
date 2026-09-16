import 'dart:async';

import '../core/agent/agent_checkpoint.dart';
import '../core/agent/agent_events.dart';
import '../core/agent/agent_runtime.dart';
import '../core/repository.dart';
import '../core/types.dart' as domain;
import 'ids.dart';
import 'repair_queue.dart';

/// 把 AgentRuntime 的内存事件投影成持久审计记录。
class AgentExecutionSession {
  AgentExecutionSession({
    required this.repository,
    required this.workId,
    required this.runtime,
    String? runId,
  }) : runId = runId ?? newId('run');

  final Repository repository;
  final String workId;
  final AgentRuntime runtime;
  final String runId;
  final Map<String, domain.ToolCall> _calls = {};

  late domain.AgentRun _run;
  StreamSubscription<AgentEvent>? _subscription;
  Future<void> _auditQueue = Future.value();

  Stream<AgentEvent> get events => runtime.events;

  Future<AgentRunResult> run(String input) async {
    _run = domain.AgentRun(
      id: runId,
      workId: workId,
      startedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await repository.putAgentRun(_run);
    _subscription = runtime.events.listen((event) {
      _auditQueue = _auditQueue.then((_) => _audit(event));
    });
    final result = await runtime.run(input, runId: runId);
    await _auditQueue;
    _run = _run.copyWith(
      status: result.status.name,
      finishedAt: DateTime.now().millisecondsSinceEpoch,
      inputTokens: result.tokens,
      lastCheckpoint: runtime.lastCheckpoint?.encode() ?? _run.lastCheckpoint,
    );
    await repository.putAgentRun(_run);
    if (result.status == AgentStatus.cancelled ||
        result.status == AgentStatus.failed ||
        result.status == AgentStatus.budgetExceeded) {
      await _expirePendingProposals();
      await _retryRunningRepairJobs();
      await _finishRepairRun('failed');
    } else {
      await _finishRepairRun('completed');
    }
    await _subscription?.cancel();
    return result;
  }

  Future<AgentRunResult> resume() async {
    final runs = await repository.listAgentRuns(workId);
    _run = runs.firstWhere(
      (item) => item.id == runId,
      orElse: () => throw StateError('Agent run $runId not found'),
    );
    if (_run.lastCheckpoint.isEmpty) {
      throw StateError('Agent run $runId has no checkpoint');
    }
    final checkpoint = AgentCheckpoint.decode(_run.lastCheckpoint);
    if (checkpoint.runId != runId) {
      throw StateError('Checkpoint run id mismatch');
    }
    _subscription = runtime.events.listen((event) {
      _auditQueue = _auditQueue.then((_) => _audit(event));
    });
    try {
      final result = await runtime.resumeCheckpoint(checkpoint);
      await _auditQueue;
      _run = _run.copyWith(
        status: result.status.name,
        finishedAt: DateTime.now().millisecondsSinceEpoch,
        inputTokens: result.tokens,
        lastCheckpoint: runtime.lastCheckpoint?.encode() ?? _run.lastCheckpoint,
      );
      await repository.putAgentRun(_run);
      return result;
    } finally {
      await _auditQueue;
      await _subscription?.cancel();
    }
  }

  Future<void> approveToolCalls() async {
    for (final call in _calls.values.where(
      (c) => c.status == 'awaiting_approval',
    )) {
      final updated = call.copyWith(status: 'approved');
      _calls[call.id] = updated;
      await repository.putToolCall(updated);
    }
    await runtime.approveToolCalls();
  }

  Future<void> rejectToolCalls() async {
    for (final call in _calls.values.where(
      (c) => c.status == 'awaiting_approval',
    )) {
      final updated = call.copyWith(status: 'rejected');
      _calls[call.id] = updated;
      await repository.putToolCall(updated);
    }
    await runtime.rejectToolCalls();
  }

  Future<void> _audit(AgentEvent event) async {
    if (event is ToolCallRequestedEvent) {
      final tool = runtime.toolRegistry[event.name];
      // 无效/未注册调用不会形成成功的工具审计记录。
      if (tool == null) return;
      final call = domain.ToolCall(
        id: event.id,
        runId: runId,
        toolName: event.name,
        inputSummary: _summary(event.arguments.toString()),
        status: tool.requiresApproval ? 'awaiting_approval' : 'started',
        startedAt: event.timestamp.millisecondsSinceEpoch,
        schemaVersion: tool.schemaVersion,
        risk: tool.risk.name,
      );
      _calls[event.id] = call;
      await repository.putToolCall(call);
    } else if (event is ToolCallCompletedEvent) {
      final existing = _calls[event.id];
      if (existing == null) return;
      final updated = existing.copyWith(
        status: event.isError ? 'failed' : 'completed',
        resultSummary: _summary(event.content ?? ''),
      );
      _calls[event.id] = updated;
      await repository.putToolCall(updated);
    } else if (event is CheckpointSavedEvent) {
      final encoded = runtime.lastCheckpoint?.encode();
      if (encoded != null) {
        _run = _run.copyWith(lastCheckpoint: encoded);
        await repository.putAgentRun(_run);
      }
    }
  }

  Future<void> _retryRunningRepairJobs() async {
    final queue = RepairQueue(repository);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final job in await repository.listRepairJobs(workId)) {
      if (job.runId != runId || job.status != 'running') continue;
      await queue.fail(job, StateError('Agent 未完成'), now);
    }
  }

  Future<void> _finishRepairRun(String status) async {
    final runs = await repository.listRepairRuns(workId);
    final run = runs.where((item) => item.id == runId).firstOrNull;
    if (run == null) return;
    await repository.putRepairRun(
      run.copyWith(
        status: status,
        finishedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> _expirePendingProposals() async {
    for (final proposal in await repository.listProposals(workId)) {
      if (proposal.runId == runId && proposal.status == 'pending') {
        await repository.updateProposal(
          domain.Proposal(
            id: proposal.id,
            workId: proposal.workId,
            runId: proposal.runId,
            type: proposal.type,
            payload: proposal.payload,
            status: 'expired',
            createdAt: proposal.createdAt,
            beforeSnapshot: proposal.beforeSnapshot,
            afterSnapshot: proposal.afterSnapshot,
          ),
        );
      }
    }
  }

  String _summary(String value) =>
      value.length <= 1000 ? value : '${value.substring(0, 1000)}…';
}
