import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/approval_service.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/data/memory_repository.dart';

void main() {
  test('approval stores revision and rollback restores text', () async {
    final repo = MemoryRepository();
    await repo.putWork(const Work(id: 'w', title: 'w'));
    await repo.putChapter(
      'w',
      const Chapter(id: 'c', workId: 'w', idx: 0, title: 'c'),
      'old',
    );
    final p = Proposal(
      id: 'p',
      workId: 'w',
      runId: 'run',
      type: 'text_repair',
      payload: jsonEncode({
        'chapterId': 'c',
        'patches': [
          {'paraIndex': 0, 'original': 'old', 'replacement': 'new'},
        ],
      }),
    );
    await repo.putProposal(p);
    final service = ApprovalService(repo);
    await service.approve(p);
    expect(await repo.listRevisions('w'), hasLength(1));
    expect(await repo.getChapterText('c'), 'new\n');
    expect(await service.rollbackRun('run'), ['p']);
    expect(await repo.getChapterText('c'), 'old');
    expect((await repo.listProposals('w')).single.status, 'rolled_back');
  });

  test('unknown kind cannot be approved', () async {
    final repo = MemoryRepository();
    await repo.putWork(const Work(id: 'w', title: 'w'));
    final p = Proposal(id: 'p', workId: 'w', type: 'wat', payload: '{}');
    await repo.putProposal(p);
    expect(() => ApprovalService(repo).approve(p), throwsFormatException);
    expect((await repo.listProposals('w')).single.status, 'pending');
  });

  test('non-pending proposals cannot be approved or rejected again', () async {
    final repo = MemoryRepository();
    await repo.putWork(const Work(id: 'w', title: 'w'));
    final p = Proposal(
      id: 'p',
      workId: 'w',
      type: 'coverage',
      payload: '{}',
      status: 'approved',
    );
    await repo.putProposal(p);
    final service = ApprovalService(repo);
    expect(() => service.approve(p), throwsStateError);
    expect(() => service.reject(p), throwsStateError);
    expect((await repo.listProposals('w')).single.status, 'approved');
  });

  test('mismatched repair patch cannot be silently approved', () async {
    final repo = MemoryRepository();
    await repo.putWork(const Work(id: 'w', title: 'w'));
    await repo.putChapter(
      'w',
      const Chapter(id: 'c', workId: 'w', idx: 0, title: 'c'),
      'actual',
    );
    final p = Proposal(
      id: 'p',
      workId: 'w',
      type: 'text_repair',
      payload: jsonEncode({
        'chapterId': 'c',
        'patches': [
          {'paraIndex': 0, 'original': 'missing', 'replacement': 'new'},
        ],
      }),
    );
    await repo.putProposal(p);
    expect(() => ApprovalService(repo).approve(p), throwsStateError);
    expect(await repo.getChapterText('c'), 'actual');
    expect((await repo.listProposals('w')).single.status, 'pending');
  });

  test('pending proposals expire', () async {
    final repo = MemoryRepository();
    await repo.putWork(const Work(id: 'w', title: 'w'));
    final p = Proposal(
      id: 'p',
      workId: 'w',
      type: 'coverage',
      payload: '{}',
      createdAt: 1,
    );
    await repo.putProposal(p);
    expect(
      await ApprovalService(repo)
          .expirePendingProposals('w', now: 100, ttlMillis: 10),
      ['p'],
    );
    expect((await repo.listProposals('w')).single.status, 'expired');
  });
}
