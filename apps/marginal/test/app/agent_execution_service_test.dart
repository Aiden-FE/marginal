import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/agent_execution_service.dart';
import 'package:marginal/app/reading_tools.dart';
import 'package:marginal/core/agent/agent_runtime.dart';
import 'package:marginal/core/provider/demo_transport.dart';
import 'package:marginal/core/provider/provider_transport.dart' as provider;
import 'package:marginal/core/types.dart';
import 'package:marginal/data/memory_repository.dart';

void main() {
  test(
    'AgentExecutionSession persists run, tool call and checkpoint',
    () async {
      final repo = MemoryRepository()..init();
      await repo.putWork(const Work(id: 'w', title: '审计书'));
      await repo.putChapter(
        'w',
        const Chapter(id: 'c', workId: 'w', idx: 0, title: '第一章'),
        '正文',
      );
      const runId = 'run-audit';
      final transport = DemoTransport(
        responses: [
          provider.ChatResponse.toolCalls([
            provider.ToolCall(
              id: 'call-1',
              name: 'list_chapters',
              arguments: {},
            ),
          ]),
          provider.ChatResponse.text('完成'),
        ],
      );
      final runtime = AgentRuntime(
        transport: transport,
        toolRegistry: readingTools(repository: repo, workId: 'w', runId: runId),
      );
      final session = AgentExecutionSession(
        repository: repo,
        workId: 'w',
        runtime: runtime,
        runId: runId,
      );
      final result = await session.run('列出章节');
      expect(result.status.name, 'completed');
      final run = (await repo.listAgentRuns('w')).single;
      expect(run.status, 'completed');
      expect(run.lastCheckpoint, isNotEmpty);
      final call = (await repo.listToolCalls(runId)).single;
      expect(call.toolName, 'list_chapters');
      expect(call.schemaVersion, 1);
      expect(call.risk, 'read');
      expect(call.status, 'completed');
    },
  );
}
