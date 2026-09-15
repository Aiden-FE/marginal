import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/platform_services.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/data/memory_repository.dart';
import 'package:marginal/features/approvals/approvals_page.dart';

void main() {
  Future<PlatformServices> seed(List<Proposal> proposals) async {
    final repo = MemoryRepository();
    await repo.init();
    await repo.putWork(const Work(id: 'w', title: 'w'));
    await repo.putChapter(
      'w',
      const Chapter(id: 'c', workId: 'w', idx: 0, title: 'c'),
      'a\n\nb',
    );
    for (final p in proposals) {
      await repo.putProposal(p);
    }
    return PlatformServices(repository: repo);
  }

  testWidgets('shows structured diff for text repair proposals', (
    tester,
  ) async {
    final services = await seed([
      Proposal(
        id: 'p',
        workId: 'w',
        type: 'text_repair',
        payload: jsonEncode({
          'chapterId': 'c',
          'patches': [
            {'paraIndex': 0, 'original': 'a', 'replacement': 'x'},
          ],
        }),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: ApprovalsPage(
          services: services,
          work: const Work(id: 'w', title: 'w'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('a'), findsWidgets);
  });

  testWidgets('shows a chapter split proposal as a concrete structure diff', (
    tester,
  ) async {
    final services = await seed([
      Proposal(
        id: 'split',
        workId: 'w',
        type: 'chapter_split',
        payload: jsonEncode({
          'sourceChapterId': 'c',
          'chapters': [
            {'title': '第一段', 'text': 'a'},
            {'title': '第二段', 'text': 'b'},
          ],
        }),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: ApprovalsPage(
          services: services,
          work: const Work(id: 'w', title: 'w'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('原章节：c'), findsOneWidget);
    expect(find.text('拟拆分为 2 章'), findsOneWidget);
    expect(find.text('第 1 章：第一段'), findsOneWidget);
    expect(find.text('第 2 章：第二段'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('batch approve only applies safe text repair types', (
    tester,
  ) async {
    final services = await seed([
      Proposal(
        id: 'p1',
        workId: 'w',
        type: 'text_repair',
        payload: jsonEncode({
          'chapterId': 'c',
          'patches': [
            {'paraIndex': 0, 'original': 'a', 'replacement': 'x'},
          ],
        }),
      ),
      Proposal(
        id: 'p2',
        workId: 'w',
        type: 'delete',
        payload: jsonEncode({'chapterId': 'c'}),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: ApprovalsPage(
          services: services,
          work: const Work(id: 'w', title: 'w'),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byType(Checkbox),
      findsOneWidget,
      reason: '仅 text_repair 可批量勾选',
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('批量批准安全类型'));
    await tester.pumpAndSettle();
    expect(find.text('确认批量批准？'), findsOneWidget);
    await tester.tap(find.text('确认批准'));
    await tester.pumpAndSettle();
    final statuses = await services.repository.listProposals('w');
    expect(statuses.firstWhere((p) => p.id == 'p1').status, 'approved');
    expect(statuses.firstWhere((p) => p.id == 'p2').status, 'pending');
    expect(await services.repository.getChapterText('c'), contains('x'));
  });
}
