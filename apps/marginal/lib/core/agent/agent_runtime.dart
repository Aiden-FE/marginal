import 'dart:async';

import '../provider/provider_transport.dart';
import 'agent_budget.dart';
import 'agent_checkpoint.dart';
import 'agent_events.dart';
import 'tool_registry.dart';

enum _ApprovalDecision { approve, reject, cancelled }

class AgentRunResult {
  const AgentRunResult({
    required this.runId,
    required this.status,
    this.output,
    this.error,
    this.turns = 0,
    this.toolCalls = 0,
    this.tokens = 0,
  });
  final String runId;
  final AgentStatus status;
  final String? output, error;
  final int turns, toolCalls, tokens;
}

class AgentRuntime {
  AgentRuntime({
    required this.transport,
    ToolRegistry? toolRegistry,
    AgentBudget? budget,
    this.systemPrompt,
  }) : toolRegistry = toolRegistry ?? ToolRegistry(),
       budget = budget ?? const AgentBudget();
  final ProviderTransport transport;
  final ToolRegistry toolRegistry;
  final AgentBudget budget;
  final String? systemPrompt;
  final List<ChatMessage> _messages = [];
  final List<AgentEvent> eventLog = [];
  final _events = StreamController<AgentEvent>.broadcast();
  Stream<AgentEvent> get events => _events.stream;
  AgentStatus _status = AgentStatus.idle;
  AgentStatus get status => _status;
  List<ChatMessage> get history => List.unmodifiable(_messages);
  AgentCheckpoint? lastCheckpoint;
  BudgetUsage get usage => _ledger?.usage ?? const BudgetUsage();
  int _runCounter = 0, _checkpointCounter = 0;
  BudgetTracker? _ledger;
  Completer<_ApprovalDecision>? _approvalGate;
  String? _cancelReason;
  bool _cancelled = false;
  int _currentTurn = 0;

  Future<AgentRunResult> run(String userInput) async {
    if (_status == AgentStatus.running ||
        _status == AgentStatus.awaitingApproval) {
      throw StateError('A run is already active ($_status)');
    }
    final runId = 'run-${++_runCounter}';
    _ledger = BudgetTracker(budget);
    _currentTurn = 0;
    _cancelled = false;
    _cancelReason = null;
    _messages.add(ChatMessage(role: ChatRole.user, content: userInput));
    if (systemPrompt != null &&
        (_messages.isEmpty || _messages.first.role != ChatRole.system)) {
      _messages.insert(
        0,
        ChatMessage(role: ChatRole.system, content: systemPrompt),
      );
    }
    _setStatus(AgentStatus.running);
    _emit(RunStartedEvent(runId));
    await _saveCheckpoint();
    return _loop(runId);
  }

  Future<AgentRunResult> _loop(String runId) async {
    try {
      while (true) {
        if (_cancelled) {
          return _finish(
            runId,
            AgentStatus.cancelled,
            RunCancelledEvent(_cancelReason ?? 'cancelled'),
          );
        }
        if (budget.maxDuration != null) {
          final elapsed = DateTime.now().difference(eventLog.first.timestamp);
          if (elapsed > budget.maxDuration!) {
            _emit(BudgetExceededEvent('maxDuration', elapsed.inMilliseconds));
            return _finish(
              runId,
              AgentStatus.budgetExceeded,
              null,
              output: _lastAssistantContent(),
            );
          }
        }
        _ledger!.turn();
        _currentTurn++;
        final response = await transport.complete(
          ChatRequest(messages: history, tools: toolRegistry.specs),
        );
        if (_cancelled) {
          return _finish(
            runId,
            AgentStatus.cancelled,
            RunCancelledEvent(_cancelReason ?? 'cancelled'),
          );
        }
        if (response.usage != null) {
          _ledger!.tokensUsed(response.usage!.totalTokens);
        }
        _messages.add(response.message);
        _emit(
          AssistantMessageEvent(
            response.message.content,
            toolCalls: response.message.toolCalls.length,
          ),
        );
        await _saveCheckpoint();
        final calls = response.message.toolCalls;
        if (calls.isEmpty) {
          return _finish(
            runId,
            AgentStatus.completed,
            RunCompletedEvent(response.message.content ?? '', _currentTurn),
          );
        }
        for (final call in calls) {
          _emit(ToolCallRequestedEvent(call.id, call.name, call.arguments));
        }
        final needsApproval = calls.any(
          (c) => toolRegistry[c.name]?.requiresApproval ?? false,
        );
        if (needsApproval) {
          _setStatus(AgentStatus.awaitingApproval);
          _emit(
            ApprovalRequiredEvent([
              for (final c in calls) (id: c.id, name: c.name),
            ]),
          );
          _approvalGate = Completer<_ApprovalDecision>();
          final decision = await _approvalGate!.future;
          _approvalGate = null;
          if (decision != _ApprovalDecision.approve) {
            if (decision == _ApprovalDecision.cancelled) {
              return _finish(
                runId,
                AgentStatus.cancelled,
                RunCancelledEvent('cancelled during approval'),
              );
            }
            for (final c in calls) {
              _messages.add(
                ChatMessage(
                  role: ChatRole.tool,
                  content: 'Tool call rejected by user',
                  toolCallId: c.id,
                ),
              );
            }
            await _saveCheckpoint();
            return _finish(
              runId,
              AgentStatus.cancelled,
              RunCancelledEvent('tool calls rejected'),
            );
          }
          _setStatus(AgentStatus.running);
        }
        for (final call in calls) {
          if (_cancelled) {
            return _finish(
              runId,
              AgentStatus.cancelled,
              RunCancelledEvent(_cancelReason ?? 'cancelled'),
            );
          }
          _ledger!.toolCall();
          final result = await toolRegistry.execute(call.name, call.arguments);
          _messages.add(
            ChatMessage(
              role: ChatRole.tool,
              content: result.content,
              toolCallId: call.id,
            ),
          );
          _emit(
            ToolCallCompletedEvent(
              call.id,
              call.name,
              result.isError,
              result.content,
            ),
          );
          await _saveCheckpoint();
        }
      }
    } catch (e) {
      return _finish(
        runId,
        e is BudgetExceededException
            ? AgentStatus.budgetExceeded
            : AgentStatus.failed,
        e is BudgetExceededException
            ? BudgetExceededEvent(e.limit, e.value)
            : RunFailedEvent(e.toString()),
        error: e.toString(),
      );
    }
  }

