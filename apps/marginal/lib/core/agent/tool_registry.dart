import '../provider/provider_transport.dart';
import 'agent_tool.dart';

class ToolRegistry {
  final Map<String, AgentTool> _tools = {};
  void register(AgentTool tool) {
    if (_tools.containsKey(tool.name)) {
      throw ArgumentError('Tool already registered: ${tool.name}');
    }
    _tools[tool.name] = tool;
  }

  AgentTool? operator [](String name) => _tools[name];
  bool contains(String name) => _tools.containsKey(name);
  bool remove(String name) => _tools.remove(name) != null;
  Iterable<String> get names => _tools.keys;
  List<ToolSpec> get specs => _tools.values
      .map(
        (t) => ToolSpec(
          name: t.name,
          description: t.description,
          parameters: t.parameterSchema,
        ),
      )
      .toList(growable: false);
  Future<AgentToolResult> execute(
    String name,
    Map<String, Object?> arguments,
  ) async {
    final tool = _tools[name];
    if (tool == null) return AgentToolResult.error('Unknown tool: $name');
    final errors = JsonSchema.validate(tool.parameterSchema, arguments);
    if (errors.isNotEmpty) {
      return AgentToolResult.error('Invalid arguments: ${errors.join('; ')}');
    }
    try {
      return await tool.invoke(arguments);
    } catch (e) {
      return AgentToolResult.error('$e');
    }
  }
}
