import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'types.dart';

const int bundleFormatVersion = 1;

Uint8List buildBundle(
  BundleData data, {
  Map<String, Uint8List> blobData = const {},
  String appVersion = '2.0.0',
}) {
  final manifest = {
    'formatVersion': bundleFormatVersion,
    'appVersion': appVersion,
    'exportedAt': DateTime.now().millisecondsSinceEpoch,
    'workId': data.work.id,
    'contentHash': data.work.importSource,
  };
  final payload = {'manifest': manifest, ...data.toJson()};
  final archive = Archive()
    ..addFile(
      ArchiveFile(
        'bundle.json',
        utf8.encode(jsonEncode(payload)).length,
        utf8.encode(jsonEncode(payload)),
      ),
    );
  for (final e in blobData.entries) {
    archive.addFile(ArchiveFile('blobs/${e.key}', e.value.length, e.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

({BundleData data, Map<String, Uint8List> blobData}) readBundle(
  Uint8List bytes,
) {
  late Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('无效的 .mabk ZIP 文件');
  }
  final file = archive.findFile('bundle.json');
  if (file == null) throw const FormatException('全书包缺少 bundle.json');
  final j = jsonDecode(
    utf8.decode(file.content as List<int>),
  ) as Map<String, dynamic>;
  final m = Map<String, dynamic>.from(j['manifest'] ?? {});
  if (m['formatVersion'] is! num ||
      (m['formatVersion'] as num).toInt() > bundleFormatVersion) {
    throw const FormatException('全书包格式版本过高');
  }
  final d = BundleData(
    work: Work.fromJson(Map<String, dynamic>.from(j['work'])),
    chapters: (j['chapters'] as List? ?? [])
        .map((x) => Chapter.fromJson(Map<String, dynamic>.from(x)))
        .toList(),
    texts: Map<String, String>.from(j['texts'] ?? j['chapterTexts'] ?? {}),
    anchors: (j['anchors'] as List? ?? [])
        .map((x) => Anchor.fromJson(Map<String, dynamic>.from(x)))
        .toList(),
    blobs: (j['blobs'] as List? ?? [])
        .map((x) => BlobRec.fromJson(Map<String, dynamic>.from(x)))
        .toList(),
    prompts: (j['prompts'] as List? ?? [])
        .map((x) => Prompt.fromJson(Map<String, dynamic>.from(x)))
        .toList(),
    proposals: (j['proposals'] as List? ?? [])
        .map((x) => Proposal.fromJson(Map<String, dynamic>.from(x)))
        .toList(),
    runs: (j['runs'] as List? ?? [])
        .map((x) => AgentRun.fromJson(Map<String, dynamic>.from(x)))
        .toList(),
    toolCalls: (j['toolCalls'] as List? ?? [])
        .map((x) => ToolCall.fromJson(Map<String, dynamic>.from(x)))
        .toList(),
    revisions: (j['revisions'] as List? ?? [])
        .map((x) => Revision.fromJson(Map<String, dynamic>.from(x)))
        .toList(),
  );
  return (
    data: d,
    blobData: {
      for (final f in archive.files)
        if (f.name.startsWith('blobs/'))
          f.name.substring(6): Uint8List.fromList(f.content as List<int>),
    },
  );
}

BundleData reidForCopy(BundleData d) {
  final workId = '${d.work.id}-copy-${DateTime.now().microsecondsSinceEpoch}';
  final cm = {for (final c in d.chapters) c.id: '$workId-${c.id}'};
  final rm = {for (final r in d.runs) r.id: '$workId-${r.id}'};
  final bm = {for (final b in d.blobs) b.id: '$workId-${b.id}'};
  final pm = {for (final p in d.prompts) p.id: '$workId-${p.id}'};
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
            targetId: bm[a.targetId] ?? a.targetId,
            paraIndex: a.paraIndex,
            charOffset: a.charOffset,
            targetType: a.targetType,
            state: a.state,
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
            beforeSnapshot: r.beforeSnapshot,
            afterSnapshot: r.afterSnapshot,
            createdAt: r.createdAt,
          ),
        )
        .toList(),
  );
}
