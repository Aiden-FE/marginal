import 'dart:convert';

abstract interface class ProviderTransport {
  Future<ChatResponse> complete(ChatRequest request);
}

enum ChatRole { system, user, assistant, tool }

class ToolCall {
  ToolCall({required this.id, required this.name, required this.arguments});
  final String id;
  final String name;
  final Map<String, Object?> arguments;

  factory ToolCall.fromJson(Map<String, Object?> json) {
    final fn = (json['function'] as Map?)?.cast<String, Object?>() ?? json;
    final raw = fn['arguments'];
    final args = raw is String
        ? ((jsonDecode(raw) as Map?)?.cast<String, Object?>() ??
              <String, Object?>{})
        : (raw is Map ? raw.cast<String, Object?>() : <String, Object?>{});
    return ToolCall(
      id: json['id'] as String? ?? 'call',
      name: fn['name'] as String? ?? '',
      arguments: args,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'type': 'function',
    'function': {'name': name, 'arguments': jsonEncode(arguments)},
  };
}

class ChatMessage {
  ChatMessage({
    required this.role,
    this.content,
    this.toolCalls = const [],
    this.toolCallId,
    this.name,
  });
  final ChatRole role;
  final String? content;
  final List<ToolCall> toolCalls;
  final String? toolCallId;
  final String? name;

  Map<String, Object?> toJson() {
    final out = <String, Object?>{'role': role.name, 'content': content};
    if (toolCalls.isNotEmpty) {
      out['tool_calls'] = toolCalls.map((e) => e.toJson()).toList();
    }
    if (toolCallId != null) out['tool_call_id'] = toolCallId;
    if (name != null) out['name'] = name;
    return out;
  }

  factory ChatMessage.fromJson(Map<String, Object?> json) => ChatMessage(
    role: ChatRole.values.firstWhere(
      (r) => r.name == json['role'],
      orElse: () => ChatRole.user,
    ),
    content: json['content'] as String?,
    toolCalls: ((json['tool_calls'] as List?) ?? const [])
        .map((e) => ToolCall.fromJson((e as Map).cast<String, Object?>()))
        .toList(),
    toolCallId: json['tool_call_id'] as String?,
    name: json['name'] as String?,
  );
}

class ToolSpec {
  ToolSpec({
    required this.name,
    this.description = '',
    this.parameters = const {'type': 'object'},
  });
  final String name;
  final String description;
  final Map<String, Object?> parameters;
  Map<String, Object?> toJson() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

class ChatRequest {
  ChatRequest({
    required this.messages,
    this.tools = const [],
    this.model,
    this.temperature,
    this.maxTokens,
  });
  final List<ChatMessage> messages;
  final List<ToolSpec> tools;
  final String? model;
  final double? temperature;
  final int? maxTokens;
  Map<String, Object?> toJson() => {
    if (model != null) 'model': model,
    'messages': messages.map((e) => e.toJson()).toList(),
    if (tools.isNotEmpty) 'tools': tools.map((e) => e.toJson()).toList(),
    if (tools.isNotEmpty) 'tool_choice': 'auto',
    if (temperature != null) 'temperature': temperature,
    if (maxTokens != null) 'max_tokens': maxTokens,
  };
}

class ChatUsage {
  ChatUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    int? totalTokens,
  }) : totalTokens = totalTokens ?? promptTokens + completionTokens;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  factory ChatUsage.fromJson(Map<String, Object?> json) => ChatUsage(
    promptTokens: (json['prompt_tokens'] as num?)?.toInt() ?? 0,
    completionTokens: (json['completion_tokens'] as num?)?.toInt() ?? 0,
    totalTokens: (json['total_tokens'] as num?)?.toInt(),
  );
  Map<String, Object?> toJson() => {
    'prompt_tokens': promptTokens,
    'completion_tokens': completionTokens,
    'total_tokens': totalTokens,
  };
}

class ChatResponse {
  ChatResponse({
    required this.message,
    this.finishReason,
    this.usage,
    this.raw,
  });
  final ChatMessage message;
  final String? finishReason;
  final ChatUsage? usage;
  final Map<String, Object?>? raw;
  List<ToolCall> get toolCalls => message.toolCalls;
  factory ChatResponse.text(String text, {ChatUsage? usage}) => ChatResponse(
    message: ChatMessage(role: ChatRole.assistant, content: text),
    finishReason: 'stop',
    usage: usage,
  );
  factory ChatResponse.toolCalls(
    List<ToolCall> calls, {
    String? content,
    ChatUsage? usage,
  }) => ChatResponse(
    message: ChatMessage(
      role: ChatRole.assistant,
      content: content,
      toolCalls: calls,
    ),
    finishReason: 'tool_calls',
    usage: usage,
  );
  factory ChatResponse.fromJson(Map<String, Object?> json) {
    final choices = (json['choices'] as List?) ?? const [];
    if (choices.isEmpty) {
      throw const FormatException('Provider response has no choices');
    }
    final choice = (choices.first as Map).cast<String, Object?>();
    return ChatResponse(
      message: ChatMessage.fromJson(
        (choice['message'] as Map).cast<String, Object?>(),
      ),
      finishReason: choice['finish_reason'] as String?,
      usage: (json['usage'] as Map?) == null
          ? null
          : ChatUsage.fromJson((json['usage'] as Map).cast<String, Object?>()),
      raw: json,
    );
  }
}

class ProviderException implements Exception {
  ProviderException(
    this.message, {
    this.statusCode,
    this.retryable = false,
    this.cause,
  });
  final String message;
  final int? statusCode;
  final bool retryable;
  final Object? cause;
  @override
  String toString() => 'ProviderException($statusCode): $message';
}
