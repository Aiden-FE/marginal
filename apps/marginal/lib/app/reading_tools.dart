import 'dart:convert';

import '../core/agent/agent_tool.dart';
import '../core/agent/tool_registry.dart';
import '../core/repository.dart';
import '../core/types.dart';
import 'ids.dart';

Future<void> _ensureRepairRun(
  Repository repository,
  String workId,
  String runId, {
  required String kind,
  String providerId = '',
  String model = 'agent',
}) async {
  final existing = await repository.listRepairRuns(workId);
  if (existing.any((run) => run.id == runId)) return;
  await repository.putRepairRun(
    RepairRun(
      id: runId,
      workId: workId,
      kind: kind,
      providerId: '',
      model: 'agent',
      startedAt: DateTime.now().millisecondsSinceEpoch,
      status: 'running',
    ),
  );
}

ToolRegistry readingTools({
  required Repository repository,
  required String workId,
  required String runId,
  String providerId = '',
  String model = 'agent',
}) {
  final tools = <AgentTool>[
    FunctionAgentTool(
      name: 'list_chapters',
      description: '列出当前书稿章节',
      parameterSchema: {'type': 'object', 'additionalProperties': false},
      handler: (_) async => (await repository.listChapters(workId))
          .map(
            (c) => {
              'id': c.id,
              'idx': c.idx,
              'title': c.title,
              'wordCount': c.wordCount,
            },
          )
          .toList(),
    ),
    FunctionAgentTool(
      name: 'get_chapter',
      description: '读取章节正文',
      parameterSchema: {
        'type': 'object',
        'required': ['chapterId'],
        'properties': {
          'chapterId': {'type': 'string'},
        },
        'additionalProperties': false,
      },
      handler: (a) async {
        final c = (await repository.listChapters(workId))
            .firstWhere((x) => x.id == a['chapterId']);
        final text = await repository.getChapterText(c.id);
        return {
          'id': c.id,
          'title': c.title,
          'text': text.substring(0, text.length.clamp(0, 30000)),
        };
      },
    ),
    FunctionAgentTool(
      name: 'search_text',
      description: '搜索当前书稿正文',
      parameterSchema: {
        'type': 'object',
        'required': ['query'],
        'properties': {
          'query': {'type': 'string'},
        },
        'additionalProperties': false,
      },
      handler: (a) async {
        final q = a['query'] as String;
        final out = [];
        for (final c in await repository.listChapters(workId)) {
          final t = await repository.getChapterText(c.id);
          final at = t.indexOf(q);
          if (at >= 0) {
            out.add({
              'chapterId': c.id,
              'title': c.title,
              'snippet': t.substring(
                at.clamp(0, t.length),
                (at + 120).clamp(0, t.length),
              ),
            });
          }
        }
        return out;
      },
    ),
    FunctionAgentTool(
      name: 'propose_text_repair',
      description: '提出正文修复提案',
      risk: AgentToolRisk.write,
      parameterSchema: {
        'type': 'object',
        'required': ['chapterId', 'patches'],
        'properties': {
          'chapterId': {'type': 'string'},
          'patches': {'type': 'array'},
        },
        'additionalProperties': false,
      },
      handler: (a) async {
        await _ensureRepairRun(
          repository,
          workId,
          runId,
          kind: 'content',
          providerId: providerId,
          model: model,
        );
        final p = Proposal(
          id: newId('proposal'),
          workId: workId,
          runId: runId,
          type: 'text_repair',
          payload: jsonEncode(a),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
        await repository.putProposal(p);
        return {'proposalId': p.id, 'status': 'pending'};
      },
    ),
    FunctionAgentTool(
      name: 'propose_chapter_split',
      description: '提出章节切分提案',
      risk: AgentToolRisk.write,
      parameterSchema: {
        'type': 'object',
        'required': ['sourceChapterId', 'chapters'],
        'properties': {
          'sourceChapterId': {'type': 'string'},
          'chapters': {'type': 'array'},
        },
        'additionalProperties': false,
      },
      handler: (a) async {
        await _ensureRepairRun(
          repository,
          workId,
          runId,
          kind: 'structure',
          providerId: providerId,
          model: model,
        );
        final p = Proposal(
          id: newId('proposal'),
          workId: workId,
          runId: runId,
          type: 'chapter_split',
          payload: jsonEncode(a),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
        await repository.putProposal(p);
        return {'proposalId': p.id, 'status': 'pending'};
      },
    ),
  ];
  final registry = ToolRegistry();
  for (final tool in tools) {
    registry.register(tool);
  }
  return registry;
}
