import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:marginal/core/repository.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/data/idb_repository.dart';
import 'package:marginal/data/json_repository.dart';

/// 覆盖共享根快照的全部记录类型，并混合两本书稿防止跨稿串数据。
Future<void> seedFullFixture(Repository repo) async {
  await repo.putWork(
    const Work(
      id: 'w1',
      title: '甲',
      createdAt: 1,
      updatedAt: 2,
      settings: {'a': 1},
    ),
  );
  await repo.putWork(
    const Work(id: 'w2', title: '乙', createdAt: 3, updatedAt: 4),
  );
  await repo.putChapter(
    'w1',
    const Chapter(id: 'c1', workId: 'w1', idx: 0, title: '一', wordCount: 2),
    '甲正文',
  );
  await repo.putChapter(
    'w1',
    const Chapter(id: 'c2', workId: 'w1', idx: 1, title: '二', wordCount: 3),
    '乙正文',
  );
  await repo.putChapter(
    'w2',
    const Chapter(id: 'c3', workId: 'w2', idx: 0, title: '外'),
    '丙正文',
  );
  await repo.putAnchor(
    const Anchor(
      id: 'a1',
      workId: 'w1',
      chapterId: 'c1',
      targetId: 'b1',
      paraIndex: 2,
    ),
  );
  await repo.putPrompt(
    const Prompt(id: 'pr1', workId: 'w1', text: '提示', createdAt: 5),
  );
  await repo.putProposal(
    const Proposal(
      id: 'pp1',
      workId: 'w1',
      type: 'text_repair',
      payload: '{}',
      status: 'approved',
      createdAt: 6,
    ),
  );
  await repo.putAgentRun(
    const AgentRun(
      id: 'r1',
      workId: 'w1',
      status: 'completed',
      startedAt: 7,
      inputTokens: 3,
      outputTokens: 4,
    ),
  );
  await repo.putToolCall(
    const ToolCall(
      id: 't1',
      runId: 'r1',
      toolName: 'get_chapter',
      status: 'completed',
      startedAt: 8,
    ),
  );
  await repo.putBlob(
    const BlobRec(
      id: 'b1',
      workId: 'w1',
      storageKey: 'w1/b1',
      kind: 'image',
      mime: 'image/png',
      sha256: 'h',
      byteSize: 3,
    ),
    Uint8List.fromList([1, 2, 3]),
  );
}

Future<Directory> tempDir() =>
    Directory.systemTemp.createTemp('marginal-snapshot');

void main() {
  test('json driver restores every record kind from the shared root', () async {
    final dir = await tempDir();
    final path = '${dir.path}/library.json';
    await JsonFileRepository(path).init();
    await seedFullFixture(JsonFileRepository(path));

    final reopened = JsonFileRepository(path);
    await reopened.init();
    final works = await reopened.listWorks();
    expect(works.map((w) => w.id), unorderedEquals(['w1', 'w2']));
    final w1 = works.firstWhere((w) => w.id == 'w1');
    expect(w1.updatedAt, 2, reason: '时间戳应按字面往返，不引入 now()');
    expect(w1.settings, {'a': 1});
    expect((await reopened.listChapters('w1')).map((c) => c.id), ['c1', 'c2']);
    expect(await reopened.getChapterText('c1'), '甲正文');
    expect(await reopened.getChapterText('c3'), '丙正文', reason: '第二本书稿正文不丢');
    expect((await reopened.listAnchors('w1')).single.targetId, 'b1');
    expect((await reopened.listPrompts('w1')).single.text, '提示');
    expect((await reopened.listProposals('w1')).single.status, 'approved');
    final run = (await reopened.listAgentRuns('w1')).single;
    expect(run.inputTokens, 3);
    expect(
      (await reopened.listToolCalls(run.id)).single.toolName,
      'get_chapter',
    );
    expect(await reopened.getBlobData('w1/b1'), [1, 2, 3]);
    await dir.delete(recursive: true);
  });

  test('idb driver restores every record kind from the same root', () async {
    final factory = idbFactoryMemory;
    final first = IdbRepository(factory);
    await first.init();
    await seedFullFixture(first);

    final reopened = IdbRepository(factory);
    await reopened.init();
    expect((await reopened.listWorks()).length, 2);
    expect(await reopened.getChapterText('c3'), '丙正文');
    expect((await reopened.listAgentRuns('w1')).single.status, 'completed');
    expect((await reopened.listToolCalls('r1')).single.runId, 'r1');
    expect(await reopened.getBlobData('w1/b1'), [1, 2, 3]);
  });

  test('both drivers serialize an identical shared root', () async {
    final dir = await tempDir();
    final jsonRepo = JsonFileRepository('${dir.path}/library.json');
    await jsonRepo.init();
    await seedFullFixture(jsonRepo);
    final idbRepo = IdbRepository(idbFactoryMemory);
    await idbRepo.init();
    await seedFullFixture(idbRepo);

    expect(await idbRepo.snapshotRoot(), await jsonRepo.snapshotRoot());
    await dir.delete(recursive: true);
  });

  test('reloading a root must not re-persist partial state', () async {
    final dir = await tempDir();
    final path = '${dir.path}/library.json';
    final repo = JsonFileRepository(path);
    await repo.init();
    await seedFullFixture(repo);
    final before = await File(path).readAsString();

    await repo.init(); // 再次加载：加载期间的 wipe/put 不得触发持久化。

    expect(await File(path).readAsString(), before);
    expect((await repo.listWorks()).length, 2, reason: '重载后内存态仍完整');
    await dir.delete(recursive: true);
  });
}
