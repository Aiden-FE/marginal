import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/reading_prefs.dart';

void main() {
  group('字号边界', () {
    test('clampFontSize 落在 14-30，NaN 回落默认 19', () {
      expect(clampFontSize(13.9), 14);
      expect(clampFontSize(31), 30);
      expect(clampFontSize(22), 22);
      expect(clampFontSize(double.nan), defaultFontSize);
      expect(defaultFontSize, 19);
      expect(minFontSize, 14);
      expect(maxFontSize, 30);
    });
  });

  group('自动阅读速度 clamp', () {
    test('clampAutoScrollSpeed 落在 20-180', () {
      expect(clampAutoScrollSpeed(10), 20);
      expect(clampAutoScrollSpeed(999), 180);
      expect(clampAutoScrollSpeed(60.4), 60);
      expect(clampAutoScrollSpeed(double.nan), defaultAutoSpeed);
      expect(clampAutoScrollSpeed(double.infinity), defaultAutoSpeed);
      expect(defaultAutoSpeed, 60);
      expect(minAutoSpeed, 20);
      expect(maxAutoSpeed, 180);
    });
  });

  group('滚动比例', () {
    test('内容不足一屏视为整章已读', () {
      expect(scrollRatio(5, 10, 5), 1);
      expect(scrollRatio(2.5, 10, 5), 0.5);
      expect(scrollRatio(-1, 10, 5), 0);
    });

    test('scrollTopForRatio 反算并 clamp', () {
      expect(scrollTopForRatio(0.5, 10, 5), 2.5);
      expect(scrollTopForRatio(2, 10, 5), 5);
      expect(scrollTopForRatio(0.5, 5, 10), 0);
    });

    test('全书进度按章节正文长度加权', () {
      expect(
        workProgressRatio(
          chapterWeights: const [100, 300],
          chapterIndex: 1,
          chapterRatio: 0.5,
        ),
        0.625,
      );
      expect(
        workProgressRatio(
          chapterWeights: const [100, 300],
          chapterIndex: 0,
          chapterRatio: 1,
        ),
        0.25,
      );
    });

    test('全书进度可反解到目标章节与章内比例', () {
      expect(
        workProgressTarget(chapterWeights: const [100, 300], workRatio: 0.625),
        (chapterIndex: 1, chapterRatio: 0.5),
      );
      expect(
        workProgressTarget(chapterWeights: const [100, 300], workRatio: 2),
        (chapterIndex: 1, chapterRatio: 1),
      );
    });
  });

  group('阅读位置', () {
    test('settings 缺失或格式非法时返回 null', () {
      expect(loadReadingPosition({}), isNull);
      expect(loadReadingPosition({'reading': 'x'}), isNull);
      expect(
        loadReadingPosition({
          'reading': {'chapterId': 'c'},
        }),
        isNull,
      );
    });

    test('ratio 越界 clamp 到 0-1，且可往返', () {
      final settings = <String, dynamic>{};
      saveReadingPosition(settings, 'c1', 0.42);
      expect(loadReadingPosition(settings), (chapterId: 'c1', ratio: 0.42));
      saveReadingPosition(settings, 'c2', 1.5);
      expect(loadReadingPosition(settings)!.ratio, 1);
    });
  });

  group('段落收藏 toggle', () {
    test('新增置顶，再 toggle 同一段落即移除', () {
      final settings = <String, dynamic>{};
      final first = toggleParagraphFavorite(
        settings,
        'w',
        ParagraphFavorite(
          chapterId: 'c1',
          chapterTitle: '第一章',
          paraIndex: 0,
          text: 'a',
          savedAt: 1,
        ),
      );
      expect(first.added, isTrue);
      final second = toggleParagraphFavorite(
        settings,
        'w',
        ParagraphFavorite(
          chapterId: 'c2',
          chapterTitle: '第二章',
          paraIndex: 3,
          text: 'b',
          savedAt: 2,
        ),
      );
      expect(second.added, isTrue);
      expect(second.favorites.map((f) => f.paraIndex), [3, 0]);

      final removed = toggleParagraphFavorite(
        settings,
        'w',
        ParagraphFavorite(
          chapterId: 'c1',
          chapterTitle: '第一章',
          paraIndex: 0,
          text: 'a',
          savedAt: 1,
        ),
      );
      expect(removed.added, isFalse);
      expect(removed.favorites.map((f) => f.paraIndex), [3]);
      expect(listParagraphFavorites(settings, 'w'), hasLength(1));
    });

    test('同一段落索引跨章节互不影响', () {
      final settings = <String, dynamic>{};
      toggleParagraphFavorite(
        settings,
        'w',
        ParagraphFavorite(
          chapterId: 'c1',
          chapterTitle: '第一章',
          paraIndex: 0,
          text: 'a',
          savedAt: 1,
        ),
      );
      final result = toggleParagraphFavorite(
        settings,
        'w',
        ParagraphFavorite(
          chapterId: 'c2',
          chapterTitle: '第二章',
          paraIndex: 0,
          text: 'b',
          savedAt: 2,
        ),
      );
      expect(result.added, isTrue);
      expect(result.favorites, hasLength(2));
    });
  });

  group('章节书签 toggle', () {
    test('新增与移除，settings 持久化结构可回读', () {
      final settings = <String, dynamic>{};
      final added = toggleChapterBookmark(settings, 'w', 'c1', '第一章');
      expect(added.added, isTrue);
      expect(added.bookmarks.single.chapterId, 'c1');

      final removed = toggleChapterBookmark(settings, 'w', 'c1', '第一章');
      expect(removed.added, isFalse);
      expect(removed.bookmarks, isEmpty);
      expect(listChapterBookmarks(settings, 'w'), isEmpty);
    });
  });
}
