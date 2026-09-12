import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/platform_services.dart';
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
  testWidgets('书架进入阅读器、沉浸唤栏后返回主页', (tester) async {
    final services = await seedReader();
    await tester.pumpWidget(MaterialApp(home: LibraryPage(services: services)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('交互验收书'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderPage), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.tapAt(const Offset(195, 420));
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
          onPosterEncoder: recordingPosterEncoder,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('第二段唯一文本。'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-poster')));
    await tester.pumpAndSettle();

    expect(capturedPosterTexts.single, '第二段唯一文本。');
    expect(capturedPosterTexts.single, isNot('第一段唯一文本。'));
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
          onPosterEncoder: recordingPosterEncoder,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('目录'));
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
          onPosterEncoder: recordingPosterEncoder,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('收藏段落'), findsNothing);

    // 点击屏幕中央唤醒菜单。
    await tester.tapAt(const Offset(195, 420));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    for (final label in ['收藏本章', '摘录', '目录', '设置', '自动阅读']) {
      expect(find.text(label), findsOneWidget, reason: '$label 应在唤出菜单后可见');
    }
    expect(find.text('自动阅读').hitTestable(), findsOneWidget);
  });
}
