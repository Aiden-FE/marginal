import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/core/agent/agent.dart';
import 'package:marginal/core/provider/provider.dart';

void main() {
  test('schema validates required, types and extras', () {
    final s = {
      'type': 'object',
      'required': ['x'],
      'properties': {
        'x': {'type': 'integer'},
      },
      'additionalProperties': false,
    };
    expect(JsonSchema.validate(s, {'x': 1}), isEmpty);
    expect(JsonSchema.validate(s, {'x': 'a', 'z': 1}), hasLength(2));
  });
  test('registry validates and catches tool errors', () async {
    final r = ToolRegistry();
    r.register(
      FunctionAgentTool(
        name: 'add',
        parameterSchema: {
          'type': 'object',
          'required': ['x'],
          'properties': {
            'x': {'type': 'integer'},
          },
        },
        handler: (a) async => {'v': a['x']},
      ),
    );
    expect((await r.execute('add', {'x': 2})).content, '{"v":2}');
    expect((await r.execute('add', {})).isError, true);
    expect((await r.execute('none', {})).isError, true);
  });
  test('runtime executes tool call loop and checkpoints', () async {
    final registry = ToolRegistry();
    registry.register(
      FunctionAgentTool(
        name: 'add',
        parameterSchema: {'type': 'object'},
        handler: (a) async => 3,
      ),
    );
    final transport = DemoTransport(
      responses: [
        ChatResponse.toolCalls([ToolCall(id: 'c', name: 'add', arguments: {})]),
        ChatResponse.text('done'),
      ],
    );
    final runtime = AgentRuntime(transport: transport, toolRegistry: registry);
    final result = await runtime.run('go');
    expect(result.status, AgentStatus.completed);
    expect(result.output, 'done');
    expect(transport.requestCount, 2);
    expect(runtime.lastCheckpoint, isNotNull);
    expect(runtime.eventLog.whereType<ToolCallCompletedEvent>(), hasLength(1));
    final cp = AgentCheckpoint.decode(runtime.lastCheckpoint!.encode());
    expect(cp.messages.length, runtime.history.length);
  });
  test('approval pauses and resumes', () async {
    final registry = ToolRegistry();
    registry.register(
      FunctionAgentTool(
        name: 'danger',
        requiresApproval: true,
        parameterSchema: {'type': 'object'},
        handler: (a) async => 'ok',
      ),
    );
    final rt = AgentRuntime(
      transport: DemoTransport(
        responses: [
          ChatResponse.toolCalls([
            ToolCall(id: 'c', name: 'danger', arguments: {}),
          ]),
          ChatResponse.text('finished'),
        ],
      ),
      toolRegistry: registry,
    );
    final future = rt.run('x');
    await Future<void>.delayed(Duration.zero);
    expect(rt.status, AgentStatus.awaitingApproval);
    await rt.approveToolCalls();
    expect((await future).status, AgentStatus.completed);
  });
  test('budget and cancellation', () async {
    final budgetRt = AgentRuntime(
      transport: DemoTransport(
        responses: [
          ChatResponse.text('x', usage: ChatUsage(completionTokens: 1)),
        ],
      ),
      budget: const AgentBudget(maxTokens: 0),
    );
    expect((await budgetRt.run('x')).status, AgentStatus.budgetExceeded);
    final rt = AgentRuntime(
      transport: DemoTransport.responder((r) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return ChatResponse.text('x');
      }),
    );
    final f = rt.run('x');
    rt.cancel();
    expect((await f).status, AgentStatus.cancelled);
  });
}
