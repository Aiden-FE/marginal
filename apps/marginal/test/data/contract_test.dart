import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/core/repository.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/data/json_repository.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:marginal/data/idb_repository.dart';
import 'package:marginal/data/memory_repository.dart';

/// 契约测试：同一套语义在 memory / indexeddb / json-file 驱动上必须全绿（工单 005）。
Future<void> runContract(Repository repo) async {
  await repo.init();
  final work = Work(
    id: 'w1',
    title: '契约书',
    createdAt: 1,
    updatedAt: 1,
    settings: const {'budgetLimit': 5},
  );
  await repo.putWork(work);
  expect((await repo.listWorks()).single.title, '契约书');

  final chapter = Chapter(
    id: 'c1',
    workId: 'w1',
    idx: 0,
    title: '第一章',
    wordCount: 4,
    contentHash: 'h',
  );
  await repo.putChapter('w1', chapter, '第一段\n\n第二段');
  expect(await repo.getChapterText('c1'), '第一段\n\n第二段');
  expect(await repo.readChapterRange('c1', 0, 2), '第一');
  expect(await repo.readChapterRange('c1', 2, 3), '段\n\n');

  final blob = BlobRec(
    id: 'b1',
    workId: 'w1',
    storageKey: 'w1/b1',
    kind: 'image',
    mime: 'image/png',
  );
  await repo.putBlob(blob, Uint8List.fromList([1, 2, 3]));
  expect(await repo.getBlobData('w1/b1'), Uint8List.fromList([1, 2, 3]));

  final proposal = Proposal(
    id: 'p1',
    workId: 'w1',
    type: 'text_repair',
    payload: '{}',
    createdAt: 2,
  );
  await repo.putProposal(proposal);
  expect((await repo.listProposals('w1')).single.status, 'pending');
  await repo.updateProposal(
    Proposal(
      id: 'p1',
      workId: 'w1',
      type: 'text_repair',
      payload: '{}',
      status: 'approved',
      createdAt: 2,
    ),
  );
  expect((await repo.listProposals('w1')).single.status, 'approved');

  final anchor = Anchor(
    id: 'a1',
    workId: 'w1',
    chapterId: 'c1',
    targetId: 'b1',
    paraIndex: 0,
  );
  await repo.putAnchor(anchor);
  expect((await repo.listAnchors('w1')).single.targetId, 'b1');

  final repairRun = RepairRun(
    id: 'rr1',
    workId: 'w1',
    kind: 'content',
    providerId: 'demo',
    model: 'demo',
    startedAt: 3,
    status: 'completed',
  );
  await repo.putRepairRun(repairRun);
  expect((await repo.listRepairRuns('w1')).single.model, 'demo');
  await repo.putRepairJob(
    const RepairJob(id: 'job1', workId: 'w1', runId: 'rr1', kind: 'content'),
  );
  expect((await repo.listRepairJobs('w1')).single.status, 'queued');

  final run = AgentRun(
    id: 'r1',
    workId: 'w1',
    status: 'completed',
    startedAt: 3,
    inputTokens: 10,
    outputTokens: 5,
  );
  await repo.putAgentRun(run);
  await repo.putToolCall(
    ToolCall(
      id: 't1',
      runId: 'r1',
      toolName: 'get_chapter',
      status: 'completed',
    ),
  );
  expect((await repo.listAgentRuns('w1')).single.inputTokens, 10);
  expect((await repo.listToolCalls('r1')).single.toolName, 'get_chapter');

  final exported = await repo.exportAll('w1');
  expect(exported.chapters.single.id, 'c1');
  expect(exported.proposals.single.status, 'approved');
  expect(exported.repairRuns.single.id, 'rr1');
  expect(exported.repairJobs.single.id, 'job1');

  await repo.importBundle(
    exported,
    copy: true,
    blobData: {
      'w1/b1': Uint8List.fromList([9]),
    },
  );
  final works = await repo.listWorks();
  expect(works.length, 2, reason: 'copy 导入应生成副本书稿');
  final copyWork = works.firstWhere((w) => w.id != 'w1');
  expect(copyWork.title, contains('副本'));
  final copyChapters = await repo.listChapters(copyWork.id);
  expect(copyChapters.single.title, '第一章');
  expect(await repo.getChapterText(copyChapters.single.id), '第一段\n\n第二段');
  final copyBlob = (await repo.listBlobs(copyWork.id)).single;
  expect(await repo.getBlobData(copyBlob.storageKey), Uint8List.fromList([9]));

  await repo.deleteWork('w1');
  expect((await repo.listWorks()).map((w) => w.id), isNot(contains('w1')));
  expect(await repo.listChapters('w1'), isEmpty);
  expect(await repo.listRepairRuns('w1'), isEmpty);
  expect(await repo.listRepairJobs('w1'), isEmpty);
  expect((await repo.listRepairRuns(copyWork.id)).single.workId, copyWork.id);
}

void main() {
  test(
    'memory repository satisfies the contract',
    () => runContract(MemoryRepository()),
  );

  test('indexeddb repository satisfies the contract (memory factory)', () {
    // H5 持久化驱动：用 idbFactoryMemory 在 VM 跑同一契约。
    return runContract(IdbRepository(idbFactoryMemory));
  });

  test(
    'json-file repository satisfies the contract and survives reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp('marginal-json');
      final path = '${dir.path}/library.json';
      await runContract(JsonFileRepository(path));
      // 重新打开：全部数据（含副本与 blob 字节）应从磁盘恢复。
      final reopened = JsonFileRepository(path);
      await reopened.init();
      final works = await reopened.listWorks();
      expect(works.length, 1, reason: '仅剩副本书稿');
      expect(works.single.title, contains('副本'));
      expect(
        (await reopened.listProposals(works.single.id)).single.status,
        'approved',
      );
      expect(
        await reopened.getBlobData(
          (await reopened.listBlobs(works.single.id)).single.storageKey,
        ),
        Uint8List.fromList([9]),
      );
      await dir.delete(recursive: true);
    },
  );
}
