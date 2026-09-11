import 'dart:convert';
import 'dart:typed_data';

import '../core/types.dart';
import 'memory_repository.dart';

/// Shared snapshot codec and mutation persistence for durable repositories.
mixin SnapshotPersistence on MemoryRepository {
  bool _loadingSnapshot = false;

  /// Persists the current in-memory state in the driver's storage.
  Future<void> persist();

  Future<void> loadSnapshotRoot(Map<String, dynamic> root) async {
    _loadingSnapshot = true;
    try {
      await wipe();
      for (final raw in (root['works'] as List? ?? const [])) {
        await super.putWork(
          Work.fromJson(Map<String, dynamic>.from(raw as Map)),
        );
      }
      final texts = Map<String, dynamic>.from(
        root['texts'] as Map? ?? const {},
      );
      for (final raw in (root['chapters'] as List? ?? const [])) {
        final json = Map<String, dynamic>.from(raw as Map);
        await super.putChapter(
          json['workId'] as String,
          Chapter.fromJson(json),
          texts[json['id']] as String? ?? '',
        );
      }
      for (final raw in (root['anchors'] as List? ?? const [])) {
        await super.putAnchor(
          Anchor.fromJson(Map<String, dynamic>.from(raw as Map)),
        );
      }
      for (final raw in (root['prompts'] as List? ?? const [])) {
        await super.putPrompt(
          Prompt.fromJson(Map<String, dynamic>.from(raw as Map)),
        );
      }
      for (final raw in (root['proposals'] as List? ?? const [])) {
        await super.putProposal(
          Proposal.fromJson(Map<String, dynamic>.from(raw as Map)),
        );
      }
      for (final raw in (root['revisions'] as List? ?? const [])) {
        await super.putRevision(
          Revision.fromJson(Map<String, dynamic>.from(raw as Map)),
        );
      }
      for (final raw in (root['runs'] as List? ?? const [])) {
        await super.putAgentRun(
          AgentRun.fromJson(Map<String, dynamic>.from(raw as Map)),
        );
      }
      for (final raw in (root['toolCalls'] as List? ?? const [])) {
        await super.putToolCall(
          ToolCall.fromJson(Map<String, dynamic>.from(raw as Map)),
        );
      }
      final blobBytes = Map<String, dynamic>.from(
        root['blobData'] as Map? ?? const {},
      );
      for (final raw in (root['blobs'] as List? ?? const [])) {
        final blob = BlobRec.fromJson(Map<String, dynamic>.from(raw as Map));
        await super.putBlob(
          blob,
          Uint8List.fromList(
            base64Decode(blobBytes[blob.storageKey] as String? ?? ''),
          ),
        );
      }
    } finally {
      _loadingSnapshot = false;
    }
  }

  Future<Map<String, Object?>> snapshotRoot() async {
    final works = await listWorks();
    final chapters = <Chapter>[];
    final texts = <String, String>{};
    final anchors = <Anchor>[];
    final prompts = <Prompt>[];
    final proposals = <Proposal>[];
    final revisions = <Revision>[];
    final runs = <AgentRun>[];
    final calls = <ToolCall>[];
    final blobs = <BlobRec>[];
    final blobData = <String, String>{};
    for (final work in works) {
      final cs = await listChapters(work.id);
      chapters.addAll(cs);
      for (final chapter in cs) {
        texts[chapter.id] = await getChapterText(chapter.id);
      }
      anchors.addAll(await listAnchors(work.id));
      prompts.addAll(await listPrompts(work.id));
      proposals.addAll(await listProposals(work.id));
      revisions.addAll(await listRevisions(work.id));
      final workRuns = await listAgentRuns(work.id);
      runs.addAll(workRuns);
      for (final run in workRuns) {
        calls.addAll(await listToolCalls(run.id));
      }
      final workBlobs = await listBlobs(work.id);
      blobs.addAll(workBlobs);
      for (final blob in workBlobs) {
        blobData[blob.storageKey] = base64Encode(
          (await getBlobData(blob.storageKey)) ?? Uint8List(0),
        );
      }
    }
    return {
      'works': works.map((x) => x.toJson()).toList(),
      'chapters': chapters.map((x) => x.toJson()).toList(),
      'texts': texts,
      'anchors': anchors.map((x) => x.toJson()).toList(),
      'prompts': prompts.map((x) => x.toJson()).toList(),
      'proposals': proposals.map((x) => x.toJson()).toList(),
      'revisions': revisions.map((x) => x.toJson()).toList(),
      'runs': runs.map((x) => x.toJson()).toList(),
      'toolCalls': calls.map((x) => x.toJson()).toList(),
      'blobs': blobs.map((x) => x.toJson()).toList(),
      'blobData': blobData,
    };
  }

  Future<void> _persistAfter(Future<void> Function() operation) async {
    await operation();
    await persist();
  }

  @override
  Future<void> putWork(Work value) => _persistAfter(() => super.putWork(value));
  @override
  Future<void> deleteWork(String id) =>
      _persistAfter(() => super.deleteWork(id));
  @override
  Future<void> putChapter(String workId, Chapter chapter, String text) =>
      _persistAfter(() => super.putChapter(workId, chapter, text));
  @override
  Future<void> replaceChapters(
    String workId,
    List<MapEntry<Chapter, String>> chapters,
  ) => _persistAfter(() => super.replaceChapters(workId, chapters));
  @override
  Future<void> deleteChapters(String workId) =>
      _persistAfter(() => super.deleteChapters(workId));
  @override
  Future<void> putAnchor(Anchor value) =>
      _persistAfter(() => super.putAnchor(value));
  @override
  Future<void> deleteAnchor(String id) =>
      _persistAfter(() => super.deleteAnchor(id));
  @override
  Future<void> remapAnchors(String workId, List<Anchor> values) =>
      _persistAfter(() => super.remapAnchors(workId, values));
  @override
  Future<void> putPrompt(Prompt value) =>
      _persistAfter(() => super.putPrompt(value));
  @override
  Future<void> putProposal(Proposal value) =>
      _persistAfter(() => super.putProposal(value));
  @override
  Future<void> updateProposal(Proposal value) =>
      _persistAfter(() => super.updateProposal(value));
  @override
  Future<void> putRevision(Revision value) =>
      _persistAfter(() => super.putRevision(value));
  @override
  Future<void> putAgentRun(AgentRun value) =>
      _persistAfter(() => super.putAgentRun(value));
  @override
  Future<void> putToolCall(ToolCall value) =>
      _persistAfter(() => super.putToolCall(value));
  @override
  Future<void> putBlob(BlobRec blob, Uint8List data) =>
      _persistAfter(() => super.putBlob(blob, data));
  @override
  Future<void> importBundle(
    BundleData data, {
    required bool copy,
    Map<String, Uint8List> blobData = const {},
  }) => _persistAfter(
    () => super.importBundle(data, copy: copy, blobData: blobData),
  );
  @override
  Future<void> wipe() => _persistAfter(super.wipe);

  bool get isLoadingSnapshot => _loadingSnapshot;
}
