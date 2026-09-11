class AgentBudget {
  const AgentBudget({
    this.maxTurns,
    this.maxToolCalls,
    this.maxTokens,
    this.maxDuration,
  });
  final int? maxTurns, maxToolCalls, maxTokens;
  final Duration? maxDuration;
}

class BudgetUsage {
  const BudgetUsage({this.turns = 0, this.toolCalls = 0, this.tokens = 0});
  final int turns, toolCalls, tokens;
  Map<String, Object?> toJson() => {
    'turns': turns,
    'tool_calls': toolCalls,
    'tokens': tokens,
  };
  factory BudgetUsage.fromJson(Map<String, Object?> json) => BudgetUsage(
    turns: (json['turns'] as num?)?.toInt() ?? 0,
    toolCalls: (json['tool_calls'] as num?)?.toInt() ?? 0,
    tokens: (json['tokens'] as num?)?.toInt() ?? 0,
  );
}

class BudgetExceededException implements Exception {
  const BudgetExceededException(this.limit, this.value);
  final String limit;
  final int value;
  @override
  String toString() => 'Budget exceeded: $limit ($value)';
}

class BudgetTracker {
  BudgetTracker(this.budget);
  final AgentBudget budget;
  int turns = 0, toolCalls = 0, tokens = 0;
  BudgetUsage get usage =>
      BudgetUsage(turns: turns, toolCalls: toolCalls, tokens: tokens);
  void turn() {
    turns++;
    if (budget.maxTurns != null && turns > budget.maxTurns!) {
      throw BudgetExceededException('turns', turns);
    }
  }

  void toolCall() {
    toolCalls++;
    if (budget.maxToolCalls != null && toolCalls > budget.maxToolCalls!) {
      throw BudgetExceededException('toolCalls', toolCalls);
    }
  }

  void tokensUsed(int count) {
    tokens += count;
    if (budget.maxTokens != null && tokens > budget.maxTokens!) {
      throw BudgetExceededException('tokens', tokens);
    }
  }
}
