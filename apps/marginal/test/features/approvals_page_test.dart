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
    final statuses = await services.repository.listProposals('w');
    expect(statuses.firstWhere((p) => p.id == 'p1').status, 'approved');
    expect(statuses.firstWhere((p) => p.id == 'p2').status, 'pending');
    expect(await services.repository.getChapterText('c'), contains('x'));
  });
}
