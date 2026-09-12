import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/platform_services.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/data/memory_repository.dart';
import 'package:marginal/features/reader/reader_page.dart';

/// 沉浸模式：点击正文切换 chrome、3.5s 自动收起、交互续期、弹层暂停收起。
void main() {
  final longText = List.generate(40, (i) => '第$i段内容。').join('\n\n');

  Future<PlatformServices> seed() async {
    final repo = MemoryRepository();
    await repo.init();
    await repo.putWork(const Work(id: 'w', title: '纸上海图'));
    await repo.putChapter(
      'w',
      const Chapter(id: 'c0', workId: 'w', idx: 0, title: '第一章'),
      longText,
    );
    return PlatformServices(repository: repo);
  }

  Future<void> pumpReader(WidgetTester tester) async {
    final services = await seed();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          services: services,
          work: const Work(id: 'w', title: '纸上海图'),
          initialChapterId: 'c0',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double chromeOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.text('纸上海图'),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      )
      .opacity;

  /// 点击两段之间的空隙（不属于段落交互区）。
  Future<void> tapGap(WidgetTester tester) async {
    final topLeft = tester.getTopLeft(find.text('第1段内容。'));
    await tester.tapAt(Offset(topLeft.dx + 4, topLeft.dy - 8));
    await tester.pumpAndSettle();
  }

  testWidgets('初始显示 chrome，点击正文收起，再点唤出', (tester) async {
    await pumpReader(tester);
    expect(chromeOpacity(tester), 1);

    await tapGap(tester);
    expect(chromeOpacity(tester), 0);

    await tapGap(tester);
    expect(chromeOpacity(tester), 1);
  });

  testWidgets('chrome 显示 3.5 秒后自动收起', (tester) async {
    await pumpReader(tester);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(chromeOpacity(tester), 0);

    await tapGap(tester);
    expect(chromeOpacity(tester), 1, reason: '手动唤出');
  });

  testWidgets('滚动等交互为 chrome 续期', (tester) async {
    await pumpReader(tester);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(chromeOpacity(tester), 1, reason: '3 秒 < 3.5 秒，交互续期');

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(chromeOpacity(tester), 0);
  });

  testWidgets('弹层打开时 chrome 暂停收起，关闭后恢复倒计时', (tester) async {
    await pumpReader(tester);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('阅读设置'), findsWidgets);

    await tester.pump(const Duration(seconds: 4));
    expect(chromeOpacity(tester), 1, reason: '弹层打开期间不收起');

    // 点击遮罩关闭弹层。
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect(chromeOpacity(tester), 0);
  });

  testWidgets('点击段落打开动作面板而不是切换 chrome', (tester) async {
    await pumpReader(tester);
    await tester.tap(find.text('第2段内容。'));
    await tester.pumpAndSettle();
    expect(find.text('收藏段落'), findsOneWidget);
    expect(chromeOpacity(tester), 1);
  });
}
