import '../core/repository.dart';
import '../core/types.dart';

class RepairQueue {
  RepairQueue(this.repository);
  final Repository repository;

  Future<RepairJob?> claimNext(String workId, {required int now}) async {
    return repository.runInTransaction(() async {
      final jobs = await repository.listRepairJobs(workId);
      final eligible =
          jobs
              .where((job) => job.status == 'queued' && job.nextRetryAt <= now)
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (eligible.isEmpty) return null;
      final claimed = eligible.first.copyWith(
        status: 'running',
        attempts: eligible.first.attempts + 1,
        updatedAt: now,
        error: '',
      );
      await repository.putRepairJob(claimed);
      return claimed;
    });
  }

  Future<RepairJob?> processNext(
    String workId, {
    required int now,
    required Future<String?> Function(RepairJob job) execute,
  }) async {
    final job = await claimNext(workId, now: now);
    if (job == null) return null;
    try {
      if (job.proposalId.isNotEmpty) {
        final proposals = await repository.listProposals(workId);
        if (proposals.any((proposal) => proposal.id == job.proposalId)) {
          final awaiting = job.copyWith(
            status: 'awaiting_approval',
            updatedAt: now,
          );
          await repository.putRepairJob(awaiting);
          return awaiting;
        }
      }
      final proposalId = await execute(job);
      if (proposalId == null || proposalId.isEmpty) {
        throw StateError('repair job did not create a proposal');
      }
      final awaiting = job.copyWith(
        proposalId: proposalId,
        status: 'awaiting_approval',
        updatedAt: now,
      );
      await repository.putRepairJob(awaiting);
      return awaiting;
    } catch (error) {
      await fail(job, error, now);
      return (await repository.listRepairJobs(workId))
          .firstWhere((item) => item.id == job.id);
    }
  }

  Future<void> markAwaitingApproval(
    RepairJob job,
    String proposalId,
    int now,
  ) => repository.putRepairJob(
    job.copyWith(
      proposalId: proposalId,
      status: 'awaiting_approval',
      updatedAt: now,
    ),
  );

  Future<void> markApplied(RepairJob job, int now) => repository.putRepairJob(
    job.copyWith(status: 'applied', updatedAt: now, error: ''),
  );

  Future<void> fail(
    RepairJob job,
    Object error,
    int now, {
    int maxAttempts = 3,
  }) => repository.putRepairJob(
    job.copyWith(
      status: job.attempts >= maxAttempts ? 'failed' : 'queued',
      nextRetryAt: job.attempts >= maxAttempts
          ? 0
          : now + _backoffMillis(job.attempts),
      updatedAt: now,
      error: '$error',
    ),
  );

  Future<int> recoverInterrupted(String workId, {required int now}) async {
    var recovered = 0;
    for (final job in await repository.listRepairJobs(workId)) {
      if (job.status != 'running') continue;
      await repository.putRepairJob(
        job.copyWith(
          status: 'queued',
          nextRetryAt: now,
          updatedAt: now,
          error: '应用重启后恢复',
        ),
      );
      recovered++;
    }
    return recovered;
  }

  int _backoffMillis(int attempts) => switch (attempts) {
    <= 1 => 1000,
    2 => 5000,
    _ => 30000,
  };
}
