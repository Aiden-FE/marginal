import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/core/agent/agent.dart';
import 'package:marginal/core/provider/provider.dart';

class _JsonActionTransport implements ProviderTransport {
  _JsonActionTransport(this._responses);
  final List<ChatResponse> _responses;
  final requests = <ChatRequest>[];
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
    supportsTools: false,
    jsonActionFallback: true,
  );
  @override
  Future<ChatResponse> complete(ChatRequest request) async {
    requests.add(request);
    return _responses.removeAt(0);
  }
}

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
  test('json action fallback triggers approval and completes', () async {
    final registry = ToolRegistry();
    registry.register(
      FunctionAgentTool(
        name: 'danger',
        risk: AgentToolRisk.write,
        parameterSchema: {'type': 'object'},
        handler: (a) async => 'ok',
      ),
    );
    final transport = _JsonActionTransport([
      ChatResponse.text('{"tool":"danger","arguments":{}}'),
      ChatResponse.text('finished'),
    ]);
    final rt = AgentRuntime(
      transport: transport,
      toolRegistry: registry,
      systemPrompt: 'Use tools.',
    );
    final future = rt.run('x');
    await Future<void>.delayed(Duration.zero);
    expect(transport.requests.single.tools, isEmpty);
    expect(rt.status, AgentStatus.awaitingApproval);
    await rt.approveToolCalls();
    expect((await future).status, AgentStatus.completed);
    expect((await future).output, 'finished');
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
  test(
    'checkpoint resume restores approval gate and pending tool call',
    () async {
      final registry = ToolRegistry();
      var executions = 0;
      registry.register(
        FunctionAgentTool(
          name: 'danger',
          risk: AgentToolRisk.write,
          parameterSchema: {'type': 'object'},
          handler: (_) async {
            executions++;
            return 'ok';
          },
        ),
      );
      final original = AgentRuntime(
        transport: DemoTransport(
          responses: [
            ChatResponse.toolCalls([
              ToolCall(id: 'c', name: 'danger', arguments: {}),
            ]),
          ],
        ),
        toolRegistry: registry,
      );
      final running = original.run('x', runId: 'stable-run');
      await Future<void>.delayed(Duration.zero);
      expect(original.status, AgentStatus.awaitingApproval);
      final checkpoint = original.lastCheckpoint!;
      original.cancel();
      await running;

      final restored = AgentRuntime(
        transport: DemoTransport(responses: [ChatResponse.text('done')]),
        toolRegistry: registry,
      );
      final resumed = restored.resumeCheckpoint(checkpoint);
      await Future<void>.delayed(Duration.zero);
      expect(restored.status, AgentStatus.awaitingApproval);
      await restored.approveToolCalls();
      final result = await resumed;
      expect(result.runId, 'stable-run');
      expect(result.status, AgentStatus.completed);
      expect(executions, 1);
    },
  );

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
