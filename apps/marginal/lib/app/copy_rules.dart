import '../core/types.dart';

/// 一本书稿被"复制"成一份独立的副本时，所有跨实体外键需要按新 `workId` 重新映射。
///
/// 这份规则在书稿副本流程里被 `import_service.copyWorkBundle` 调用，
/// 也被 `Repository.importBundle` 在 `copy:true` 路径上使用 —— 它是一份
/// 跨两个入口共享的纯领域规则，因此放在 app 层（与导入流程同层），而不是
/// `core/bundle.dart`（那里只保留编解码与容器类型）。
BundleData reidForCopy(BundleData d) {
  final workId = '${d.work.id}-copy-${DateTime.now().microsecondsSinceEpoch}';
  final cm = {for (final c in d.chapters) c.id: '$workId-${c.id}'};
  final rm = {for (final r in d.runs) r.id: '$workId-${r.id}'};
  final rrm = {for (final r in d.repairRuns) r.id: '$workId-${r.id}'};
  final rjm = {for (final j in d.repairJobs) j.id: '$workId-${j.id}'};
  final bm = {for (final b in d.blobs) b.id: '$workId-${b.id}'};
  final pm = {for (final p in d.prompts) p.id: '$workId-${p.id}'};
  final em = {for (final e in d.entityCards) e.id: '$workId-${e.id}'};
  final im = {for (final i in d.illustrations) i.id: '$workId-${i.id}'};
  final propm = {for (final p in d.proposals) p.id: '$workId-${p.id}'};
  return BundleData(
    work: Work(
      id: workId,
      title: '${d.work.title}（副本）',
      author: d.work.author,
      importSource: d.work.importSource,
      createdAt: d.work.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      settings: d.work.settings,
    ),
    chapters: d.chapters
        .map(
          (c) => Chapter(
            id: cm[c.id]!,
            workId: workId,
            idx: c.idx,
            title: c.title,
            wordCount: c.wordCount,
            contentHash: c.contentHash,
          ),
        )
        .toList(),
    texts: {for (final e in d.texts.entries) cm[e.key]!: e.value},
    anchors: d.anchors
        .map(
          (a) => Anchor(
            id: '$workId-${a.id}',
            workId: workId,
            chapterId: cm[a.chapterId] ?? a.chapterId,
            targetId: bm[a.targetId] ?? im[a.targetId] ?? a.targetId,
            paraIndex: a.paraIndex,
            charOffset: a.charOffset,
            targetType: a.targetType,
            state: a.state,
          ),
        )
        .toList(),
    entityCards: d.entityCards
        .map(
          (e) => EntityCard(
            id: em[e.id]!,
            workId: workId,
            name: e.name,
            kind: e.kind,
            aliases: e.aliases,
            attributes: e.attributes,
            status: e.status,
            portraitBlobId: e.portraitBlobId == null
                ? null
                : (bm[e.portraitBlobId] ?? e.portraitBlobId),
            createdAt: e.createdAt,
          ),
        )
        .toList(),
    illustrations: d.illustrations
        .map(
          (i) => Illustration(
            id: im[i.id]!,
            workId: workId,
            prompt: i.prompt,
            providerId: i.providerId,
            model: i.model,
            blobId: bm[i.blobId] ?? i.blobId,
            chapterId: cm[i.chapterId] ?? i.chapterId,
            paraIndex: i.paraIndex,
            status: i.status,
            entityCardIds: i.entityCardIds.map((x) => em[x] ?? x).toList(),
            createdAt: i.createdAt,
          ),
        )
        .toList(),
    blobs: d.blobs
        .map(
          (b) => BlobRec(
            id: bm[b.id]!,
            workId: workId,
            storageKey: b.storageKey,
            kind: b.kind,
            mime: b.mime,
            sha256: b.sha256,
            byteSize: b.byteSize,
          ),
        )
        .toList(),
    prompts: d.prompts
        .map(
          (p) => Prompt(
            id: pm[p.id]!,
            workId: workId,
            text: p.text,
            createdAt: p.createdAt,
          ),
        )
        .toList(),
    proposals: d.proposals
        .map(
          (p) => Proposal(
            id: propm[p.id]!,
            workId: workId,
            runId: rm[p.runId] ?? p.runId,
            type: p.type,
            payload: p.payload,
            status: p.status,
            createdAt: p.createdAt,
          ),
        )
        .toList(),
    repairRuns: d.repairRuns
        .map(
          (r) => RepairRun(
            id: rrm[r.id]!,
            workId: workId,
            kind: r.kind,
            providerId: r.providerId,
            model: r.model,
            startedAt: r.startedAt,
            finishedAt: r.finishedAt,
            status: r.status,
          ),
        )
        .toList(),
    repairJobs: d.repairJobs
        .map(
          (j) => RepairJob(
            id: rjm[j.id]!,
            workId: workId,
            runId: rrm[j.runId] ?? j.runId,
            kind: j.kind,
            proposalId: propm[j.proposalId] ?? j.proposalId,
            payload: j.payload,
            status: j.status,
            attempts: j.attempts,
            nextRetryAt: j.nextRetryAt,
            error: j.error,
            createdAt: j.createdAt,
            updatedAt: j.updatedAt,
          ),
        )
        .toList(),
    runs: d.runs
        .map(
          (r) => AgentRun(
            id: rm[r.id]!,
            workId: workId,
            status: r.status,
            startedAt: r.startedAt,
            finishedAt: r.finishedAt,
            inputTokens: r.inputTokens,
            outputTokens: r.outputTokens,
          ),
        )
        .toList(),
    toolCalls: d.toolCalls
        .map(
          (c) => ToolCall(
            id: '$workId-${c.id}',
            runId: rm[c.runId] ?? c.runId,
            toolName: c.toolName,
            inputSummary: c.inputSummary,
            resultSummary: c.resultSummary,
            status: c.status,
            startedAt: c.startedAt,
          ),
        )
        .toList(),
    revisions: d.revisions
        .map(
          (r) => Revision(
            id: '$workId-${r.id}',
            workId: workId,
            proposalId: propm[r.proposalId] ?? r.proposalId,
            runId: rrm[r.runId] ?? r.runId,
            beforeSnapshot: r.beforeSnapshot,
            afterSnapshot: r.afterSnapshot,
            createdAt: r.createdAt,
          ),
        )
        .toList(),
  );
}