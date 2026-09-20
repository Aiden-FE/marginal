import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/platform_services.dart';
import 'package:marginal/app/share.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/data/memory_repository.dart';
import 'package:marginal/features/reader/reader_page.dart';
import 'package:marginal/features/reader/reader_poster_sheet.dart';

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

  testWidgets('悬浮卡片章节导航并记录当前章', (tester) async {
    final services = await seed();
    await pumpReader(tester, services);
    expect(find.textContaining('第 1/2 章'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-next-chapter')));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2/2 章'), findsOneWidget);
    expect(find.text('第三段。'), findsOneWidget);

    final saved = await services.repository.getWork('w');
    expect((saved!.settings['reader'] as Map)['chapterId'], 'c1');
  });

  testWidgets('书签按钮 toggle 当前章并持久化', (tester) async {
    final services = await seed();
    await pumpReader(tester, services);

    await tester.tap(find.byKey(const Key('reader-chapter-favorite')));
    await tester.pumpAndSettle();
    var saved = await services.repository.getWork('w');
    expect((saved!.settings['bookmarks.w'] as List), hasLength(1));
    expect(find.byTooltip('已收藏'), findsOneWidget);

    await afterSnackBar(tester);
    await tester.tap(find.byKey(const Key('reader-chapter-favorite')));
    await tester.pumpAndSettle();
    saved = await services.repository.getWork('w');
    expect((saved!.settings['bookmarks.w'] as List), isEmpty);
    await settleQuietly(tester);
  });

  testWidgets('设置面板：字号 slider 实时持久化到 settings', (tester) async {
    final services = await seed();
    await pumpReader(tester, services);

    await tester.tap(find.byKey(const Key('reader-open-settings')));
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

    await tester.tap(find.byKey(const Key('reader-open-settings')));
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

    await tester.tap(find.text('自动阅读'));
    await tester.pump(const Duration(milliseconds: 16));
    final firstFrame = scrollOffset(tester);
    await tester.pump(const Duration(milliseconds: 16));
    final secondFrame = scrollOffset(tester);
    expect(secondFrame - firstFrame, lessThan(2), reason: '每帧位移应细小平滑');
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final moved = scrollOffset(tester);
    expect(moved, inInclusiveRange(45, 75), reason: '60 px/s 运行约 1 秒');

    await tester.tap(find.text('停止自动'));
    await tester.pump(const Duration(seconds: 1));
    expect(scrollOffset(tester), moved);
  });

  testWidgets('章末停留 1.5s 自动切下一章，末章自动停止', (tester) async {
    final services = await seed();
    await pumpReader(tester, services);

    await tester.tap(find.text('自动阅读'));
    for (var i = 0; i < 130; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2/2 章'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('最后一章'), findsOneWidget);
    expect(find.text('自动阅读'), findsOneWidget, reason: '停止后按钮回到播放态');
  });

  testWidgets('悬浮卡片展示按章节正文加权的全本进度', (tester) async {
    const seedSettings = {
      'reading': {'chapterId': 'c1', 'ratio': 0.5},
    };
    final services = await seed(
      chapterTexts: [longText, longText],
      settings: seedSettings,
    );
    await pumpReader(tester, services, settings: seedSettings);

    expect(find.text('75%'), findsOneWidget, reason: '第二章读到一半即全本 75%');
  });

  testWidgets('下部热区翻页到章末后点击进入下一章', (tester) async {
    final services = await seed();
    await pumpReader(tester, services);
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1/2 章'), findsOneWidget);

    await tester.tapAt(const Offset(400, 550));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('第 2/2 章'),
      findsOneWidget,
      reason: '短章章末向下翻页即跨章',
    );
  });

  testWidgets('上部热区在章首向上翻页回退到上一章章尾', (tester) async {
    const seedSettings = {
      'reading': {'chapterId': 'c1', 'ratio': 0.0},
    };
    final services = await seed(
      chapterTexts: [longText, longText],
      settings: seedSettings,
    );
    await pumpReader(tester, services, settings: seedSettings);
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2/2 章'), findsOneWidget);

    // 顶栏常显后，上翻热区从顶栏下方开始。
    await tester.tapAt(const Offset(400, 150));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('第 1/2 章'),
      findsOneWidget,
      reason: '章首向上翻页回退上一章',
    );
    expect(scrollOffset(tester), greaterThan(0), reason: '落在上一章章尾');
  });

  testWidgets('拖动全本进度只预览，松手后一次定位目标章节', (tester) async {
    final services = await seed(chapterTexts: [longText, longText]);
    await pumpReader(tester, services);
    final sliderFinder = find.byKey(const Key('reader-progress-slider'));
    var slider = tester.widget<Slider>(sliderFinder);
    slider.onChangeStart!(slider.value);
    slider.onChanged!(0.8);
    await tester.pump();

    expect(find.textContaining('第 1/2 章'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget, reason: '拖动中只更新预览值');

    slider = tester.widget<Slider>(sliderFinder);
    slider.onChangeEnd!(0.8);
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2/2 章'), findsOneWidget);
    expect(scrollOffset(tester), greaterThan(100), reason: '直接定位目标章内约 60% 位置');
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
    await tester.longPress(find.text('第二段。'));
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

    await tester.tap(find.text('摘录'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('第三段。'), findsOneWidget);

    await tester.tap(find.text('第三段。'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2/2 章'), findsOneWidget, reason: '跳转到收藏所在章节');
    await settleQuietly(tester);
  });

  testWidgets('段落动作使用复制而非分享文字，未注入 AI 时提示配置', (tester) async {
    final services = await seed();
    await pumpReader(tester, services);

    await tester.longPress(find.text('第二段。'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('分享文字'), findsNothing);
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('第二段。'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 插图'));
    await tester.pumpAndSettle();
    expect(find.textContaining('AI 供应商'), findsOneWidget);
    await settleQuietly(tester);
  });

  testWidgets('ReaderPage 未注入编码器时仍向海报 sheet 提供默认编码器', (tester) async {
    final services = await seed();
    await pumpReader(tester, services);

    await tester.longPress(find.text('第二段。'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生成分享海报'));
    await tester.pump(const Duration(milliseconds: 300));

    final sheet = tester.widget<ReaderPosterSheet>(
      find.byType(ReaderPosterSheet),
    );
    expect(sheet.encoder, isNotNull, reason: '不可用 null 覆盖默认编码器，否则会永远 loading');
  });

  testWidgets('注入 onIllustrateParagraph 后回调透传段落文本', (tester) async {
    final services = await seed();
    final illustrated = <String>[];
    await pumpReader(tester, services, onIllustrateParagraph: illustrated.add);

    await tester.longPress(find.text('第二段。'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 插图'));
    await tester.pumpAndSettle();
    expect(illustrated, ['第二段。']);
    await settleQuietly(tester);
  });

  testWidgets('窗口末尾不是真实章末时不会提前切换下一章', (tester) async {
    final veryLong = List.generate(9000, (i) => '段落$i：窗口正文。').join('\n');
    final services = await seed(chapterTexts: [veryLong, '下一章。']);
    await pumpReader(tester, services);
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('reader-scroll-view')),
        matching: find.byType(Scrollable),
      ),
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('第 1/2 章'), findsOneWidget);
  });

  testWidgets('超长单段收藏保存完整原段而非当前窗口片段', (tester) async {
    final hugeParagraph = '长' * 60000;
    final services = await seed(chapterTexts: [hugeParagraph]);
    await pumpReader(tester, services);
    await tester.longPressAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏段落'));
    await tester.pumpAndSettle();
    final saved = await services.repository.getWork('w');
    final favorites = saved!.settings['favorites.w'] as List;
    expect((favorites.single as Map)['text'], hugeParagraph);
  });
}
