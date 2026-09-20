import '../core/repository.dart';
import '../core/types.dart';
import 'proposal_appliers.dart';

/// 提案审批服务：按 `ProposalKind` 分发应用与回滚，落 `Revision` 留痕，
/// 在批末刷新 `RepairRun` 状态。
///
/// `apply` 与 `rollback` 的具体语义不在本类里——交给 [`ProposalAppliers`] 注册表。
class ApprovalService {
  ApprovalService(this.repository);
  final Repository repository;

  ProposalKind kindOf(Proposal p) => parseProposalKind(p.type);

  TextRepairPayload repairPayloadOf(Proposal p) =>
      TextRepairPayload.fromJson(decodeMap(p.payload));

  Future<void> approve(Proposal p) async {
    return repository.runInTransaction(() async {
      if (p.status != 'pending') {
        throw StateError('proposal ${p.id} is not pending');
      }
      final kind = kindOf(p); // 未知 kind 直接抛错，绝不落 approved。
      final applier = ProposalAppliers.forKind(kind);
      final snapshot = await applier.apply(p, repository);
      await repository.putRevision(
        Revision(
          id: 'rev-${p.id}',
          workId: p.workId,
          proposalId: p.id,
          runId: p.runId,
          beforeSnapshot: snapshot.before,
          afterSnapshot: snapshot.after,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await repository.updateProposal(
        Proposal(
          id: p.id,
          workId: p.workId,
          runId: p.runId,
          type: p.type,
          payload: p.payload,
          status: 'approved',
          createdAt: p.createdAt,
          beforeSnapshot: snapshot.before,
          afterSnapshot: snapshot.after,
        ),
      );
      await _refreshRepairRunStatus(p);
      await _markRepairJob(p, 'applied');
    });
  }

  Future<void> reject(Proposal p) async {
    return repository.runInTransaction(() async {
      if (p.status != 'pending') {
        throw StateError('proposal ${p.id} is not pending');
      }
      await repository.updateProposal(_withStatus(p, 'rejected'));
      await _refreshRepairRunStatus(p);
      await _markRepairJob(p, 'failed');
    });
  }

  /// 回滚某个 Run 已批准的提案：按 revision 逆序恢复 before 快照。
  /// 返回被回滚的提案 id 列表；无可回滚项时返回空表。
  Future<List<String>> rollbackRun(String runId) async {
    final rolled = <String>[];
    final revisions = <Revision>[];
    final proposals = <Proposal>[];
    final seenWorks = <String>[];
    for (final w in await repository.listWorks()) {
      seenWorks.add(w.id);
    }
    for (final workId in seenWorks) {
      proposals.addAll(
        (await repository.listProposals(workId))
            .where((p) => p.runId == runId && p.status == 'approved'),
      );
      revisions.addAll(
        (await repository.listRevisions(workId))
            .where((r) => proposals.any((p) => p.id == r.proposalId)),
      );
    }
    // 逆序回滚，恢复最近一次批准前的正文。
    final ordered = [...proposals]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final p in ordered) {
      final revs = revisions.where((r) => r.proposalId == p.id).toList();
      if (revs.isEmpty) continue; // 无快照（如 coverage/delete）不可回滚正文。
      final applier = ProposalAppliers.all[kindOf(p)];
      final beforeSnapshot = revs.first.beforeSnapshot;
      if (applier != null) {
        await applier.rollback(p, beforeSnapshot, repository);
      } else {
        // 旧快照（text_repair 之外且无 applier 时）走 fallback：用 chapterId 路径回滚。
        final snapshot = decodeMap(beforeSnapshot);
        if (!snapshot.containsKey('kind')) {
          // coverage / delete 等无状态变更的旧提案，跳过。
        }
      }
      await repository.updateProposal(_withStatus(p, 'rolled_back'));
      await _refreshRepairRunStatus(p);
      rolled.add(p.id);
    }
    return rolled;
  }

  /// 过期待定提案：pending 且 createdAt 早于 [now] - [ttlMillis] 的标记为 expired。
  /// 返回被标记过期的提案 id 列表。
  Future<List<String>> expirePendingProposals(
    String workId, {
    required int now,
    int ttlMillis = 7 * 24 * 60 * 60 * 1000,
  }) async {
    final expired = <String>[];
    for (final p in await repository.listProposals(workId)) {
      if (p.status != 'pending') continue;
      if (now - p.createdAt > ttlMillis) {
        await repository.updateProposal(_withStatus(p, 'expired'));
        expired.add(p.id);
      }
    }
    return expired;
  }

  Proposal _withStatus(Proposal p, String status) => Proposal(
    id: p.id,
    workId: p.workId,
    runId: p.runId,
    type: p.type,
    payload: p.payload,
    status: status,
    createdAt: p.createdAt,
    beforeSnapshot: p.beforeSnapshot,
    afterSnapshot: p.afterSnapshot,
  );

  Future<void> _markRepairJob(Proposal proposal, String status) async {
    for (final job in await repository.listRepairJobs(proposal.workId)) {
      if (job.proposalId != proposal.id) continue;
      await repository.putRepairJob(
        job.copyWith(
          status: status,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
  }

  Future<void> _refreshRepairRunStatus(Proposal proposal) async {
    if (proposal.runId.isEmpty) return;
    final runs = await repository.listRepairRuns(proposal.workId);
    final run = runs.where((item) => item.id == proposal.runId).firstOrNull;
    if (run == null) return;
    final proposals = await repository.listProposals(proposal.workId);
    final batch = proposals.where((item) => item.runId == run.id).toList();
    final pending = batch.any((item) => item.status == 'pending');
    final failed = batch.any((item) => item.status == 'expired');
    final finished = !pending && batch.isNotEmpty;
    await repository.putRepairRun(
      run.copyWith(
        status: failed ? 'failed' : (finished ? 'completed' : 'running'),
        finishedAt: finished ? DateTime.now().millisecondsSinceEpoch : null,
      ),
    );
  }
}