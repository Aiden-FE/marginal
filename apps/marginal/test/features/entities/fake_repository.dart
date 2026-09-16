import 'dart:typed_data';

import 'package:marginal/core/repository.dart';
import 'package:marginal/core/types.dart';

/// 测试用全内存仓库：不依赖 lib/data（该层由并行工单维护）。
class FakeRepository implements Repository {
  final Map<String, Work> _works = {};
  final Map<String, Chapter> _chapters = {};
  final Map<String, String> _texts = {};
  final Map<String, Anchor> _anchors = {};
  final Map<String, Prompt> _prompts = {};
  final Map<String, Proposal> _proposals = {};
  final Map<String, Revision> _revisions = {};
  final Map<String, AgentRun> _runs = {};
  final Map<String, RepairRun> _repairRuns = {};
  final Map<String, ToolCall> _calls = {};
  final Map<String, EntityCard> _entityCards = {};
  final Map<String, Illustration> _illustrations = {};
  final Map<String, BlobRec> _blobs = {};
  final Map<String, Uint8List> _blobData = {};

  @override
  String get engine => 'fake';

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) => action();
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
  Future<void> deleteWork(String id) async => _works.remove(id);
  @override
  Future<List<Chapter>> listChapters(String workId) async =>
      _chapters.values.where((c) => c.workId == workId).toList()
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
    _chapters.removeWhere((_, c) => c.workId == workId);
    _texts.removeWhere((k, _) => !_chapters.containsKey(k));
  }

  @override
  Future<List<Anchor>> listAnchors(String workId) async =>
      _anchors.values.where((a) => a.workId == workId).toList();
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
      _prompts.values.where((p) => p.workId == workId).toList();
  @override
  Future<void> putPrompt(Prompt value) async => _prompts[value.id] = value;
  @override
  Future<List<Proposal>> listProposals(String workId) async =>
      _proposals.values.where((p) => p.workId == workId).toList();
  @override
  Future<void> putProposal(Proposal value) async =>
      _proposals[value.id] = value;
  @override
  Future<void> updateProposal(Proposal value) async =>
      _proposals[value.id] = value;
  @override
  Future<List<Revision>> listRevisions(String workId) async =>
      _revisions.values.where((r) => r.workId == workId).toList();
  @override
  Future<void> putRevision(Revision value) async =>
      _revisions[value.id] = value;
  @override
  Future<List<EntityCard>> listEntityCards(String workId) async => [
    ..._entityCards.values.where((c) => c.workId == workId),
  ];
  @override
  Future<void> putEntityCard(EntityCard value) async =>
      _entityCards[value.id] = value;
  @override
  Future<void> deleteEntityCard(String id) async => _entityCards.remove(id);
  @override
  Future<List<Illustration>> listIllustrations(String workId) async => [
    ..._illustrations.values.where((i) => i.workId == workId),
  ];
  @override
  Future<void> putIllustration(Illustration value) async =>
      _illustrations[value.id] = value;
  @override
  Future<void> deleteIllustration(String id) async => _illustrations.remove(id);
  @override
  Future<List<AgentRun>> listAgentRuns(String workId) async =>
      _runs.values.where((r) => r.workId == workId).toList();
  @override
  Future<void> putAgentRun(AgentRun value) async => _runs[value.id] = value;
  @override
  Future<List<RepairRun>> listRepairRuns(String workId) async =>
      _repairRuns.values.where((r) => r.workId == workId).toList();
  @override
  Future<void> putRepairRun(RepairRun value) async =>
      _repairRuns[value.id] = value;
  @override
  Future<List<ToolCall>> listToolCalls(String runId) async =>
      _calls.values.where((c) => c.runId == runId).toList();
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
      _blobs.values.where((b) => b.workId == workId).toList();
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
    entityCards: await listEntityCards(workId),
    illustrations: await listIllustrations(workId),
    revisions: await listRevisions(workId),
    runs: await listAgentRuns(workId),
    toolCalls: await listToolCalls(''),
  );
  @override
  Future<void> importBundle(
    BundleData data, {
    required bool copy,
    Map<String, Uint8List> blobData = const {},
  }) async {}
  @override
  Future<void> wipe() async {
    _works.clear();
    _chapters.clear();
    _texts.clear();
    _anchors.clear();
    _prompts.clear();
    _proposals.clear();
    _revisions.clear();
    _runs.clear();
    _calls.clear();
    _entityCards.clear();
    _illustrations.clear();
    _blobs.clear();
    _blobData.clear();
  }
}
