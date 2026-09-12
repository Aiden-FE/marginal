import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/platform_services.dart';
import 'package:marginal/app/share.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/data/memory_repository.dart';
import 'package:marginal/features/reader/reader_page.dart';

void main() {
  final longText = List.generate(60, (i) => '段落$i：书里的一段话。').join('\n\n');

  Future<PlatformServices> seed({
    List<String> chapterTexts = const ['第一段。\n\n第二段。', '第三段。'],
    Map<String, dynamic> settings = const {},
  }) async {
    final repo = MemoryRepository();
    await repo.init();
    await repo.putWork(Work(id: 'w', title: '纸上海图', settings: settings));
    for (var i = 0; i < chapterTexts.length; i++) {
      await repo.putChapter(
        'w',
        Chapter(id: 'c$i', workId: 'w', idx: i, title: '第${i + 1}章'),
        chapterTexts[i],
      );
    }
    return PlatformServices(repository: repo);
  }

  Future<void> pumpReader(
    WidgetTester tester,
    PlatformServices services, {
    Map<String, dynamic> settings = const {},
    ShareService? shareService,
    void Function(String paragraph)? onIllustrateParagraph,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          services: services,
          work: Work(id: 'w', title: '纸上海图', settings: settings),
          initialChapterId: 'c0',
          shareService: shareService,
          onIllustrateParagraph: onIllustrateParagraph,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 收尾：让 chrome 倒计时与 SnackBar 计时器走完，避免悬挂定时器。
  Future<void> settleQuietly(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  double scrollOffset(WidgetTester tester) => tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .pixels;

  /// 立即收起 SnackBar，避免浮层挡住底栏按钮。
  Future<void> afterSnackBar(WidgetTester tester) async {
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();
  }

  testWidgets('底栏章节导航并记录当前章', (tester) async {
    final services = await seed();
    await pumpReader(tester, services);
    expect(find.textContaining('第 1/2 章'), findsOneWidget);

    await tester.tap(find.byTooltip('下一章'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2/2 章'), findsOneWidget);
    expect(find.text('第三段。'), findsOneWidget);

    final saved = await services.repository.getWork('w');
    expect((saved!.settings['reader'] as Map)['chapterId'], 'c1');
  });

  testWidgets('书签按钮 toggle 当前章并持久化', (tester) async {
    final services = await seed();
    await pumpReader(tester, services);

    await tester.tap(find.byTooltip('收藏章节'));
    await tester.pumpAndSettle();
    var saved = await services.repository.getWork('w');
    expect((saved!.settings['bookmarks.w'] as List), hasLength(1));
    expect(find.byIcon(Icons.bookmark), findsAtLeastNWidgets(1));

    await afterSnackBar(tester);
    await tester.tap(find.byTooltip('取消收藏章节'));
    await tester.pumpAndSettle();
    saved = await services.repository.getWork('w');
    expect((saved!.settings['bookmarks.w'] as List), isEmpty);
    await settleQuietly(tester);
  });

  testWidgets('设置面板：字号 slider 实时持久化到 settings', (tester) async {
    final services = await seed();
    await pumpReader(tester, services);

    await tester.tap(find.byTooltip('阅读设置'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(const Key('font-size-slider')));
    await tester.tapAt(Offset(rect.left + rect.width * 0.95, rect.center.dy));
    await tester.pump();

    final saved = await services.repository.getWork('w');
    final fontSize = (saved!.settings['reader.fontSize'] as num).toDouble();
    expect(fontSize, inInclusiveRange(26, 30));
    expect(fontSize, inInclusiveRange(14, 30));
    await settleQuietly(tester);
  });

  testWidgets('设置面板：主题三选持久化并应用夜间配色', (tester) async {
    final services = await seed();
    await pumpReader(tester, services);

    await tester.tap(find.byTooltip('阅读设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-dark')));
    await tester.pump();
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();

    final saved = await services.repository.getWork('w');
    expect(saved!.settings['reader.theme'], 'dark');
    expect(
      find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == const Color(0xFF171816),
      ),
      findsOneWidget,
      reason: '正文背景应用夜间主题色',
    );
    await settleQuietly(tester);
  });

  testWidgets('自动阅读等速滚动、再次点击停止', (tester) async {
    final services = await seed(chapterTexts: [longText]);
    await pumpReader(tester, services);

    await tester.tap(find.byTooltip('自动阅读'));
    await tester.pump(const Duration(seconds: 1));
    final moved = scrollOffset(tester);
    expect(moved, greaterThan(40), reason: '60 px/s 滚动 1 秒');

    await tester.pump(const Duration(seconds: 1));
    final movedMore = scrollOffset(tester);
    expect(movedMore, greaterThan(moved));

    await tester.tap(find.byTooltip('暂停自动阅读'));
    await tester.pump(const Duration(seconds: 1));
    expect(scrollOffset(tester), movedMore);
  });

  testWidgets('章末停留 1.5s 自动切下一章，末章自动停止', (tester) async {
    final services = await seed();
    await pumpReader(tester, services);

    await tester.tap(find.byTooltip('自动阅读'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2/2 章'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('最后一章'), findsOneWidget);
    expect(find.byTooltip('自动阅读'), findsOneWidget, reason: '停止后按钮回到播放态');
  });

  testWidgets('恢复阅读位置（chapterId + ratio）', (tester) async {
    const seedSettings = {
      'reading': {'chapterId': 'c0', 'ratio': 1.0},
    };
    final services = await seed(
      chapterTexts: [longText, '另一章。'],
      settings: seedSettings,
    );
    await pumpReader(tester, services, settings: seedSettings);

    expect(
      find.textContaining('第 1/2 章'),
      findsOneWidget,
      reason: '按 reading.chapterId 定位章节',
    );
    expect(scrollOffset(tester), greaterThan(200), reason: 'ratio=1.0 滚动到章末');
  });

  testWidgets('段落收藏：金色星标标记并写入 settings', (tester) async {
    final services = await seed();
    await pumpReader(tester, services);

    // 「第二段」位于顶栏 chrome 之下方，避免被顶栏拦截点击。
    await tester.tap(find.text('第二段。'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏段落'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star), findsOneWidget, reason: '段落尾金色星标');
    final saved = await services.repository.getWork('w');
    final favorites = saved!.settings['favorites.w'] as List;
    expect(favorites, hasLength(1));
    expect((favorites.first as Map)['paraIndex'], 1);
    await settleQuietly(tester);
  });

  testWidgets('顶栏段落收藏入口列出收藏并可跳转', (tester) async {
    final seedSettings = <String, dynamic>{
      'favorites.w': [
        {
          'chapterId': 'c1',
          'chapterTitle': '第2章',
          'paraIndex': 0,
          'text': '第三段。',
          'savedAt': 1,
        },
      ],
    };
    final services = await seed(settings: seedSettings);
    await pumpReader(tester, services, settings: seedSettings);

    await tester.tap(find.byTooltip('段落收藏'));
    await tester.pumpAndSettle();
    expect(find.text('第三段。'), findsOneWidget);

    await tester.tap(find.text('第三段。'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2/2 章'), findsOneWidget, reason: '跳转到收藏所在章节');
    await settleQuietly(tester);
  });

  testWidgets('分享文字走 ShareService，未注入 AI 插图回调时提示配置', (tester) async {
    final services = await seed();
    final share = FakeShareService();
    await pumpReader(tester, services, shareService: share);

    await tester.tap(find.text('第二段。'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享文字'));
    await tester.pumpAndSettle();
    expect(share.texts, ['第二段。']);

    await tester.tap(find.text('第二段。'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 插图'));
    await tester.pumpAndSettle();
    expect(find.textContaining('AI 供应商'), findsOneWidget);
    await settleQuietly(tester);
  });

  testWidgets('注入 onIllustrateParagraph 后回调透传段落文本', (tester) async {
    final services = await seed();
    final illustrated = <String>[];
    await pumpReader(tester, services, onIllustrateParagraph: illustrated.add);

    await tester.tap(find.text('第二段。'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 插图'));
    await tester.pumpAndSettle();
    expect(illustrated, ['第二段。']);
    await settleQuietly(tester);
  });
}
