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
  Future<List<AgentRun>> listAgentRuns(String workId);
  Future<void> putAgentRun(AgentRun value);
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
}
