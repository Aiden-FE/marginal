import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/approval_service.dart';
import 'package:marginal/app/import_service.dart';
import 'package:marginal/app/platform_services.dart';
import 'package:marginal/app/reading_tools.dart';
import 'package:marginal/core/agent/agent_checkpoint.dart';
import 'package:marginal/core/agent/agent_events.dart';
import 'package:marginal/core/agent/agent_runtime.dart';
import 'package:marginal/core/bundle.dart';
import 'package:marginal/core/provider/demo_transport.dart';
import 'package:marginal/core/provider/provider_transport.dart' as provider;
import 'package:marginal/core/types.dart';
import 'package:marginal/features/reader/reader_page.dart';

const sampleTxt =
    '第一章 起点\n\n少年推开门，风雪扑面。\n\n本章由某站整理发布，请支持正版。\n\n他握紧了手里的剑。\n\n第二章 归途\n\n雪停了，路还很长。\n';

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

Future<PlatformServices> seeded() async {
  final services = await PlatformServices.boot(persistent: false);
  await ImportService(services.repository)
      .importTxt('风雪.txt', bytesOf(sampleTxt));
  return services;
}

Future<void> until(bool Function() condition) async {
  var guard = 0;
  while (!condition()) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (++guard > 2000) throw StateError('condition not met within 10s');
  }
}

void main() {
  // 完整链路用纯 async 测试：导入 -> 切章 -> Agent 提案 -> 批准 -> 正文更新 -> .mabk 副本迁移。
  test('vertical slice: import -> agent proposal -> approve -> updated text -> mabk copy', () async {
    final services = await seeded();
    final repo = services.repository;
    final work = (await repo.listWorks()).single;

    final chapters = await repo.listChapters(work.id);
    expect(chapters.length, 2, reason: '启发式应切出两章');
    expect(chapters[0].title, contains('第一章'));

    final repairToolCall = provider.ToolCall(
      id: 'call-1',
      name: 'propose_text_repair',
      arguments: {
        'chapterId': chapters[0].id,
        'patches': [
          {
            'paraIndex': 2,
            'original': '本章由某站整理发布，请支持正版。',
            'replacement': '',
            'reason': '广告',
          },
        ],
      },
    );
    final transport = DemoTransport(
      responses: [
        provider.ChatResponse.toolCalls([repairToolCall]),
        provider.ChatResponse.text('已提交正文修复提案，等待用户确认。'),
      ],
    );
    final runtime = AgentRuntime(
      transport: transport,
      toolRegistry: readingTools(
        repository: repo,
        workId: work.id,
        runId: 'e2e',
      ),
    );
    final events = <AgentEvent>[];
    final sub = runtime.events.listen(events.add);
    final runFuture = runtime.run('清理第一章广告');
    await until(() => runtime.status == AgentStatus.awaitingApproval);
    expect(
      events.whereType<ApprovalRequiredEvent>(),
      isNotEmpty,
      reason: '写工具必须先请求批准',
    );
    await runtime.approveToolCalls();
    final result = await runFuture;
    expect(result.status, AgentStatus.completed);
    expect(events.whereType<CheckpointSavedEvent>(), isNotEmpty);
    await sub.cancel();

    final repairRuns = await repo.listRepairRuns(work.id);
    expect(repairRuns, hasLength(1));
    expect(repairRuns.single.id, 'e2e');
    expect(repairRuns.single.kind, 'content');

    var proposals = await repo.listProposals(work.id);
    expect(proposals.single.status, 'pending');

    await ApprovalService(repo).approve(proposals.single);
    proposals = await repo.listProposals(work.id);
    expect(proposals.single.status, 'approved');
    final textAfter = await repo.getChapterText(chapters[0].id);
    expect(textAfter.contains('某站整理'), isFalse, reason: '批准后广告行应被清除');
    expect(textAfter.contains('握紧了手里的剑'), isTrue, reason: '其余正文不受影响');

    final bundleBytes = buildBundle(await repo.exportAll(work.id));
    final read = readBundle(bundleBytes);
    expect(read.data.chapters.length, 2);
    await repo.importBundle(read.data, copy: true);
    expect((await repo.listWorks()).length, 2);
    expect((await repo.listWorks()).map((w) => w.title), contains('风雪（副本）'));
  });

  // 渲染断言独立成 widget 测试，不与 Agent 异步循环混用假时钟。
  testWidgets('reader renders imported text and repaired text after approval', (
    tester,
  ) async {
    final services = await seeded();
    final repo = services.repository;
    final work = (await repo.listWorks()).single;
    final chapter = (await repo.listChapters(work.id)).first;

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          services: services,
          work: work,
          initialChapterId: chapter.id,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('风雪扑面'), findsOneWidget);
    expect(find.textContaining('某站整理'), findsOneWidget);

    final repair = Proposal(
      id: 'p-1',
      workId: work.id,
      type: 'text_repair',
      payload: jsonEncode({
        'chapterId': chapter.id,
        'patches': [
          {
            'paraIndex': 2,
            'original': '本章由某站整理发布，请支持正版。',
            'replacement': '',
            'reason': '广告',
          },
        ],
      }),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await repo.putProposal(repair);
    await ApprovalService(repo).approve(repair);

    expect((await repo.getChapterText(chapter.id)).contains('某站整理'), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    // 离线重开：仅本地数据层与阅读器，不涉及任何 transport。
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          services: services,
          work: work,
          initialChapterId: chapter.id,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('某站整理'), findsNothing);
    expect(find.textContaining('握紧了手里的剑'), findsOneWidget);
  });

  testWidgets('anchor illustration renders at its paragraph', (tester) async {
    final services = await seeded();
    final repo = services.repository;
    final work = (await repo.listWorks()).single;
    final chapter = (await repo.listChapters(work.id)).first;
    final png = Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]);
    final blob = BlobRec(
      id: 'blob-1',
      workId: work.id,
      storageKey: 'work/x/blob-1',
      kind: 'image',
      mime: 'image/png',
    );
    await repo.putBlob(blob, png);
    await repo.putAnchor(
      Anchor(
        id: 'anchor-1',
        workId: work.id,
        chapterId: chapter.id,
        targetId: 'blob-1',
        paraIndex: 0,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          services: services,
          work: work,
          initialChapterId: chapter.id,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(Image), findsOneWidget, reason: '锚点插图应插入第 0 段后');
  });

  test('agent rejects write path when user declines approval', () async {
    final services = await seeded();
    final repo = services.repository;
    final work = (await repo.listWorks()).single;
    final chapter = (await repo.listChapters(work.id)).first;
    final call = provider.ToolCall(
      id: 'c1',
      name: 'propose_text_repair',
      arguments: {
        'chapterId': chapter.id,
        'patches': [
          {
            'paraIndex': 0,
            'original': '少年',
            'replacement': '青年',
            'reason': '测试',
          },
        ],
      },
    );
    final transport = DemoTransport(
      responses: [
        provider.ChatResponse.toolCalls([call]),
        provider.ChatResponse.text('done'),
      ],
    );
    final runtime = AgentRuntime(
      transport: transport,
      toolRegistry: readingTools(repository: repo, workId: work.id, runId: 'r'),
    );
    final done = runtime.run('修一下');
    await until(() => runtime.status == AgentStatus.awaitingApproval);
    await runtime.rejectToolCalls();
    final result = await done;
    expect(result.status, AgentStatus.cancelled, reason: '拒绝写工具应终止会话');
    expect(
      await repo.listProposals(work.id),
      isEmpty,
      reason: '拒绝发生在工具执行前，不得创建提案',
    );
  });
}
