import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/repository.dart';
import '../core/types.dart';

/// 提案审批服务：类型化校验、批准快照、Revision 留痕、按 Run 回滚与过期。
class ApprovalService {
  ApprovalService(this.repository);
  final Repository repository;

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

  Future<void> reject(Proposal p) =>
      repository.updateProposal(_withStatus(p, 'rejected'));

  /// 解析提案类型；未知类型抛 [FormatException]，调用方不得将其标为 approved。
  ProposalKind kindOf(Proposal p) => parseProposalKind(p.type);

  /// 解析并校验 text_repair payload；结构非法抛 [FormatException]。
  TextRepairPayload repairPayloadOf(Proposal p) =>
      TextRepairPayload.fromJson(decodeMap(p.payload));

  Future<void> approve(Proposal p) async {
    final kind = kindOf(p); // 未知 kind 直接抛错，绝不落 approved。
    String? before;
    String? after;
    if (kind == ProposalKind.textRepair) {
      final payload = repairPayloadOf(p);
      final chapters = await repository.listChapters(p.workId);
      final chapter = chapters.firstWhere((c) => c.id == payload.chapterId);
      final beforeText = await repository.getChapterText(chapter.id);
      before = jsonEncode({'chapterId': chapter.id, 'text': beforeText});
      final afterText = _applyPatches(beforeText, payload.patches);
      after = jsonEncode({'chapterId': chapter.id, 'text': afterText});
      await repository.putChapter(
        p.workId,
        _chapterWithText(chapter, afterText),
        afterText,
      );
    }
    final revisionId = 'rev-${p.id}';
    if (before != null && after != null) {
      await repository.putRevision(
        Revision(
          id: revisionId,
          workId: p.workId,
          proposalId: p.id,
          beforeSnapshot: before,
          afterSnapshot: after,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    await repository.updateProposal(
      Proposal(
        id: p.id,
        workId: p.workId,
        runId: p.runId,
        type: p.type,
        payload: p.payload,
        status: 'approved',
        createdAt: p.createdAt,
        beforeSnapshot: before,
        afterSnapshot: after,
      ),
    );
  }

  /// 回滚某个 Run 已批准的提案：按 revision 逆序恢复 before 快照。
  /// 返回被回滚的提案 id 列表；无可回滚项时返回空表。
  Future<List<String>> rollbackRun(String runId) async {
    final rolled = <String>[];
    final revisions = <Revision>[];
    final proposals = <Proposal>[];
    // revision 按 work 维度存储，先定位该 run 的 approved 提案。
    final seenWorks = <String>{};
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
      final rev = revisions.where((r) => r.proposalId == p.id).toList();
      if (rev.isEmpty) continue; // 无快照（如 coverage/delete）不可回滚正文。
      final snapshot = decodeMap(rev.first.beforeSnapshot);
      final chapterId = snapshot['chapterId'] as String;
      final text = snapshot['text'] as String? ?? '';
      final chapters = await repository.listChapters(p.workId);
      final chapter = chapters.firstWhere(
        (c) => c.id == chapterId,
        orElse: () => throw StateError('chapter $chapterId missing'),
      );
      await repository.putChapter(
        p.workId,
        _chapterWithText(chapter, text),
        text,
      );
      await repository.updateProposal(_withStatus(p, 'rolled_back'));
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

  String _applyPatches(String text, List<Map<String, dynamic>> patches) {
    var parts = text.split(RegExp(r'\n\s*\n'));
    for (final x in patches) {
      final i = (x['paraIndex'] as num).toInt();
      if (i >= 0 && i < parts.length && parts[i].contains(x['original'])) {
        parts[i] = parts[i].replaceFirst(x['original'], x['replacement']);
      }
    }
    return '${parts.join('\n\n').trim()}\n';
  }

  Chapter _chapterWithText(Chapter c, String text) => Chapter(
    id: c.id,
    workId: c.workId,
    idx: c.idx,
    title: c.title,
    wordCount: text.runes.length,
    contentHash: sha256.convert(utf8.encode(text)).toString(),
  );
}
