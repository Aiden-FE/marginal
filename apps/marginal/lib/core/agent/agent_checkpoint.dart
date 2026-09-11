import 'dart:convert';

import '../provider/provider_transport.dart';
import 'agent_budget.dart';

enum AgentStatus {
  idle,
  running,
  awaitingApproval,
  completed,
  failed,
  cancelled,
  budgetExceeded,
}

class AgentCheckpoint {
  AgentCheckpoint({
    required this.id,
    required this.runId,
    required this.status,
    required this.turn,
    required this.messages,
    required this.usage,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  final String id, runId;
  final AgentStatus status;
  final int turn;
  final List<ChatMessage> messages;
  final BudgetUsage usage;
  final DateTime createdAt;
  Map<String, Object?> toJson() => {
    'id': id,
    'run_id': runId,
    'status': status.name,
    'turn': turn,
    'messages': messages.map((e) => e.toJson()).toList(),
    'usage': usage.toJson(),
    'created_at': createdAt.toIso8601String(),
  };
  String encode() => jsonEncode(toJson());
  factory AgentCheckpoint.fromJson(
    Map<String, Object?> json,
  ) => AgentCheckpoint(
    id: json['id'] as String,
    runId: json['run_id'] as String,
    status: AgentStatus.values.byName(json['status'] as String),
    turn: (json['turn'] as num).toInt(),
    messages: (json['messages'] as List)
        .map((e) => ChatMessage.fromJson((e as Map).cast<String, Object?>()))
        .toList(),
    usage: BudgetUsage.fromJson((json['usage'] as Map).cast<String, Object?>()),
    createdAt: DateTime.parse(json['created_at'] as String),
  );
  factory AgentCheckpoint.decode(String value) => AgentCheckpoint.fromJson(
    (jsonDecode(value) as Map).cast<String, Object?>(),
  );
}
