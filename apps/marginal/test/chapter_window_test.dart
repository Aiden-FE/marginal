import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/chapter_window.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/data/memory_repository.dart';

class RangeCountingRepository extends MemoryRepository {
  int fullReads = 0;
  int rangeReads = 0;
  int rangeUnits = 0;

  @override
  Future<String> getChapterText(String chapterId) async {
    fullReads++;
    return super.getChapterText(chapterId);
  }

  @override
  Future<String> readChapterRange(
    String chapterId,
    int start,
    int length,
  ) async {
    rangeReads++;
    final value = await super.readChapterRange(chapterId, start, length);
    rangeUnits += value.length;
    return value;
  }
}

void main() {
  test('200k chapter loads only a bounded initial window', () async {
    final repo = RangeCountingRepository();
    final text = List.generate(10000, (i) => '段落$i：长篇正文。').join('\n');
    expect(text.length, greaterThan(100000));
    await repo.putWork(const Work(id: 'w', title: '长篇'));
    await repo.putChapter(
      'w',
      Chapter(
        id: 'c',
        workId: 'w',
        idx: 0,
        title: '长章',
        wordCount: text.length,
      ),
      text,
    );
    final window = await ChapterWindowSource(repo).load('c');
    expect(window.text.length, lessThanOrEqualTo(50000));
    expect(repo.fullReads, 0);
    expect(repo.rangeUnits, lessThan(text.length ~/ 2));
  });

  test('middle restore reads a window around requested ratio', () async {
    final repo = RangeCountingRepository();
    final text = List.generate(12000, (i) => '第$i段正文。').join('\n');
    await repo.putChapter(
      'w',
      Chapter(
        id: 'c',
        workId: 'w',
        idx: 0,
        title: '长章',
        wordCount: text.length,
      ),
      text,
    );
    final window = await ChapterWindowSource(repo).load('c', ratio: .6);
    expect(window.startRatio, lessThan(.6));
    expect(window.endRatio, greaterThan(.6));
    expect(repo.fullReads, 0);
    expect(window.paragraphBase, greaterThan(0));
  });
}
