import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/import_service.dart';
import 'package:marginal/app/platform_services.dart';
import 'package:marginal/core/repository.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/features/library/library_page.dart';

const String sampleTxt = '第一章 起点\n\n少年推开门，风雪扑面。\n\n第二章 归途\n\n雪停了，路还很长。\n';

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

/// 返回固定输入的文件源，替代 FilePicker 平台通道。
class StubFileSource implements FileSource {
  const StubFileSource(this.input);
  final PickedInput? input;

  @override
  Future<PickedInput?> pick() async => input;
}

/// 在 putWork/putChapter 上注入延迟的仓库代理，让导入遮罩可被观察。
class SlowImportRepository implements Repository {
  SlowImportRepository(this._inner);
  final Repository _inner;

  @override
  Future<List<Work>> listWorks() => _inner.listWorks();

  @override
  Future<List<Chapter>> listChapters(String workId) =>
      _inner.listChapters(workId);

  @override
  Future<void> putWork(Work value) async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await _inner.putWork(value);
  }

  @override
  Future<void> putChapter(String workId, Chapter chapter, String text) async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await _inner.putChapter(workId, chapter, text);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<PlatformServices> memoryServices() async =>
    PlatformServices.boot(persistent: false);

Future<void> seedWork(
  Repository repo, {
  required String id,
  required String title,
  Map<String, dynamic> settings = const {},
}) async {
  await repo.putWork(
    Work(id: id, title: title, settings: Map<String, dynamic>.from(settings)),
  );
}

void main() {
  group('LibraryPage', () {
    testWidgets('导入时出现遮罩与阶段文案，完成后消失并提示', (tester) async {
      final memory = await memoryServices();
      final services = PlatformServices(
        repository: SlowImportRepository(memory.repository),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryPage(
            services: services,
            fileSource: StubFileSource(
              PickedInput('风雪.txt', bytesOf(sampleTxt)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      // 半透明遮罩 + spinner + 阶段文案同时在场。
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('写入书库'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('已导入「风雪」'), findsOneWidget);
      expect(find.text('风雪'), findsOneWidget);
    });

    testWidgets('取消选择文件不触发遮罩', (tester) async {
      final services = await memoryServices();
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryPage(
            services: services,
            fileSource: const StubFileSource(null),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('分组 chips 过滤：全部 / 分组 / 未分组', (tester) async {
      final services = await memoryServices();
      await seedWork(
        services.repository,
        id: 'w-1',
        title: '群星的回响',
        settings: {'group': '科幻'},
      );
      await seedWork(services.repository, id: 'w-2', title: '旧宅笔记');
      await tester.pumpWidget(
        MaterialApp(home: LibraryPage(services: services)),
      );
      await tester.pumpAndSettle();

      expect(find.text('全部'), findsOneWidget);
      expect(find.text('科幻'), findsOneWidget);
      expect(find.text('未分组'), findsOneWidget);
      expect(find.text('群星的回响'), findsOneWidget);
      expect(find.text('旧宅笔记'), findsOneWidget);

      await tester.tap(find.text('科幻'));
      await tester.pumpAndSettle();
      expect(find.text('群星的回响'), findsOneWidget);
      expect(find.text('旧宅笔记'), findsNothing);

      await tester.tap(find.text('未分组'));
      await tester.pumpAndSettle();
      expect(find.text('旧宅笔记'), findsOneWidget);
      expect(find.text('群星的回响'), findsNothing);

      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      expect(find.text('群星的回响'), findsOneWidget);
      expect(find.text('旧宅笔记'), findsOneWidget);
    });

    testWidgets('收藏书置顶并显示星标', (tester) async {
      final services = await memoryServices();
      await seedWork(services.repository, id: 'w-1', title: '普通之书');
      await seedWork(
        services.repository,
        id: 'w-2',
        title: '心爱之书',
        settings: {'favorite': true},
      );
      await tester.pumpWidget(
        MaterialApp(home: LibraryPage(services: services)),
      );
      await tester.pumpAndSettle();

      final normalTop = tester.getTopLeft(find.text('普通之书'));
      final favoriteTop = tester.getTopLeft(find.text('心爱之书'));
      expect(favoriteTop.dy, lessThan(normalTop.dy), reason: '收藏组应置顶');
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    });

    testWidgets('卡片渲染阅读进度条与百分比，最后一章近末尾显示读完徽章', (tester) async {
      final services = await memoryServices();
      final repo = services.repository;
      await seedWork(
        repo,
        id: 'w-1',
        title: '进度之书',
        settings: {
          'reading': {'chapterId': 'c-2', 'ratio': 0.42},
        },
      );
      await repo.putChapter(
        'w-1',
        const Chapter(id: 'c-1', workId: 'w-1', idx: 0, title: '第一章'),
        '甲',
      );
      await repo.putChapter(
        'w-1',
        const Chapter(id: 'c-2', workId: 'w-1', idx: 1, title: '第二章'),
        '乙',
      );
      await seedWork(
        repo,
        id: 'w-2',
        title: '完本之书',
        settings: {
          'reading': {'chapterId': 'c-9', 'ratio': 0.99},
        },
      );
      await repo.putChapter(
        'w-2',
        const Chapter(id: 'c-9', workId: 'w-2', idx: 0, title: '终章'),
        '丙',
      );
      await tester.pumpWidget(
        MaterialApp(home: LibraryPage(services: services)),
      );
      await tester.pumpAndSettle();

      final indicators = tester.widgetList<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicators.map((w) => w.value).toList(), contains(0.42));
      expect(find.text('42%'), findsOneWidget);
      expect(find.text('99%'), findsOneWidget);
      expect(find.text('读完'), findsOneWidget);
    });

    testWidgets('长按卡片弹出 bottom sheet，可保存分组', (tester) async {
      final services = await memoryServices();
      await seedWork(services.repository, id: 'w-1', title: '待分类');
      await tester.pumpWidget(
        MaterialApp(home: LibraryPage(services: services)),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('待分类'));
      await tester.pumpAndSettle();
      expect(find.text('保存分组'), findsOneWidget);
      expect(find.text('加入收藏'), findsOneWidget);
      expect(find.text('导出 .mabk'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '散文');
      await tester.tap(find.text('保存分组'));
      await tester.pumpAndSettle();

      expect(find.text('散文'), findsOneWidget, reason: '保存后应出现分组 chip');
      expect(
        (await services.repository.getWork('w-1'))!.settings['group'],
        '散文',
      );
    });

    testWidgets('删除需确认，确认后书稿移除', (tester) async {
      final services = await memoryServices();
      await seedWork(services.repository, id: 'w-1', title: '将删之书');
      await tester.pumpWidget(
        MaterialApp(home: LibraryPage(services: services)),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('将删之书'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除书稿'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('将删之书'), findsOneWidget);

      await tester.longPress(find.text('将删之书'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await tester.pumpAndSettle();
      expect(find.text('将删之书'), findsNothing);
      expect(await services.repository.getWork('w-1'), isNull);
    });

    testWidgets('顶栏展示品牌块与衬线书库标题', (tester) async {
      final services = await memoryServices();
      await tester.pumpWidget(
        MaterialApp(home: LibraryPage(services: services)),
      );
      await tester.pumpAndSettle();
      expect(find.text('书库'), findsOneWidget);
      expect(find.text('M'), findsOneWidget);
      expect(find.text('还没有书稿。导入一本 TXT 开始阅读。'), findsOneWidget);
    });
  });
}
