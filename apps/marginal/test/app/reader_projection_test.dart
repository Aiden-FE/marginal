import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/reader_projection.dart';
import 'package:marginal/app/reading_tools.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/data/memory_repository.dart';

class CountingRepository extends MemoryRepository {
  int blobLists = 0;
  int blobReads = 0;
  int textReads = 0;

  @override
  Future<List<BlobRec>> listBlobs(String workId) async {
    blobLists++;
    return super.listBlobs(workId);
  }

  @override
  Future<Uint8List?> getBlobData(String storageKey) async {
    blobReads++;
    return super.getBlobData(storageKey);
  }

  @override
  Future<String> getChapterText(String chapterId) async {
    textReads++;
    return super.getChapterText(chapterId);
  }
}

void main() {
  test(
    'projection loads blobs once and resolves only active anchors',
    () async {
      final repo = CountingRepository();
      const work = Work(id: 'w', title: '书');
      const chapter = Chapter(id: 'c', workId: 'w', idx: 0, title: '章');
      await repo.putWork(work);
      await repo.putChapter('w', chapter, '正文');
      await repo.putBlob(
        const BlobRec(id: 'b1', workId: 'w', storageKey: 'k1', kind: 'image'),
        Uint8List.fromList([1]),
      );
      await repo.putBlob(
        const BlobRec(id: 'b2', workId: 'w', storageKey: 'k2', kind: 'image'),
        Uint8List.fromList([2]),
      );
      await repo.putAnchor(
        const Anchor(
          id: 'a1',
          workId: 'w',
          chapterId: 'c',
          targetId: 'b1',
          paraIndex: 2,
        ),
      );
      await repo.putAnchor(
        const Anchor(
          id: 'a2',
          workId: 'w',
          chapterId: 'c',
          targetId: 'b2',
          paraIndex: 4,
          state: 'inactive',
        ),
      );
      final result = await ReaderProjectionService(repo)
          .projection('w', chapter);

      expect(result.text, '正文');
      expect(result.images.keys, contains(2));
      expect(result.images[2]!.single, orderedEquals([1]));
      expect(repo.blobLists, 1);
      expect(repo.blobReads, 1);
      expect(repo.textReads, 1);
    },
  );

  test('get_chapter reads chapter text once', () async {
    final repo = CountingRepository();
    await repo.putWork(const Work(id: 'w', title: '书'));
    await repo.putChapter(
      'w',
      const Chapter(id: 'c', workId: 'w', idx: 0, title: '章'),
      '正文',
    );
    final result = await readingTools(
      repository: repo,
      workId: 'w',
      runId: 'r',
    ).execute('get_chapter', {'chapterId': 'c'});

    expect(result.isError, isFalse);
    expect(jsonDecode(result.content)['text'], '正文');
    expect(repo.textReads, 1);
  });
}
