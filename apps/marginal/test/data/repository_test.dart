import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:marginal/core/types.dart';
import 'package:marginal/data/memory_repository.dart';

void main() {
  test(
    'memory repository stores domain records, chapter text and blobs',
    () async {
      final repo = MemoryRepository();
      final work = Work(id: 'w1', title: '测试');
      await repo.putWork(work);
      await repo.putChapter(
        'w1',
        const Chapter(id: 'c1', workId: 'w1', idx: 0, title: '第一章'),
        '正文',
      );
      await repo.putAnchor(
        const Anchor(id: 'a1', workId: 'w1', chapterId: 'c1', targetId: 'i1'),
      );
      await repo.putProposal(
        const Proposal(id: 'p1', workId: 'w1', type: 'content', payload: '{}'),
      );
      await repo.putBlob(
        const BlobRec(id: 'b1', workId: 'w1', storageKey: 'k1', kind: 'text'),
        Uint8List.fromList([1, 2]),
      );
      expect((await repo.listWorks()).single.id, 'w1');
      expect(await repo.getChapterText('c1'), '正文');
      expect((await repo.listAnchors('w1')).single.id, 'a1');
      expect((await repo.listProposals('w1')).single.status, 'pending');
      expect((await repo.getBlobData('k1'))!.toList(), [1, 2]);
    },
  );
}
