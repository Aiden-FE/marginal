import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:marginal/core/types.dart';
import 'package:marginal/data/sqlite_repository.dart';

void main() {
  late Database db;
  late SqliteRepository repo;

  setUp(() {
    db = sqlite3.openInMemory();
    repo = SqliteRepository(db);
  });

  tearDown(() async => repo.close());

  final work = Work(id: 'w1', title: 'Book', updatedAt: 2);
  final chapter = Chapter(id: 'c1', workId: 'w1', idx: 0, title: 'One');

  test('work and chapter CRUD', () async {
    await repo.init();
    await repo.putWork(work);
    expect((await repo.getWork('w1'))?.title, 'Book');
    expect((await repo.listWorks()).single.id, 'w1');
    await repo.putChapter('w1', chapter, 'hello');
    expect((await repo.listChapters('w1')).single.id, 'c1');
    expect(await repo.getChapterText('c1'), 'hello');
    await repo.replaceChapters('w1', [
      MapEntry(Chapter(id: 'c2', workId: 'w1', idx: 0, title: 'Two'), 'world'),
    ]);
    expect(await repo.getChapterText('c1'), '');
    expect((await repo.listChapters('w1')).single.id, 'c2');
    await repo.deleteWork('w1');
    expect(await repo.getWork('w1'), isNull);
    expect(await repo.listChapters('w1'), isEmpty);
  });

  test('proposal update and blob CRUD', () async {
    await repo.putWork(work);
    final proposal = Proposal(
      id: 'p1',
      workId: 'w1',
      type: 'edit',
      payload: '{}',
    );
    await repo.putProposal(proposal);
    await repo.updateProposal(
      Proposal(
        id: 'p1',
        workId: 'w1',
        type: 'edit',
        payload: '{"x":1}',
        status: 'approved',
      ),
    );
    expect((await repo.listProposals('w1')).single.status, 'approved');
    final blob = BlobRec(
      id: 'b1',
      workId: 'w1',
      storageKey: 'key',
      kind: 'image',
      byteSize: 3,
    );
    await repo.putBlob(blob, Uint8List.fromList([1, 2, 3]));
    expect(await repo.getBlobData('key'), orderedEquals([1, 2, 3]));
    expect((await repo.listBlobs('w1')).single.id, 'b1');
  });

  test('export and copy import preserve per-work data', () async {
    await repo.putWork(work);
    await repo.putChapter('w1', chapter, 'text');
    await repo.putAnchor(
      const Anchor(id: 'a1', workId: 'w1', chapterId: 'c1', targetId: 't1'),
    );
    await repo.putPrompt(const Prompt(id: 'q1', workId: 'w1', text: 'prompt'));
    await repo.putBlob(
      const BlobRec(id: 'b1', workId: 'w1', storageKey: 'blob', kind: 'file'),
      Uint8List.fromList([9]),
    );
    final bundle = await repo.exportAll('w1');
    expect(bundle.chapters.single.id, 'c1');
    await repo.importBundle(
      bundle,
      copy: true,
      blobData: {
        'blob': Uint8List.fromList([9]),
      },
    );
    final works = await repo.listWorks();
    expect(works, hasLength(2));
    final copied = works.firstWhere((w) => w.id != 'w1');
    final copiedBundle = await repo.exportAll(copied.id);
    expect(copiedBundle.chapters.single.workId, copied.id);
    expect(copiedBundle.texts.values.single, 'text');
    expect(await repo.getBlobData('blob'), orderedEquals([9]));
    await repo.wipe();
    expect(await repo.listWorks(), isEmpty);
  });
}
