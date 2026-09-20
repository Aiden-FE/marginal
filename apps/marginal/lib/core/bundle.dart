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
    repairRuns: (j['repairRuns'] as List? ?? [])
        .map((x) => RepairRun.fromJson(Map<String, dynamic>.from(x)))
        .toList(),
    repairJobs: (j['repairJobs'] as List? ?? [])
        .map((x) => RepairJob.fromJson(Map<String, dynamic>.from(x)))
        .toList(),
    entityCards: (j['entityCards'] as List? ?? [])
        .map((x) => EntityCard.fromJson(Map<String, dynamic>.from(x)))
        .toList(),
    illustrations: (j['illustrations'] as List? ?? [])
        .map((x) => Illustration.fromJson(Map<String, dynamic>.from(x)))
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

// `reidForCopy` 已迁到 `lib/app/copy_rules.dart` —— 它属于书稿副本流程的领域规则，
// 与 `import_service.copyWorkBundle` / `Repository.importBundle(copy:true)` 共享；
// 不再留在 codec 文件里。
