import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/data/memory_repository.dart';

void main() {
  test('memory transaction rolls back all writes on failure', () async {
    final repo = MemoryRepository();
    await repo.putWork(const Work(id: 'w', title: '原始'));
    await expectLater(
      repo.runInTransaction(() async {
        await repo.putWork(const Work(id: 'w', title: '临时'));
        await repo.putChapter(
          'w',
          const Chapter(id: 'c', workId: 'w', idx: 0, title: '第一章'),
          '正文',
        );
        throw StateError('fail');
      }),
      throwsStateError,
    );
    expect((await repo.getWork('w'))!.title, '原始');
    expect(await repo.listChapters('w'), isEmpty);
  });

  test('nested transaction commits as one outer unit', () async {
    final repo = MemoryRepository();
    await repo.runInTransaction(() async {
      await repo.putWork(const Work(id: 'w', title: '书稿'));
      await repo.runInTransaction(() async {
        await repo.putChapter(
          'w',
          const Chapter(id: 'c', workId: 'w', idx: 0, title: '第一章'),
          '正文',
        );
      });
    });
    expect(await repo.getWork('w'), isNotNull);
    expect(await repo.listChapters('w'), hasLength(1));
  });
}
