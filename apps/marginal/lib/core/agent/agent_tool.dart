import 'dart:convert';

typedef AgentToolHandler = Future<Object?> Function(
  Map<String, Object?> arguments,
);

class AgentToolResult {
  const AgentToolResult(this.content, {this.isError = false});
  final String content;
  final bool isError;
  factory AgentToolResult.text(String value) => AgentToolResult(value);
  factory AgentToolResult.json(Object value) =>
      AgentToolResult(jsonEncode(value));
  factory AgentToolResult.error(String value) =>
      AgentToolResult(value, isError: true);
  Map<String, Object?> toJson() => {'content': content, 'is_error': isError};
}

abstract interface class AgentTool {
  String get name;
  String get description;
  Map<String, Object?> get parameterSchema;
  bool get requiresApproval => false;
  Future<AgentToolResult> invoke(Map<String, Object?> arguments);
}

class FunctionAgentTool implements AgentTool {
  const FunctionAgentTool({
    required this.name,
    this.description = '',
    required this.parameterSchema,
    required this.handler,
    this.requiresApproval = false,
  });
  @override
  final String name;
  @override
  final String description;
  @override
  final Map<String, Object?> parameterSchema;
  final AgentToolHandler handler;
  @override
  final bool requiresApproval;
  @override
  Future<AgentToolResult> invoke(Map<String, Object?> arguments) async {
    final value = await handler(arguments);
    return AgentToolResult(value == null ? 'null' : jsonEncode(value));
  }
}

class JsonSchema {
  static List<String> validate(
    Map<String, Object?> schema,
    Object? value, [
    String path = r'$',
  ]) {
    final errors = <String>[];
    final type = schema['type'];
    if (type != null && !_typeMatches(type as String, value)) {
      errors.add('$path: expected $type');
    }
    final enumValues = schema['enum'];
    if (enumValues is List && !enumValues.any((item) => _equal(item, value))) {
      errors.add('$path: value is not in enum');
    }
    if (value is Map) {
      final required = schema['required'];
      if (required is List) {
        for (final key in required) {
          if (!value.containsKey(key)) {
            errors.add('$path.$key: required');
          }
        }
      }
      final properties =
          (schema['properties'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{};
      for (final entry in properties.entries) {
        if (value.containsKey(entry.key) && entry.value is Map) {
          errors.addAll(
            validate(
              (entry.value as Map).cast<String, Object?>(),
              value[entry.key],
              '$path.${entry.key}',
            ),
          );
        }
      }
      if (schema['additionalProperties'] == false) {
        for (final key in value.keys) {
          if (!properties.containsKey(key)) {
            errors.add('$path.$key: additional property');
          }
        }
      }
    }
    if (value is List && schema['items'] is Map) {
      for (var i = 0; i < value.length; i++) {
        errors.addAll(
          validate(
            (schema['items'] as Map).cast<String, Object?>(),
            value[i],
            '$path[$i]',
          ),
        );
      }
    }
    return errors;
  }

  static bool _typeMatches(String type, Object? value) => switch (type) {
    'object' => value is Map,
    'array' => value is List,
    'string' => value is String,
    'number' => value is num,
    'integer' => value is int || value is double && value % 1 == 0,
    'boolean' => value is bool,
    'null' => value == null,
    _ => true,
  };
  static bool _equal(Object? a, Object? b) =>
      a is num && b is num ? a == b : a == b;
}
