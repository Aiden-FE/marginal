import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/repository.dart';
import '../core/types.dart';

/// 一次 `apply` 留下的可回滚快照。
///
/// `before` 与 `after` 都是 JSON 字符串，落入 `Revision.beforeSnapshot` / `afterSnapshot`。
/// `apply` 与 `rollback` 必须保持互逆，调用方在事务里调用。
class ProposalSnapshot {
  const ProposalSnapshot({required this.before, required this.after});
  final String before;
  final String after;
}

/// 抽象 ProposalApplier —— 一类 `ProposalKind` 的应用与回滚。
///
/// 每种 kind 一个 applier，`ApprovalService` 通过注册表按 `kind` 分发。
/// `apply` 在事务内执行：读取当前状态 → 计算 `ProposalSnapshot` → 写入新状态。
/// `rollback` 是 `apply` 的逆：从 `before` 快照恢复旧状态。
abstract class ProposalApplier {
  ProposalKind get kind;

  /// 应用提案：返回 (before, after) 快照并把 after 状态写入 repo。
  Future<ProposalSnapshot> apply(Proposal p, Repository repo);

  /// 从 `before` 快照回滚。实现方负责把 `before` 还原到 repo。
  Future<void> rollback(Proposal p, String beforeSnapshot, Repository repo);
}

class TextRepairApplier implements ProposalApplier {
  const TextRepairApplier();
  @override
  ProposalKind get kind => ProposalKind.textRepair;

  @override
  Future<ProposalSnapshot> apply(Proposal p, Repository repo) async {
    final payload = TextRepairPayload.fromJson(decodeMap(p.payload));
    final chapters = await repo.listChapters(p.workId);
    final chapter = chapters.firstWhere((c) => c.id == payload.chapterId);
    final beforeText = await repo.getChapterText(chapter.id);
    final afterText = _applyPatches(beforeText, payload.patches);
    await repo.putChapter(
      p.workId,
      _chapterWithText(chapter, afterText),
      afterText,
    );
    return ProposalSnapshot(
      before: jsonEncode({'chapterId': chapter.id, 'text': beforeText}),
      after: jsonEncode({'chapterId': chapter.id, 'text': afterText}),
    );
  }

  @override
  Future<void> rollback(
    Proposal p,
    String beforeSnapshot,
    Repository repo,
  ) async {
    final snapshot = decodeMap(beforeSnapshot);
    final chapterId = snapshot['chapterId'] as String;
    final text = snapshot['text'] as String? ?? '';
    final chapters = await repo.listChapters(p.workId);
    final chapter = chapters.firstWhere(
      (c) => c.id == chapterId,
      orElse: () => throw StateError('chapter $chapterId missing'),
    );
    await repo.putChapter(
      p.workId,
      _chapterWithText(chapter, text),
      text,
    );
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

class EntityCanonApplier implements ProposalApplier {
  const EntityCanonApplier();
  @override
  ProposalKind get kind => ProposalKind.entityCanon;

  @override
  Future<ProposalSnapshot> apply(Proposal p, Repository repo) async {
    final payload = EntityCanonPayload.fromJson(decodeMap(p.payload));
    final cards = await repo.listEntityCards(p.workId);
    final card = cards.firstWhere(
      (item) => item.id == payload.entityCardId,
      orElse: () => throw StateError('entity ${payload.entityCardId} missing'),
    );
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
    await repo.putEntityCard(updated);
    return ProposalSnapshot(
      before: jsonEncode({'kind': 'entity_canon', 'entityCard': card.toJson()}),
      after: jsonEncode({'kind': 'entity_canon', 'entityCard': updated.toJson()}),
    );
  }

  @override
  Future<void> rollback(
    Proposal p,
    String beforeSnapshot,
    Repository repo,
  ) async {
    final snapshot = decodeMap(beforeSnapshot);
    final raw = Map<String, dynamic>.from(snapshot['entityCard'] as Map);
    await repo.putEntityCard(EntityCard.fromJson(raw));
  }
}

class IllustrationAcceptApplier implements ProposalApplier {
  const IllustrationAcceptApplier();
  @override
  ProposalKind get kind => ProposalKind.illustrationAccept;

  @override
  Future<ProposalSnapshot> apply(Proposal p, Repository repo) async {
    final payload = IllustrationAcceptPayload.fromJson(decodeMap(p.payload));
    final illustrations = await repo.listIllustrations(p.workId);
    final illustration = illustrations.firstWhere(
      (item) => item.id == payload.illustrationId,
      orElse: () =>
          throw StateError('illustration ${payload.illustrationId} missing'),
    );
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
    await repo.putIllustration(updated);
    return ProposalSnapshot(
      before: jsonEncode({
        'kind': 'illustration_accept',
        'illustration': illustration.toJson(),
      }),
      after: jsonEncode({
        'kind': 'illustration_accept',
        'illustration': updated.toJson(),
      }),
    );
  }

  @override
  Future<void> rollback(
    Proposal p,
    String beforeSnapshot,
    Repository repo,
  ) async {
    final snapshot = decodeMap(beforeSnapshot);
    final raw = Map<String, dynamic>.from(snapshot['illustration'] as Map);
    await repo.putIllustration(Illustration.fromJson(raw));
  }
}

class ChapterSplitApplier implements ProposalApplier {
  const ChapterSplitApplier();
  @override
  ProposalKind get kind => ProposalKind.chapterSplit;

  @override
  Future<ProposalSnapshot> apply(Proposal p, Repository repo) async {
    final payload = ChapterSplitPayload.fromJson(decodeMap(p.payload));
    final current = await repo.listChapters(p.workId);
    final beforeEntries = <Map<String, dynamic>>[];
    for (final chapter in current) {
      beforeEntries.add({
        'id': chapter.id,
        'idx': chapter.idx,
        'title': chapter.title,
        'text': await repo.getChapterText(chapter.id),
      });
    }
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
            await repo.getChapterText(chapter.id),
          ),
        );
      } else {
        merged.add(
          MapEntry(chapter, await repo.getChapterText(chapter.id)),
        );
      }
    }
    await repo.replaceChapters(p.workId, merged);
    return ProposalSnapshot(
      before: jsonEncode({'kind': 'chapter_split', 'chapters': beforeEntries}),
      after: jsonEncode({
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
      }),
    );
  }

  @override
  Future<void> rollback(
    Proposal p,
    String beforeSnapshot,
    Repository repo,
  ) async {
    final snapshot = decodeMap(beforeSnapshot);
    final entries = (snapshot['chapters'] as List).cast<Map>();
    await repo.replaceChapters(p.workId, [
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
  }
}

/// 全局注册表：按 `ProposalKind` 取对应的 `ProposalApplier`。
class ProposalAppliers {
  static const Map<ProposalKind, ProposalApplier> all = {
    ProposalKind.textRepair: TextRepairApplier(),
    ProposalKind.entityCanon: EntityCanonApplier(),
    ProposalKind.illustrationAccept: IllustrationAcceptApplier(),
    ProposalKind.chapterSplit: ChapterSplitApplier(),
  };

  static ProposalApplier forKind(ProposalKind kind) {
    final applier = all[kind];
    if (applier == null) {
      throw StateError('no applier registered for $kind');
    }
    return applier;
  }
}