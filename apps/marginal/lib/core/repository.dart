import 'dart:typed_data';

import 'types.dart';

abstract class Repository {
  Future<void> init();
  Future<void> close();
  String get engine;
  Future<List<Work>> listWorks();
  Future<Work?> getWork(String id);
  Future<void> putWork(Work value);
  Future<void> deleteWork(String id);
  Future<List<Chapter>> listChapters(String workId);
  Future<String> getChapterText(String chapterId);
  Future<int> getChapterTextLength(String chapterId) async =>
      (await getChapterText(chapterId)).length;

  /// Reads a bounded UTF-16 range without requiring callers to materialize the full chapter.
  /// Drivers that cannot range-read may return a substring from their existing text store.
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

  Future<void> putChapter(String workId, Chapter chapter, String text);
  Future<void> replaceChapters(
    String workId,
    List<MapEntry<Chapter, String>> chapters,
  );
  Future<void> deleteChapters(String workId);
  Future<List<Anchor>> listAnchors(String workId);
  Future<void> putAnchor(Anchor value);
  Future<void> deleteAnchor(String id);
  Future<void> remapAnchors(String workId, List<Anchor> values);
  Future<List<Prompt>> listPrompts(String workId);
  Future<void> putPrompt(Prompt value);
  Future<List<Proposal>> listProposals(String workId);
  Future<void> putProposal(Proposal value);
  Future<void> updateProposal(Proposal value);
  Future<List<Revision>> listRevisions(String workId);
  Future<void> putRevision(Revision value);
  Future<List<EntityCard>> listEntityCards(String workId);
  Future<void> putEntityCard(EntityCard value);
  Future<void> deleteEntityCard(String id);
  Future<List<Illustration>> listIllustrations(String workId);
  Future<void> putIllustration(Illustration value);
  Future<void> deleteIllustration(String id);
  Future<List<AgentRun>> listAgentRuns(String workId);
  Future<void> putAgentRun(AgentRun value);
  Future<List<RepairRun>> listRepairRuns(String workId);
  Future<void> putRepairRun(RepairRun value);
  Future<List<RepairJob>> listRepairJobs(String workId);
  Future<void> putRepairJob(RepairJob value);
  Future<List<ToolCall>> listToolCalls(String runId);
  Future<void> putToolCall(ToolCall value);
  Future<void> putBlob(BlobRec blob, Uint8List data);
  Future<Uint8List?> getBlobData(String storageKey);
  Future<List<BlobRec>> listBlobs(String workId);
  Future<BundleData> exportAll(String workId);
  Future<void> importBundle(
    BundleData data, {
    required bool copy,
    Map<String, Uint8List> blobData = const {},
  });
  Future<void> wipe();

  /// Executes a compound mutation as one logical commit. Drivers with native
  /// transactions provide rollback; lightweight test doubles default to direct execution.
  Future<T> runInTransaction<T>(Future<T> Function() action) => action();
}
