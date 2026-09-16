import 'dart:typed_data';

import '../core/bundle.dart';
import '../core/repository.dart';
import '../core/types.dart';

class MemoryRepository implements Repository {
  final Map<String, Work> _works = {};
  final Map<String, Chapter> _chapters = {};
  final Map<String, String> _texts = {};
  final Map<String, Anchor> _anchors = {};
  final Map<String, Prompt> _prompts = {};
  final Map<String, Proposal> _proposals = {};
  final Map<String, AgentRun> _runs = {};
  final Map<String, RepairRun> _repairRuns = {};
  final Map<String, RepairJob> _repairJobs = {};
  final Map<String, ToolCall> _calls = {};
  final Map<String, BlobRec> _blobs = {};
  final Map<String, Revision> _revisions = {};
  final Map<String, EntityCard> _entityCards = {};
  final Map<String, Illustration> _illustrations = {};
  final Map<String, Uint8List> _blobData = {};
  @override
  String get engine => 'memory';

  int _transactionDepth = 0;

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) async {
    if (_transactionDepth > 0) return action();
    final snapshots = <({BundleData data, Map<String, Uint8List> blobData})>[];
    for (final work in await listWorks()) {
      final data = await exportAll(work.id);
      final bytes = <String, Uint8List>{};
      for (final blob in data.blobs) {
        bytes[blob.storageKey] =
            await getBlobData(blob.storageKey) ?? Uint8List(0);
      }
      snapshots.add((data: data, blobData: bytes));
    }
    _transactionDepth++;
    try {
      return await action();
    } catch (_) {
      await wipe();
      for (final snapshot in snapshots) {
        await importBundle(
          snapshot.data,
          copy: false,
          blobData: snapshot.blobData,
        );
      }
      rethrow;
    } finally {
      _transactionDepth--;
    }
  }

  @override
  Future<void> init() async {}
  @override
  Future<void> close() async {}
  @override
  Future<List<Work>> listWorks() async => _works.values.toList();
  @override
  Future<Work?> getWork(String id) async => _works[id];
  @override
  Future<void> putWork(Work value) async => _works[value.id] = value;
  @override
  Future<void> deleteWork(String id) async {
    _works.remove(id);
    _chapters.removeWhere((_, v) => v.workId == id);
    _texts.removeWhere((k, _) => !_chapters.containsKey(k));
    _anchors.removeWhere((_, v) => v.workId == id);
    _prompts.removeWhere((_, v) => v.workId == id);
    _proposals.removeWhere((_, v) => v.workId == id);
    _revisions.removeWhere((_, v) => v.workId == id);
    _repairRuns.removeWhere((_, v) => v.workId == id);
    _repairJobs.removeWhere((_, v) => v.workId == id);
    _runs.removeWhere((_, v) => v.workId == id);
    _blobs.removeWhere((_, v) => v.workId == id);
    _entityCards.removeWhere((_, v) => v.workId == id);
    _illustrations.removeWhere((_, v) => v.workId == id);
  }

  @override
  Future<List<Chapter>> listChapters(String workId) async =>
      _chapters.values.where((v) => v.workId == workId).toList()
        ..sort((a, b) => a.idx.compareTo(b.idx));
  @override
  Future<String> getChapterText(String chapterId) async =>
      _texts[chapterId] ?? '';
  @override
  Future<String> readChapterRange(
    String chapterId,
    int start,
    int length,
  ) async {
    final text = await getChapterText(chapterId);
    final safeStart = start.clamp(0, text.length);
    final safeEnd = (safeStart + length.clamp(0, text.length)).clamp(
      safeStart,
      text.length,
    );
    return text.substring(safeStart, safeEnd);
  }

  @override
  Future<void> putChapter(String workId, Chapter chapter, String text) async {
    if (chapter.workId != workId) throw ArgumentError('workId mismatch');
    _chapters[chapter.id] = chapter;
    _texts[chapter.id] = text;
  }

  @override
  Future<void> replaceChapters(
    String workId,
    List<MapEntry<Chapter, String>> chapters,
  ) async {
    await deleteChapters(workId);
    for (final e in chapters) {
      await putChapter(workId, e.key, e.value);
    }
  }

  @override
  Future<void> deleteChapters(String workId) async {
    final ids = _chapters.values
        .where((v) => v.workId == workId)
        .map((v) => v.id)
        .toSet();
    _chapters.removeWhere((k, v) => v.workId == workId);
    for (final id in ids) {
      _texts.remove(id);
    }
  }

  @override
  Future<List<Anchor>> listAnchors(String workId) async =>
      _anchors.values.where((v) => v.workId == workId).toList();
  @override
  Future<void> putAnchor(Anchor value) async => _anchors[value.id] = value;
  @override
  Future<void> deleteAnchor(String id) async => _anchors.remove(id);
  @override
  Future<void> remapAnchors(String workId, List<Anchor> values) async {
    for (final a in values) {
      if (a.workId == workId) _anchors[a.id] = a;
    }
  }

  @override
  Future<List<Prompt>> listPrompts(String workId) async =>
      _prompts.values.where((v) => v.workId == workId).toList();
  @override
  Future<void> putPrompt(Prompt value) async => _prompts[value.id] = value;
  @override
  Future<List<Proposal>> listProposals(String workId) async =>
      _proposals.values.where((v) => v.workId == workId).toList();
  @override
  Future<void> putProposal(Proposal value) async =>
      _proposals[value.id] = value;
  @override
  Future<void> updateProposal(Proposal value) async {
    if (!_proposals.containsKey(value.id)) {
      throw StateError('proposal not found');
    }
    _proposals[value.id] = value;
  }

  @override
  Future<List<Revision>> listRevisions(String workId) async =>
      _revisions.values.where((v) => v.workId == workId).toList();

  @override
  Future<List<EntityCard>> listEntityCards(String workId) async =>
      _entityCards.values.where((v) => v.workId == workId).toList();
  @override
  Future<void> putEntityCard(EntityCard value) async =>
      _entityCards[value.id] = value;
  @override
  Future<void> deleteEntityCard(String id) async {
    _entityCards.remove(id);
    for (final illustration in _illustrations.values.toList()) {
      if (illustration.entityCardIds.contains(id)) {
        _illustrations[illustration.id] = Illustration(
          id: illustration.id,
          workId: illustration.workId,
          prompt: illustration.prompt,
          providerId: illustration.providerId,
          model: illustration.model,
          blobId: illustration.blobId,
          chapterId: illustration.chapterId,
          paraIndex: illustration.paraIndex,
          status: illustration.status,
          entityCardIds: illustration.entityCardIds
              .where((x) => x != id)
              .toList(),
          createdAt: illustration.createdAt,
        );
      }
    }
  }

  @override
  Future<List<Illustration>> listIllustrations(String workId) async =>
      _illustrations.values.where((v) => v.workId == workId).toList();
  @override
  Future<void> putIllustration(Illustration value) async =>
      _illustrations[value.id] = value;
  @override
  Future<void> deleteIllustration(String id) async => _illustrations.remove(id);
  @override
  Future<void> putRevision(Revision value) async =>
      _revisions[value.id] = value;

  @override
  Future<List<AgentRun>> listAgentRuns(String workId) async =>
      _runs.values.where((v) => v.workId == workId).toList();
  @override
  Future<void> putAgentRun(AgentRun value) async => _runs[value.id] = value;
  @override
  Future<List<RepairRun>> listRepairRuns(String workId) async =>
      _repairRuns.values.where((v) => v.workId == workId).toList();
  @override
  Future<void> putRepairRun(RepairRun value) async =>
      _repairRuns[value.id] = value;
  @override
  Future<List<RepairJob>> listRepairJobs(String workId) async =>
      _repairJobs.values.where((v) => v.workId == workId).toList();
  @override
  Future<void> putRepairJob(RepairJob value) async =>
      _repairJobs[value.id] = value;
  @override
  Future<List<ToolCall>> listToolCalls(String runId) async =>
      _calls.values.where((v) => v.runId == runId).toList();
  @override
  Future<void> putToolCall(ToolCall value) async => _calls[value.id] = value;
  @override
  Future<void> putBlob(BlobRec blob, Uint8List data) async {
    _blobs[blob.id] = blob;
    _blobData[blob.storageKey] = Uint8List.fromList(data);
  }

  @override
  Future<Uint8List?> getBlobData(String storageKey) async =>
      _blobData[storageKey] == null
      ? null
      : Uint8List.fromList(_blobData[storageKey]!);
  @override
  Future<List<BlobRec>> listBlobs(String workId) async =>
      _blobs.values.where((v) => v.workId == workId).toList();
  @override
  Future<BundleData> exportAll(String workId) async => BundleData(
    work: _works[workId]!,
    chapters: await listChapters(workId),
    texts: {
      for (final c in await listChapters(workId)) c.id: _texts[c.id] ?? '',
    },
    anchors: await listAnchors(workId),
    blobs: await listBlobs(workId),
    prompts: await listPrompts(workId),
    proposals: await listProposals(workId),
    revisions: await listRevisions(workId),
    entityCards: await listEntityCards(workId),
    illustrations: await listIllustrations(workId),
    runs: await listAgentRuns(workId),
    repairRuns: await listRepairRuns(workId),
    repairJobs: await listRepairJobs(workId),
    toolCalls: (await Future.wait(
      (await listAgentRuns(workId)).map((r) => listToolCalls(r.id)),
    )).expand((x) => x).toList(),
  );
  @override
  Future<void> importBundle(
    BundleData data, {
    required bool copy,
    Map<String, Uint8List> blobData = const {},
  }) async {
    final payload = copy ? reidForCopy(data) : data;
    if (!copy && _works.containsKey(payload.work.id)) {
      await deleteWork(payload.work.id);
    }
    await putWork(payload.work);
    for (final c in payload.chapters) {
      await putChapter(payload.work.id, c, payload.texts[c.id] ?? '');
    }
    for (final a in payload.anchors) {
      await putAnchor(a);
    }
    for (final p in payload.prompts) {
      await putPrompt(p);
    }
    for (final p in payload.proposals) {
      await putProposal(p);
    }
    for (final c in payload.entityCards) {
      await putEntityCard(c);
    }
    for (final i in payload.illustrations) {
      await putIllustration(i);
    }
    for (final r in payload.revisions) {
      await putRevision(r);
    }
    for (final r in payload.runs) {
      await putAgentRun(r);
    }
    for (final r in payload.repairRuns) {
      await putRepairRun(r);
    }
    for (final j in payload.repairJobs) {
      await putRepairJob(j);
    }
    for (final c in payload.toolCalls) {
      await putToolCall(c);
    }
    for (final b in payload.blobs) {
      await putBlob(b, blobData[b.storageKey] ?? Uint8List(0));
    }
  }

  @override
  Future<void> wipe() async {
    _works.clear();
    _chapters.clear();
    _texts.clear();
    _anchors.clear();
    _prompts.clear();
    _proposals.clear();
    _revisions.clear();
    _entityCards.clear();
    _illustrations.clear();
    _runs.clear();
    _repairRuns.clear();
    _repairJobs.clear();
    _calls.clear();
    _blobs.clear();
    _blobData.clear();
  }

  Future<void> restore(BundleData data) => importBundle(data, copy: false);
}
