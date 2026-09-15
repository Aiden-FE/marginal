import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/ai/ai_services.dart';
import 'package:marginal/app/platform_services.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/features/entities/entities_page.dart';

import 'fake_repository.dart';
import 'fake_services.dart';

const _work = Work(id: 'w', title: '琅琊榜');

Future<PlatformServices> seed({
  List<EntityCard> cards = const [],
  String chapterText = '林殊走进金殿。\n\n他抚摸着长剑。',
}) async {
  final repo = FakeRepository();
  await repo.init();
  await repo.putWork(_work);
  await repo.putChapter(
    'w',
    const Chapter(id: 'c1', workId: 'w', idx: 0, title: '第一章'),
    chapterText,
  );
  await repo.putChapter(
    'w',
    const Chapter(id: 'c2', workId: 'w', idx: 1, title: '第二章'),
    '第二章节选。',
  );
  for (final c in cards) {
    await repo.putEntityCard(c);
  }
  return PlatformServices(repository: repo);
}

Widget wrap(PlatformServices services, EntityExtractionService? extraction) =>
    MaterialApp(
      home: EntitiesPage(
        services: services,
        work: _work,
        extractionService: extraction,
      ),
    );

void main() {
  testWidgets('提取：同名同 kind 合并 aliases/attributes 而非重复插入', (tester) async {
    final services = await seed(
      cards: const [
        EntityCard(
          id: 'e1',
          workId: 'w',
          name: '林殊',
          kind: EntityKind.character,
          aliases: ['小殊'],
          attributes: {'身份': '麒麟才子'},
        ),
      ],
    );
    final extraction = FakeExtractionService([
      const ExtractedEntity(
        kind: EntityKind.character,
        name: '林殊',
        aliases: ['梅长苏', '小殊'],
        attributes: {'身份': '江左梅郎', '佩剑': '长剑'},
      ),
      const ExtractedEntity(kind: EntityKind.scene, name: '金殿'),
    ]);
    await tester.pumpWidget(wrap(services, extraction));
    await tester.pump();
    expect(find.text('林殊'), findsOneWidget);

    await tester.tap(find.text('提取实体'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final repo = services.repository;
    final cards = await repo.listEntityCards('w');
    final linShu = cards
        .where((c) => c.name == '林殊' && c.kind == EntityKind.character)
        .toList();
    expect(linShu, hasLength(1));
    expect(linShu.single.id, 'e1');
    expect(linShu.single.aliases, containsAll(['小殊', '梅长苏']));
    expect(linShu.single.attributes['身份'], '江左梅郎');
    expect(linShu.single.attributes['佩剑'], '长剑');
    expect(cards.where((c) => c.name == '金殿'), hasLength(1));
    expect(cards.where((c) => c.name == '金殿').single.status, 'draft');
    expect(extraction.lastChapterId, 'c1');
  });

  testWidgets('详情 sheet：设为正典 / 退回草稿 状态切换', (tester) async {
    final services = await seed(
      cards: const [
        EntityCard(
          id: 'e1',
          workId: 'w',
          name: '林殊',
          kind: EntityKind.character,
        ),
      ],
    );
    await tester.pumpWidget(wrap(services, null));
    await tester.pump();
    expect(find.text('还没有实体卡'), findsNothing);

    await tester.tap(find.text('林殊'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设为正典'));
    await tester.pumpAndSettle();
    expect(find.text('设为正典？'), findsOneWidget);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(
      (await services.repository.listEntityCards('w')).single.isCanon,
      isTrue,
    );

    await tester.tap(find.text('退回草稿'));
    await tester.pumpAndSettle();
    expect(find.text('退回草稿？'), findsOneWidget);
    await tester.tap(find.text('确认'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      (await services.repository.listEntityCards('w')).single.status,
      'draft',
    );
  });

  testWidgets('详情 sheet：删除需确认', (tester) async {
    final services = await seed(
      cards: const [
        EntityCard(
          id: 'e1',
          workId: 'w',
          name: '林殊',
          kind: EntityKind.character,
        ),
      ],
    );
    await tester.pumpWidget(wrap(services, null));
    await tester.pump();
    await tester.tap(find.text('林殊'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除实体卡'));
    await tester.pumpAndSettle();
    // 取消时不删除
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await services.repository.listEntityCards('w'), hasLength(1));
    // 确认后删除
    await tester.tap(find.text('删除实体卡'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(await services.repository.listEntityCards('w'), isEmpty);
  });

  testWidgets('筛选 chips：正典只显示 canon 卡', (tester) async {
    final services = await seed(
      cards: const [
        EntityCard(
          id: 'e1',
          workId: 'w',
          name: '林殊',
          kind: EntityKind.character,
          status: 'canon',
        ),
        EntityCard(id: 'e2', workId: 'w', name: '金殿', kind: EntityKind.scene),
      ],
    );
    await tester.pumpWidget(wrap(services, null));
    await tester.pump();
    expect(find.text('林殊'), findsOneWidget);
    expect(find.text('金殿'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '正典'));
    await tester.pump();
    expect(find.text('林殊'), findsOneWidget);
    expect(find.text('金殿'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, '场景'));
    await tester.pump();
    expect(find.text('林殊'), findsNothing);
    expect(find.text('金殿'), findsOneWidget);
  });

  testWidgets('未配置供应商时点击提取给出提示', (tester) async {
    final services = await seed();
    await tester.pumpWidget(wrap(services, null));
    await tester.pump();
    await tester.tap(find.text('提取实体'));
    await tester.pump();
    expect(find.text('请先在设置中配置供应商'), findsOneWidget);
  });

  test('mergeExtracted：空白卡新建草稿', () {
    final card = mergeExtracted(
      null,
      const ExtractedEntity(
        kind: EntityKind.item,
        name: '长剑',
        aliases: ['林殊的剑', ' '],
        attributes: {'材质': '玄铁', ' ': '忽略'},
      ),
      'w',
    );
    expect(card.status, 'draft');
    expect(card.aliases, ['林殊的剑']);
    expect(card.attributes, {'材质': '玄铁'});
  });
}
