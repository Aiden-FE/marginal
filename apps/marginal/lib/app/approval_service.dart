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

  Future<void> reject(Proposal p) async {
    if (p.status != 'pending') {
      throw StateError('proposal ${p.id} is not pending');
    }
    await repository.updateProposal(_withStatus(p, 'rejected'));
  }

  /// 解析提案类型；未知类型抛 [FormatException]，调用方不得将其标为 approved。
  ProposalKind kindOf(Proposal p) => parseProposalKind(p.type);

  /// 解析并校验 text_repair payload；结构非法抛 [FormatException]。
  TextRepairPayload repairPayloadOf(Proposal p) =>
      TextRepairPayload.fromJson(decodeMap(p.payload));

  Future<void> approve(Proposal p) async {
    if (p.status != 'pending') {
      throw StateError('proposal ${p.id} is not pending');
    }
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
    } else if (kind == ProposalKind.entityCanon) {
      final payload = EntityCanonPayload.fromJson(decodeMap(p.payload));
      final cards = await repository.listEntityCards(p.workId);
      final card = cards.firstWhere(
        (item) => item.id == payload.entityCardId,
        orElse: () =>
            throw StateError('entity ${payload.entityCardId} missing'),
      );
      before = jsonEncode({
        'kind': 'entity_canon',
        'entityCard': card.toJson(),
      });
      final updated = EntityCard(
        id: card.id,
        workId: card.workId,
        name: card.name,
        kind: card.kind,
        aliases: card.aliases,
        attributes: card.attributes,
        status: payload.status,
        portraitBlobId: card.portraitBlobId,
        createdAt: card.createdAt,
      );
      await repository.putEntityCard(updated);
      after = jsonEncode({
        'kind': 'entity_canon',
        'entityCard': updated.toJson(),
      });
    } else if (kind == ProposalKind.illustrationAccept) {
      final payload = IllustrationAcceptPayload.fromJson(decodeMap(p.payload));
      final illustrations = await repository.listIllustrations(p.workId);
      final illustration = illustrations.firstWhere(
        (item) => item.id == payload.illustrationId,
        orElse: () =>
            throw StateError('illustration ${payload.illustrationId} missing'),
      );
      before = jsonEncode({
        'kind': 'illustration_accept',
        'illustration': illustration.toJson(),
      });
      final updated = Illustration(
        id: illustration.id,
        workId: illustration.workId,
        prompt: illustration.prompt,
        providerId: illustration.providerId,
        model: illustration.model,
        blobId: illustration.blobId,
        chapterId: illustration.chapterId,
        paraIndex: illustration.paraIndex,
        status: 'accepted',
        entityCardIds: illustration.entityCardIds,
        createdAt: illustration.createdAt,
      );
      await repository.putIllustration(updated);
      after = jsonEncode({
        'kind': 'illustration_accept',
        'illustration': updated.toJson(),
      });
    } else if (kind == ProposalKind.chapterSplit) {
      final payload = ChapterSplitPayload.fromJson(decodeMap(p.payload));
      final current = await repository.listChapters(p.workId);
      final beforeEntries = <Map<String, dynamic>>[];
      for (final chapter in current) {
        beforeEntries.add({
          'id': chapter.id,
          'idx': chapter.idx,
          'title': chapter.title,
          'text': await repository.getChapterText(chapter.id),
        });
      }
      before = jsonEncode({'kind': 'chapter_split', 'chapters': beforeEntries});
      final source = current.firstWhere(
        (chapter) => chapter.id == payload.sourceChapterId,
        orElse: () =>
            throw StateError('chapter ${payload.sourceChapterId} missing'),
      );
      final replacement = <MapEntry<Chapter, String>>[];
      for (var i = 0; i < payload.chapters.length; i++) {
        final entry = payload.chapters[i];
        final text = entry['text'] as String;
        replacement.add(
          MapEntry(
            Chapter(
              id: 'chapter-${p.id}-$i',
              workId: p.workId,
              idx: source.idx + i,
              title: entry['title'] as String,
              wordCount: text.runes.length,
              contentHash: sha256.convert(utf8.encode(text)).toString(),
            ),
            text,
          ),
        );
      }
      final merged = <MapEntry<Chapter, String>>[];
      for (final chapter in current) {
        if (chapter.id == source.id) {
          merged.addAll(replacement);
        } else if (chapter.idx > source.idx) {
          merged.add(
            MapEntry(
              Chapter(
                id: chapter.id,
                workId: chapter.workId,
                idx: chapter.idx + replacement.length - 1,
                title: chapter.title,
                wordCount: chapter.wordCount,
                contentHash: chapter.contentHash,
              ),
              await repository.getChapterText(chapter.id),
            ),
          );
        } else {
          merged.add(
            MapEntry(chapter, await repository.getChapterText(chapter.id)),
          );
        }
      }
      await repository.replaceChapters(p.workId, merged);
      after = jsonEncode({
        'kind': 'chapter_split',
        'chapters': [
          for (final entry in merged)
            {
              'id': entry.key.id,
              'idx': entry.key.idx,
              'title': entry.key.title,
              'text': entry.value,
            },
        ],
      });
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
      if (snapshot['kind'] == 'entity_canon') {
        final raw = Map<String, dynamic>.from(snapshot['entityCard'] as Map);
        await repository.putEntityCard(EntityCard.fromJson(raw));
      } else if (snapshot['kind'] == 'illustration_accept') {
        final raw = Map<String, dynamic>.from(snapshot['illustration'] as Map);
        await repository.putIllustration(Illustration.fromJson(raw));
      } else if (snapshot['kind'] == 'chapter_split') {
        final entries = (snapshot['chapters'] as List).cast<Map>();
        await repository.replaceChapters(p.workId, [
          for (final raw in entries)
            MapEntry(
              Chapter(
                id: raw['id'] as String,
                workId: p.workId,
                idx: (raw['idx'] as num).toInt(),
                title: raw['title'] as String,
                wordCount: (raw['text'] as String).runes.length,
                contentHash: sha256
                    .convert(utf8.encode(raw['text'] as String))
                    .toString(),
              ),
              raw['text'] as String,
            ),
        ]);
      } else {
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
      }
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
      if (i < 0 || i >= parts.length) {
        throw StateError('paragraph $i does not exist');
      }
      final original = x['original'] as String;
      if (!parts[i].contains(original)) {
        throw StateError('original text not found in paragraph $i');
      }
      parts[i] = parts[i].replaceFirst(original, x['replacement'] as String);
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