  Future<void> approveToolCalls() async {
    final gate = _approvalGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete(_ApprovalDecision.approve);
    }
  }

  Future<void> rejectToolCalls() async {
    final gate = _approvalGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete(_ApprovalDecision.reject);
    }
  }

  void cancel({String reason = 'cancelled'}) {
    if (_status != AgentStatus.running &&
        _status != AgentStatus.awaitingApproval) {
      return;
    }
    _cancelled = true;
    _cancelReason = reason;
    final gate = _approvalGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete(_ApprovalDecision.cancelled);
    }
  }

  AgentCheckpoint saveCheckpoint() => _snapshot();
  Future<AgentCheckpoint> _saveCheckpoint() async {
    final cp = _snapshot();
    lastCheckpoint = cp;
    _emit(CheckpointSavedEvent(cp.id, cp.turn));
    return cp;
  }

  AgentCheckpoint _snapshot() => AgentCheckpoint(
    id: 'cp-$_runCounter-${++_checkpointCounter}',
    runId: 'run-$_runCounter',
    status: _status,
    turn: _currentTurn,
    messages: List.of(_messages),
    usage: _ledger?.usage ?? const BudgetUsage(),
  );

  void restoreCheckpoint(AgentCheckpoint checkpoint) {
    if (_status == AgentStatus.running ||
        _status == AgentStatus.awaitingApproval) {
      throw StateError('Cannot restore while a run is active');
    }
    _messages
      ..clear()
      ..addAll(checkpoint.messages);
    _currentTurn = checkpoint.turn;
    _status = checkpoint.status == AgentStatus.running
        ? AgentStatus.idle
        : checkpoint.status;
    _ledger = BudgetTracker(budget)
      ..turns = checkpoint.usage.turns
      ..toolCalls = checkpoint.usage.toolCalls
      ..tokens = checkpoint.usage.tokens;
    lastCheckpoint = checkpoint;
  }

  AgentRunResult _finish(
    String runId,
    AgentStatus status,
    AgentEvent? event, {
    String? output,
    String? error,
  }) {
    _setStatus(status);
    if (event != null) _emit(event);
    return AgentRunResult(
      runId: runId,
      status: status,
      output: output ?? _lastAssistantContent(),
      error: error,
      turns: _currentTurn,
      toolCalls: _ledger?.toolCalls ?? 0,
      tokens: _ledger?.tokens ?? 0,
    );
  }

  String? _lastAssistantContent() {
    for (final m in _messages.reversed) {
      if (m.role == ChatRole.assistant &&
          m.content != null &&
          m.content!.isNotEmpty) {
        return m.content;
      }
    }
    return null;
  }

  void _setStatus(AgentStatus s) {
    _status = s;
  }

  void _emit(AgentEvent event) {
    eventLog.add(event);
    _events.add(event);
  }

  void dispose() {
    _events.close();
  }
}
