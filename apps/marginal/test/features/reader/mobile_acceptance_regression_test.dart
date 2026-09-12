import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/platform_services.dart';
import 'package:marginal/app/poster.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/data/memory_repository.dart';
import 'package:marginal/features/reader/reader_page.dart';

/// 移动端验收回归：用户数据为“单换行分段”的真实 TXT 形态。
void main() {
  Future<PlatformServices> seed() async {
    final repo = MemoryRepository();
    await repo.init();
    await repo.putWork(const Work(id: 'w', title: '单换行书'));
    await repo.putChapter(
      'w',
      const Chapter(id: 'c0', workId: 'w', idx: 0, title: '第一章'),
      '第一章 标题\n这是第一段，讲了一件小事。\n这是第二段，出现了转折。\n这是第三段，收束本章。\n',
    );
    return PlatformServices(repository: repo);
  }

  Future<void> openReader(WidgetTester tester, PlatformServices services) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          services: services,
          work: const Work(id: 'w', title: '单换行书'),
          initialChapterId: 'c0',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('单换行正文按行分段，段落 sheet 只含所选段落', (tester) async {
    final services = await seed();
    await openReader(tester, services);

    await tester.tap(find.text('这是第二段，出现了转折。'));
    await tester.pumpAndSettle();
    expect(find.text('这是第一段，讲了一件小事。'), findsOneWidget,
        reason: '第一段只应存在于背景正文');
    expect(find.text('这是第二段，出现了转折。'), findsNWidgets(2),
        reason: '段落 sheet 预览应只包含所选段落（正文+预览各一次）');
  });

  testWidgets('海报内容为所选段落而非整章', (tester) async {
    final services = await seed();
    await openReader(tester, services);

    await tester.tap(find.text('这是第三段，收束本章。'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-poster')));
    await tester.pumpAndSettle();

    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is ParagraphPosterPainter,
      ),
    );
    final painter = paint.painter! as ParagraphPosterPainter;
    expect(painter.text, '这是第三段，收束本章。');
    expect(painter.text, isNot(contains('这是第一段')));
  });

  testWidgets('段落收藏只保存所选段落文本', (tester) async {
    final services = await seed();
    await openReader(tester, services);

    await tester.tap(find.text('这是第二段，出现了转折。'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-favorite')));
    await tester.pumpAndSettle();

    final saved = await services.repository.getWork('w');
    final favorites = saved!.settings['favorites.w'] as List;
    expect(favorites, hasLength(1));
    expect(favorites.single['text'], '这是第二段，出现了转折。');
  });

  testWidgets('底栏展示实时阅读进度百分比', (tester) async {
    final services = await seed();
    await openReader(tester, services);

    expect(find.textContaining('第 1/1 章 · '), findsOneWidget);
  });

  testWidgets('顶栏提供当前章收藏入口', (tester) async {
    final services = await seed();
    await openReader(tester, services);

    expect(find.byTooltip('收藏本章'), findsOneWidget);
    await tester.tap(find.byTooltip('收藏本章'));
    await tester.pumpAndSettle();
    final saved = await services.repository.getWork('w');
    expect(((saved!.settings['bookmarks.w'] as List).single as Map)['chapterId'], 'c0');
  });
}
