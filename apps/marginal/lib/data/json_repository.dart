import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/types.dart';
import 'memory_repository.dart';

/// JSON 文件驱动：作为原生端可迁移基线，完整持久化 Repository 语义。
class JsonFileRepository extends MemoryRepository {
  JsonFileRepository(String path) : file = File(path);
  final File file;

  @override
  String get engine => 'json-file';

  bool _loading = false;

  @override
  Future<void> init() async {
    if (!await file.exists()) return;
    final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    _loading = true;
    await wipe();
    for (final raw in (root['works'] as List? ?? const [])) {
      await super.putWork(Work.fromJson(Map<String, dynamic>.from(raw as Map)));
    }
    final texts = Map<String, dynamic>.from(root['texts'] as Map? ?? const {});
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
    _loading = false;
  }

  Future<void> persist() async {
    if (_loading) return;
    final works = await listWorks();
    final chapters = <Chapter>[];
    final texts = <String, String>{};
    final anchors = <Anchor>[];
    final prompts = <Prompt>[];
    final proposals = <Proposal>[];
    final runs = <AgentRun>[];
    final calls = <ToolCall>[];
    final blobs = <BlobRec>[];
    final blobData = <String, String>{};
    for (final work in works) {
      final cs = await listChapters(work.id);
      chapters.addAll(cs);
      for (final c in cs) {
        texts[c.id] = await getChapterText(c.id);
      }
      anchors.addAll(await listAnchors(work.id));
      prompts.addAll(await listPrompts(work.id));
      proposals.addAll(await listProposals(work.id));
      runs.addAll(await listAgentRuns(work.id));
      for (final run in await listAgentRuns(work.id)) {
        calls.addAll(await listToolCalls(run.id));
      }
      final bs = await listBlobs(work.id);
      blobs.addAll(bs);
      for (final b in bs) {
        blobData[b.storageKey] = base64Encode(
          (await getBlobData(b.storageKey)) ?? Uint8List(0),
        );
      }
    }
    final root = {
      'works': works.map((x) => x.toJson()).toList(),
      'chapters': chapters.map((x) => x.toJson()).toList(),
      'texts': texts,
      'anchors': anchors.map((x) => x.toJson()).toList(),
      'prompts': prompts.map((x) => x.toJson()).toList(),
      'proposals': proposals.map((x) => x.toJson()).toList(),
      'runs': runs.map((x) => x.toJson()).toList(),
      'toolCalls': calls.map((x) => x.toJson()).toList(),
      'blobs': blobs.map((x) => x.toJson()).toList(),
      'blobData': blobData,
    };
    final tmp = File('${file.path}.tmp');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsString(jsonEncode(root));
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  }

  @override
  Future<void> putWork(Work value) async {
    await super.putWork(value);
    await persist();
  }

  @override
  Future<void> deleteWork(String id) async {
    await super.deleteWork(id);
    await persist();
  }

  @override
  Future<void> putChapter(String workId, Chapter chapter, String text) async {
    await super.putChapter(workId, chapter, text);
    await persist();
  }

  @override
  Future<void> replaceChapters(
    String workId,
    List<MapEntry<Chapter, String>> chapters,
  ) async {
    await super.replaceChapters(workId, chapters);
    await persist();
  }

  @override
  Future<void> deleteChapters(String workId) async {
    await super.deleteChapters(workId);
    await persist();
  }

  @override
  Future<void> putAnchor(Anchor value) async {
    await super.putAnchor(value);
    await persist();
  }

  @override
  Future<void> deleteAnchor(String id) async {
    await super.deleteAnchor(id);
    await persist();
  }

  @override
  Future<void> remapAnchors(String workId, List<Anchor> values) async {
    await super.remapAnchors(workId, values);
    await persist();
  }

  @override
  Future<void> putPrompt(Prompt value) async {
    await super.putPrompt(value);
    await persist();
  }

  @override
  Future<void> putProposal(Proposal value) async {
    await super.putProposal(value);
    await persist();
  }

  @override
  Future<void> updateProposal(Proposal value) async {
    await super.updateProposal(value);
    await persist();
  }

  @override
  Future<void> putAgentRun(AgentRun value) async {
    await super.putAgentRun(value);
    await persist();
  }

  @override
  Future<void> putToolCall(ToolCall value) async {
    await super.putToolCall(value);
    await persist();
  }

  @override
  Future<void> putBlob(BlobRec blob, Uint8List data) async {
    await super.putBlob(blob, data);
    await persist();
  }

  @override
  Future<void> importBundle(
    BundleData data, {
    required bool copy,
    Map<String, Uint8List> blobData = const {},
  }) async {
    await super.importBundle(data, copy: copy, blobData: blobData);
    await persist();
  }

  @override
  Future<void> wipe() async {
    await super.wipe();
    await persist();
  }
}
