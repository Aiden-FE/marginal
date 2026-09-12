import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/platform_services.dart';
import 'package:marginal/app/poster.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/data/memory_repository.dart';
import 'package:marginal/features/library/library_page.dart';
import 'package:marginal/features/reader/reader_page.dart';

Future<PlatformServices> seedReader() async {
  final repo = MemoryRepository();
  await repo.init();
  await repo.putWork(const Work(id: 'w', title: '交互验收书'));
  await repo.putChapter(
    'w',
    const Chapter(id: 'c0', workId: 'w', idx: 0, title: '第一章'),
    '第一段唯一文本。\n\n第二段唯一文本。',
  );
  await repo.putChapter(
    'w',
    const Chapter(id: 'c1', workId: 'w', idx: 1, title: '第二章'),
    '第三段唯一文本。',
  );
  return PlatformServices(repository: repo);
}

void main() {
  testWidgets('书架进入阅读器、沉浸唤栏后返回主页', (tester) async {
    final services = await seedReader();
    await tester.pumpWidget(MaterialApp(home: LibraryPage(services: services)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('交互验收书'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderPage), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.byKey(const Key('reader-chrome-wake-zone')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('reader-top-chrome')), findsOneWidget);
    expect(find.text('收藏段落'), findsNothing, reason: 'chrome 隐藏时第一击只能唤出菜单');
    expect(
      find.byKey(const Key('reader-back-home')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('reader-back-home')).hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('书库'), findsOneWidget);
    expect(find.byType(ReaderPage), findsNothing);
  });

  testWidgets('生成海报使用用户选中的第二段', (tester) async {
    final services = await seedReader();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          services: services,
          work: const Work(id: 'w', title: '交互验收书'),
          initialChapterId: 'c0',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('第二段唯一文本。'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-poster')));
    await tester.pumpAndSettle();

    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is ParagraphPosterPainter,
      ),
    );
    final painter = paint.painter! as ParagraphPosterPainter;
    expect(painter.text, '第二段唯一文本。');
    expect(painter.text, isNot('第一段唯一文本。'));
  });

  testWidgets('仅 Demo provider 时 AI 插图入口不可点击', (tester) async {
    final services = await seedReader();
    expect(
      services.providerStore.providers.where((p) => p.id != 'demo'),
      isEmpty,
    );
    await tester.pumpWidget(MaterialApp(home: LibraryPage(services: services)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('交互验收书'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二段唯一文本。'));
    await tester.pumpAndSettle();

    final tile = tester.widget<ListTile>(
      find.byKey(const Key('action-illustrate')),
    );
    expect(tile.onTap, isNull, reason: '未配置真实供应商时必须 disabled');
    expect(find.text('请先配置 AI 供应商'), findsOneWidget);
  });

  testWidgets('章节列表可收藏任意章节并持久化', (tester) async {
    final services = await seedReader();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          services: services,
          work: const Work(id: 'w', title: '交互验收书'),
          initialChapterId: 'c0',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('章节列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('toggle-chapter-bookmark-c1')));
    await tester.pumpAndSettle();

    final saved = await services.repository.getWork('w');
    final bookmarks = saved!.settings['bookmarks.w'] as List;
    expect(bookmarks.single['chapterId'], 'c1');
  });

  testWidgets('沉浸隐藏后点击正文唤出全部菜单而不打开段落 sheet', (tester) async {
    final services = await seedReader();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          services: services,
          work: const Work(id: 'w', title: '交互验收书'),
          initialChapterId: 'c0',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));

    await tester.tap(find.byKey(const Key('reader-chrome-wake-zone')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('收藏段落'), findsNothing);
    for (final tooltip in ['返回主页', '收藏章节', '自动阅读', '章节列表', '阅读设置']) {
      expect(
        find.byTooltip(tooltip).hitTestable(),
        findsOneWidget,
        reason: '$tooltip 应在唤出菜单后可见',
      );
    }
  });
}
