import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/platform_services.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/data/memory_repository.dart';
import 'package:marginal/features/reader/reader_page.dart';

/// 移动端验收回归：用户数据为“单换行分段”的真实 TXT 形态。
final capturedPosterTexts = <String>[];

Future<Uint8List> recordingPosterEncoder({
  required String workTitle,
  required String chapterTitle,
  required String text,
  double pixelRatio = 3,
}) async {
  capturedPosterTexts.add(text);
  return Uint8List.fromList(const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);
}

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

  Future<void> openReader(
    WidgetTester tester,
    PlatformServices services,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          services: services,
          work: const Work(id: 'w', title: '单换行书'),
          initialChapterId: 'c0',
          onPosterEncoder: recordingPosterEncoder,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('单换行正文按行分段，段落 sheet 只含所选段落', (tester) async {
    final services = await seed();
    await openReader(tester, services);

    await tester.longPress(find.text('这是第二段，出现了转折。'));
    await tester.pumpAndSettle();
    expect(find.text('这是第一段，讲了一件小事。'), findsOneWidget, reason: '第一段只应存在于背景正文');
    expect(
      find.text('这是第二段，出现了转折。'),
      findsNWidgets(2),
      reason: '段落 sheet 预览应只包含所选段落（正文+预览各一次）',
    );
  });

  testWidgets('海报内容为所选段落而非整章', (tester) async {
    final services = await seed();
    await openReader(tester, services);

    await tester.longPress(find.text('这是第三段，收束本章。'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-poster')));
    await tester.pumpAndSettle();

    expect(capturedPosterTexts.single, '这是第三段，收束本章。');
    expect(capturedPosterTexts.single, isNot(contains('这是第一段')));
  });

  testWidgets('段落收藏只保存所选段落文本', (tester) async {
    final services = await seed();
    await openReader(tester, services);

    await tester.longPress(find.text('这是第二段，出现了转折。'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-favorite')));
    await tester.pumpAndSettle();

    final saved = await services.repository.getWork('w');
    final favorites = saved!.settings['favorites.w'] as List;
    expect(favorites, hasLength(1));
    expect(favorites.single['text'], '这是第二段，出现了转折。');
  });

  testWidgets('唤出后展示实时阅读进度与章信息', (tester) async {
    final services = await seed();
    await openReader(tester, services);

    expect(find.textContaining('第 1/1 章 · '), findsOneWidget);
  });

  testWidgets('顶栏提供当前章收藏入口', (tester) async {
    final services = await seed();
    await openReader(tester, services);

    const favorite = Key('reader-chapter-favorite');
    expect(find.byKey(favorite).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(favorite));
    await tester.pumpAndSettle();
    final saved = await services.repository.getWork('w');
    expect(
      ((saved!.settings['bookmarks.w'] as List).single as Map)['chapterId'],
      'c0',
    );
  });
}
