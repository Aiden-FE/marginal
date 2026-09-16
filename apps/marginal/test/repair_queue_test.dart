import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/repair_queue.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/data/memory_repository.dart';

void main() {
  test('queue claims in order and retries with bounded backoff', () async {
    final repo = MemoryRepository();
    await repo.putWork(const Work(id: 'w', title: 'w'));
    await repo.putRepairJob(
      const RepairJob(
        id: 'j2',
        workId: 'w',
        runId: 'r',
        kind: 'content',
        createdAt: 2,
      ),
    );
    await repo.putRepairJob(
      const RepairJob(
        id: 'j1',
        workId: 'w',
        runId: 'r',
        kind: 'content',
        createdAt: 1,
      ),
    );
    final queue = RepairQueue(repo);
    final claimed = await queue.claimNext('w', now: 10);
    expect(claimed!.id, 'j1');
    expect(claimed.attempts, 1);
    await queue.fail(claimed, StateError('network'), 10);
    final retry = (await repo.listRepairJobs('w'))
        .firstWhere((j) => j.id == 'j1');
    expect(retry.status, 'queued');
    expect(retry.nextRetryAt, 1010);
  });

  test('worker is idempotent when a proposal already exists', () async {
    final repo = MemoryRepository();
    await repo.putWork(const Work(id: 'w', title: 'w'));
    await repo.putRepairJob(
      const RepairJob(
        id: 'j',
        workId: 'w',
        runId: 'r',
        kind: 'content',
        proposalId: 'p',
      ),
    );
    await repo.putProposal(
      const Proposal(id: 'p', workId: 'w', type: 'text_repair', payload: '{}'),
    );
    var executions = 0;
    final job = await RepairQueue(repo).processNext(
      'w',
      now: 1,
      execute: (_) async {
        executions++;
        return 'new';
      },
    );
    expect(job!.status, 'awaiting_approval');
    expect(executions, 0);
  });

  test('recover requeues interrupted running jobs', () async {
    final repo = MemoryRepository();
    await repo.putWork(const Work(id: 'w', title: 'w'));
    await repo.putRepairJob(
      const RepairJob(
        id: 'j',
        workId: 'w',
        runId: 'r',
        kind: 'structure',
        status: 'running',
      ),
    );
    final recovered = await RepairQueue(repo).recoverInterrupted('w', now: 99);
    expect(recovered, 1);
    final job = (await repo.listRepairJobs('w')).single;
    expect(job.status, 'queued');
    expect(job.nextRetryAt, 99);
  });
}
