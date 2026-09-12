import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/platform_services.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/features/illustrations/illustrations_page.dart';

import '../entities/fake_repository.dart';
import '../entities/fake_services.dart';

const _work = Work(id: 'w', title: '琅琊榜');
const _blobId = 'blob-1';
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Future<PlatformServices> seed({
  String? chapterText,
  List<EntityCard> cards = const [],
  List<Illustration> illustrations = const [],
  bool withBlob = true,
  List<Anchor> anchors = const [],
}) async {
  final repo = FakeRepository();
  await repo.init();
  await repo.putWork(_work);
  await repo.putChapter(
    'w',
    const Chapter(id: 'c1', workId: 'w', idx: 0, title: '第一章'),
    chapterText ?? '林殊走进金殿。\n\n他抚摸着长剑。',
  );
  for (final c in cards) {
    await repo.putEntityCard(c);
  }
  for (final i in illustrations) {
    await repo.putIllustration(i);
  }
  for (final a in anchors) {
    await repo.putAnchor(a);
  }
  if (withBlob) {
    await repo.putBlob(
      const BlobRec(
        id: _blobId,
        workId: 'w',
        storageKey: 'k1',
        kind: 'image',
        mime: 'image/png',
      ),
      _png,
    );
  }
  return PlatformServices(repository: repo);
}

Widget wrap(PlatformServices services, FakeGenerationService? generation) =>
    MaterialApp(
      home: IllustrationsPage(
        services: services,
        work: _work,
        generationService: generation,
      ),
    );

const _canonCard = EntityCard(
  id: 'e1',
  workId: 'w',
  name: '林殊',
  kind: EntityKind.character,
  status: 'canon',
  attributes: {'身份': '麒麟才子'},
);

void main() {
  testWidgets('生成章节插图：canon 提示词 + 草稿插图 + 封面位 anchor(paraIndex 0)', (
    tester,
  ) async {
    final longText = '正' * 600;
    final services = await seed(
      chapterText: longText,
      cards: const [
        _canonCard,
        EntityCard(id: 'e2', workId: 'w', name: '金殿', kind: EntityKind.scene),
      ],
    );
    final generation = FakeGenerationService(_blobId);
    await tester.pumpWidget(wrap(services, generation));
    await tester.pump();

    await tester.tap(find.text('生成章节插图'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(generation.calls, 1);
    final prompt = generation.prompts.single;
    expect(prompt, contains('林殊'));
    expect(prompt, contains('身份：麒麟才子'));
    // draft 场景卡（非 canon）不进提示词
    expect(prompt, isNot(contains('金殿')));
    // 正文摘要截断到 500 字
    expect(prompt, contains('正' * 500));
    expect(prompt.contains('正' * 501), isFalse);

    final repo = services.repository;
    final illustrations = await repo.listIllustrations('w');
    expect(illustrations, hasLength(1));
    expect(illustrations.single.status, 'draft');
    expect(illustrations.single.blobId, _blobId);
    expect(illustrations.single.chapterId, 'c1');
    expect(illustrations.single.paraIndex, isNull);
    expect(illustrations.single.prompt, prompt);

    final anchors = await repo.listAnchors('w');
    expect(anchors, hasLength(1));
    expect(anchors.single.targetType, 'illustration');
    expect(anchors.single.targetId, _blobId);
    expect(anchors.single.paraIndex, 0);
    expect(anchors.single.chapterId, 'c1');
  });

  testWidgets('生成段落插图：选段落 + 拼入 canon 人物，anchor 挂到所选段落', (tester) async {
    final services = await seed(cards: const [_canonCard]);
    final generation = FakeGenerationService(_blobId);
    await tester.pumpWidget(wrap(services, generation));
    await tester.pump();

    await tester.tap(find.text('生成段落插图'));
    await tester.pumpAndSettle();
    // 拼入 canon 人物
    await tester.tap(find.text('林殊'));
    await tester.pump();
    await tester.tap(find.text('段落 1'));
    await tester.pump();
    await tester.tap(find.text('生成插图'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(generation.calls, 1);
    expect(generation.prompts.single, contains('林殊'));
    expect(generation.prompts.single, contains('他抚摸着长剑'));

    final illustrations = await services.repository.listIllustrations('w');
    expect(illustrations.single.paraIndex, 1);
    expect(illustrations.single.entityCardIds, ['e1']);
    final anchors = await services.repository.listAnchors('w');
    expect(anchors.single.paraIndex, 1);
    expect(anchors.single.targetId, _blobId);
  });

  testWidgets('设为接受：draft → accepted', (tester) async {
    final services = await seed(
      illustrations: const [
        Illustration(
          id: 'i1',
          workId: 'w',
          prompt: 'p',
          providerId: '',
          model: '',
          blobId: _blobId,
          chapterId: 'c1',
          status: 'draft',
        ),
      ],
    );
    await tester.pumpWidget(wrap(services, null));
    await tester.pump();
    expect(find.text('草稿'), findsOneWidget);

    await tester.tap(find.text('设为接受'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      (await services.repository.listIllustrations('w')).single.status,
      'accepted',
    );
    expect(find.text('已接受'), findsOneWidget);
  });

  testWidgets('删除插图级联删除挂载的 anchor', (tester) async {
    final services = await seed(
      illustrations: const [
        Illustration(
          id: 'i1',
          workId: 'w',
          prompt: 'p',
          providerId: '',
          model: '',
          blobId: _blobId,
          chapterId: 'c1',
        ),
      ],
      anchors: const [
        Anchor(
          id: 'a1',
          workId: 'w',
          chapterId: 'c1',
          targetId: _blobId,
          targetType: 'illustration',
          paraIndex: 0,
        ),
      ],
    );
    await tester.pumpWidget(wrap(services, null));
    await tester.pump();

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(await services.repository.listIllustrations('w'), isEmpty);
    expect(await services.repository.listAnchors('w'), isEmpty);
  });

  testWidgets('未配置供应商时提示', (tester) async {
    final services = await seed();
    await tester.pumpWidget(wrap(services, null));
    await tester.pump();
    await tester.tap(find.text('生成章节插图'));
    await tester.pump();
    expect(find.text('请先在设置中配置供应商'), findsOneWidget);
  });
}
