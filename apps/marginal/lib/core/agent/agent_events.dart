sealed class AgentEvent {
  AgentEvent({this.seq = 0, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();
  final int seq;
  final DateTime timestamp;
  Map<String, Object?> toJson() => {
    'type': runtimeType.toString(),
    'seq': seq,
    'timestamp': timestamp.toIso8601String(),
  };
}

class RunStartedEvent extends AgentEvent {
  RunStartedEvent(this.runId, {super.seq, super.timestamp});
  final String runId;
  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'run_id': runId};
}

class AssistantMessageEvent extends AgentEvent {
  AssistantMessageEvent(
    this.content, {
    this.toolCalls = 0,
    super.seq,
    super.timestamp,
  });
  final String? content;
  final int toolCalls;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'content': content,
    'tool_calls': toolCalls,
  };
}

class ToolCallRequestedEvent extends AgentEvent {
  ToolCallRequestedEvent(
    this.id,
    this.name,
    this.arguments, {
    super.seq,
    super.timestamp,
  });
  final String id, name;
  final Map<String, Object?> arguments;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'id': id,
    'name': name,
    'arguments': arguments,
  };
}

class ApprovalRequiredEvent extends AgentEvent {
  ApprovalRequiredEvent(this.calls, {super.seq, super.timestamp});
  final List<({String id, String name})> calls;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'calls': calls.map((e) => {'id': e.id, 'name': e.name}).toList(),
  };
}

class ToolCallCompletedEvent extends AgentEvent {
  ToolCallCompletedEvent(
    this.id,
    this.name,
    this.isError,
    this.content, {
    super.seq,
    super.timestamp,
  });
  final String id, name;
  final bool isError;
  final String? content;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'id': id,
    'name': name,
    'is_error': isError,
    'content': content,
  };
}

class CheckpointSavedEvent extends AgentEvent {
  CheckpointSavedEvent(
    this.checkpointId,
    this.turn, {
    super.seq,
    super.timestamp,
  });
  final String checkpointId;
  final int turn;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'checkpoint_id': checkpointId,
    'turn': turn,
  };
}

class BudgetExceededEvent extends AgentEvent {
  BudgetExceededEvent(this.limit, this.usage, {super.seq, super.timestamp});
  final String limit;
  final int usage;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'limit': limit,
    'usage': usage,
  };
}

class RunCompletedEvent extends AgentEvent {
  RunCompletedEvent(this.output, this.turns, {super.seq, super.timestamp});
  final String? output;
  final int turns;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'output': output,
    'turns': turns,
  };
}

class RunFailedEvent extends AgentEvent {
  RunFailedEvent(this.error, {super.seq, super.timestamp});
  final String error;
  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'error': error};
}

class RunCancelledEvent extends AgentEvent {
  RunCancelledEvent(this.reason, {super.seq, super.timestamp});
  final String reason;
  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'reason': reason};
}
