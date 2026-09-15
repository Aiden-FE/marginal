import 'dart:convert';
import 'dart:typed_data';

class Work {
  final String id, title, author, importSource;
  final int createdAt, updatedAt;
  final Map<String, dynamic> settings;
  const Work({
    required this.id,
    required this.title,
    this.author = '',
    this.importSource = '',
    int? createdAt,
    int? updatedAt,
    this.settings = const {},
  }) : createdAt = createdAt ?? 0,
       updatedAt = updatedAt ?? 0;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'importSource': importSource,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'settings': settings,
  };
  factory Work.fromJson(Map<String, dynamic> j) => Work(
    id: j['id'],
    title: j['title'] ?? '',
    author: j['author'] ?? '',
    importSource: j['importSource'] ?? '',
    createdAt: j['createdAt'] ?? 0,
    updatedAt: j['updatedAt'] ?? 0,
    settings: Map<String, dynamic>.from(j['settings'] ?? {}),
  );
}

class Chapter {
  final String id, workId, title, contentHash;
  final int idx, wordCount;
  const Chapter({
    required this.id,
    required this.workId,
    required this.idx,
    required this.title,
    this.wordCount = 0,
    this.contentHash = '',
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'workId': workId,
    'idx': idx,
    'title': title,
    'wordCount': wordCount,
    'contentHash': contentHash,
  };
  factory Chapter.fromJson(Map<String, dynamic> j) => Chapter(
    id: j['id'],
    workId: j['workId'],
    idx: j['idx'] ?? 0,
    title: j['title'] ?? '',
    wordCount: j['wordCount'] ?? 0,
    contentHash: j['contentHash'] ?? '',
  );
}

class Anchor {
  final String id, workId, chapterId, targetId;
  final int paraIndex, charOffset;
  final String targetType, state;
  const Anchor({
    required this.id,
    required this.workId,
    required this.chapterId,
    required this.targetId,
    this.paraIndex = 0,
    this.charOffset = 0,
    this.targetType = 'illustration',
    this.state = 'active',
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'workId': workId,
    'chapterId': chapterId,
    'targetId': targetId,
    'paraIndex': paraIndex,
    'charOffset': charOffset,
    'targetType': targetType,
    'state': state,
  };
  factory Anchor.fromJson(Map<String, dynamic> j) => Anchor(
    id: j['id'],
    workId: j['workId'],
    chapterId: j['chapterId'],
    targetId: j['targetId'],
    paraIndex: j['paraIndex'] ?? 0,
    charOffset: j['charOffset'] ?? 0,
    targetType: j['targetType'] ?? 'illustration',
    state: j['state'] ?? 'active',
  );
}

class Prompt {
  final String id, workId, text;
  final int createdAt;
  const Prompt({
    required this.id,
    required this.workId,
    required this.text,
    this.createdAt = 0,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'workId': workId,
    'text': text,
    'createdAt': createdAt,
  };
  factory Prompt.fromJson(Map<String, dynamic> j) => Prompt(
    id: j['id'],
    workId: j['workId'],
    text: j['text'] ?? '',
    createdAt: j['createdAt'] ?? 0,
  );
}

enum ProposalKind {
  textRepair,
  chapterSplit,
  entityCanon,
  illustrationAccept,
  coverage,
  delete,
}

enum ProposalStatus { pending, approved, rejected, expired, rolledBack }

ProposalKind parseProposalKind(String value) => switch (value) {
  'text_repair' => ProposalKind.textRepair,
  'chapter_split' => ProposalKind.chapterSplit,
  'entity_canon' => ProposalKind.entityCanon,
  'illustration_accept' => ProposalKind.illustrationAccept,
  'coverage' => ProposalKind.coverage,
  'delete' => ProposalKind.delete,
  _ => throw FormatException('unknown proposal kind: $value'),
};
ProposalStatus parseProposalStatus(String value) => switch (value) {
  'pending' => ProposalStatus.pending,
  'approved' => ProposalStatus.approved,
  'rejected' => ProposalStatus.rejected,
  'expired' => ProposalStatus.expired,
  'rolled_back' => ProposalStatus.rolledBack,
  _ => throw FormatException('unknown proposal status: $value'),
};

class TextRepairPayload {
  final String chapterId;
  final List<Map<String, dynamic>> patches;
  const TextRepairPayload({required this.chapterId, required this.patches});
  factory TextRepairPayload.fromJson(Map<String, dynamic> j) {
    if (j['chapterId'] is! String ||
        j['chapterId'].isEmpty ||
        j['patches'] is! List) {
      throw const FormatException('invalid text_repair payload');
    }
    final patches = (j['patches'] as List).map((raw) {
      final p = Map<String, dynamic>.from(raw as Map);
      if (p['paraIndex'] is! num ||
          p['original'] is! String ||
          p['replacement'] is! String) {
        throw const FormatException('invalid text repair patch');
      }
      return p;
    }).toList();
    return TextRepairPayload(chapterId: j['chapterId'], patches: patches);
  }
}

class ChapterSplitPayload {
  final String sourceChapterId;
  final List<Map<String, dynamic>> chapters;

  const ChapterSplitPayload({
    required this.sourceChapterId,
    required this.chapters,
  });

  factory ChapterSplitPayload.fromJson(Map<String, dynamic> j) {
    if (j['sourceChapterId'] is! String ||
        (j['sourceChapterId'] as String).isEmpty ||
        j['chapters'] is! List ||
        (j['chapters'] as List).isEmpty) {
      throw const FormatException('invalid chapter_split payload');
    }
    final chapters = (j['chapters'] as List).map((raw) {
      if (raw is! Map) throw const FormatException('invalid split chapter');
      final chapter = Map<String, dynamic>.from(raw);
      if (chapter['title'] is! String ||
          chapter['text'] is! String ||
          (chapter['title'] as String).trim().isEmpty) {
        throw const FormatException('invalid split chapter');
      }
      return chapter;
    }).toList();
    return ChapterSplitPayload(
      sourceChapterId: j['sourceChapterId'] as String,
      chapters: chapters,
    );
  }
}

class EntityCanonPayload {
  final String entityCardId;
  final String status;

  const EntityCanonPayload({required this.entityCardId, required this.status});

  factory EntityCanonPayload.fromJson(Map<String, dynamic> j) {
    if (j['entityCardId'] is! String ||
        (j['entityCardId'] as String).isEmpty ||
        j['status'] is! String ||
        !{'draft', 'canon'}.contains(j['status'])) {
      throw const FormatException('invalid entity_canon payload');
    }
    return EntityCanonPayload(
      entityCardId: j['entityCardId'] as String,
      status: j['status'] as String,
    );
  }
}

class IllustrationAcceptPayload {
  final String illustrationId;

  const IllustrationAcceptPayload({required this.illustrationId});

  factory IllustrationAcceptPayload.fromJson(Map<String, dynamic> j) {
    if (j['illustrationId'] is! String ||
        (j['illustrationId'] as String).isEmpty) {
      throw const FormatException('invalid illustration_accept payload');
    }
    return IllustrationAcceptPayload(
      illustrationId: j['illustrationId'] as String,
    );
  }
}

class Proposal {
  final String id, workId, runId, type, payload, status;
  final int createdAt;
  final String? beforeSnapshot, afterSnapshot;
  const Proposal({
    required this.id,
    required this.workId,
    required this.type,
    required this.payload,
    this.runId = '',
    this.status = 'pending',
    this.createdAt = 0,
    this.beforeSnapshot,
    this.afterSnapshot,
  });
  ProposalKind get kind => parseProposalKind(type);
  ProposalStatus get statusValue => parseProposalStatus(status);
  Map<String, dynamic> toJson() => {
    'id': id,
    'workId': workId,
    'runId': runId,
    'type': type,
    'payload': payload,
    'status': status,
    'createdAt': createdAt,
    if (beforeSnapshot != null) 'beforeSnapshot': beforeSnapshot,
    if (afterSnapshot != null) 'afterSnapshot': afterSnapshot,
  };
  factory Proposal.fromJson(Map<String, dynamic> j) => Proposal(
    id: j['id'],
    workId: j['workId'],
    runId: j['runId'] ?? '',
    type: j['type'] ?? '',
    payload: j['payload'] ?? '',
    status: j['status'] ?? 'pending',
    createdAt: j['createdAt'] ?? 0,
    beforeSnapshot: j['beforeSnapshot'] as String?,
    afterSnapshot: j['afterSnapshot'] as String?,
  );
}

class Revision {
  final String id, workId, proposalId, beforeSnapshot, afterSnapshot;
  final int createdAt;
  const Revision({
    required this.id,
    required this.workId,
    required this.proposalId,
    required this.beforeSnapshot,
    required this.afterSnapshot,
    this.createdAt = 0,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'workId': workId,
    'proposalId': proposalId,
    'beforeSnapshot': beforeSnapshot,
    'afterSnapshot': afterSnapshot,
    'createdAt': createdAt,
  };
  factory Revision.fromJson(Map<String, dynamic> j) => Revision(
    id: j['id'],
    workId: j['workId'],
    proposalId: j['proposalId'],
    beforeSnapshot: j['beforeSnapshot'] ?? '',
    afterSnapshot: j['afterSnapshot'] ?? '',
    createdAt: j['createdAt'] ?? 0,
  );
}

class AgentRun {
  final String id, workId, status;
  final int startedAt;
  final int? finishedAt;
  final int inputTokens, outputTokens;

  /// 最近一次 checkpoint 的 JSON（工单 003 §1：每轮落库，H5 冻结后可恢复审计）。
  final String lastCheckpoint;
  const AgentRun({
    required this.id,
    required this.workId,
    this.status = 'running',
    this.startedAt = 0,
    this.finishedAt,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.lastCheckpoint = '',
  });
  AgentRun copyWith({
    String? status,
    int? finishedAt,
    int? inputTokens,
    int? outputTokens,
    String? lastCheckpoint,
  }) => AgentRun(
    id: id,
    workId: workId,
    status: status ?? this.status,
    startedAt: startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    inputTokens: inputTokens ?? this.inputTokens,
    outputTokens: outputTokens ?? this.outputTokens,
    lastCheckpoint: lastCheckpoint ?? this.lastCheckpoint,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'workId': workId,
    'status': status,
    'startedAt': startedAt,
    'finishedAt': finishedAt,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'lastCheckpoint': lastCheckpoint,
  };
  factory AgentRun.fromJson(Map<String, dynamic> j) => AgentRun(
    id: j['id'],
    workId: j['workId'],
    status: j['status'] ?? 'running',
    startedAt: j['startedAt'] ?? 0,
    finishedAt: j['finishedAt'],
    inputTokens: j['inputTokens'] ?? 0,
    outputTokens: j['outputTokens'] ?? 0,
    lastCheckpoint: j['lastCheckpoint'] ?? '',
  );
}

class ToolCall {
  final String id, runId, toolName, inputSummary, resultSummary, status;
  final int startedAt;

  /// 工具 schema 版本与风险分级进入审计记录（工单 003 §3）。
  final int schemaVersion;
  final String risk;
  const ToolCall({
    required this.id,
    required this.runId,
    required this.toolName,
    this.inputSummary = '',
    this.resultSummary = '',
    this.status = 'started',
    this.startedAt = 0,
    this.schemaVersion = 1,
    this.risk = 'read',
  });
  ToolCall copyWith({String? status, String? resultSummary}) => ToolCall(
    id: id,
    runId: runId,
    toolName: toolName,
    inputSummary: inputSummary,
    resultSummary: resultSummary ?? this.resultSummary,
    status: status ?? this.status,
    startedAt: startedAt,
    schemaVersion: schemaVersion,
    risk: risk,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'runId': runId,
    'toolName': toolName,
    'inputSummary': inputSummary,
    'resultSummary': resultSummary,
    'status': status,
    'startedAt': startedAt,
    'schemaVersion': schemaVersion,
    'risk': risk,
  };
  factory ToolCall.fromJson(Map<String, dynamic> j) => ToolCall(
    id: j['id'],
    runId: j['runId'],
    toolName: j['toolName'] ?? '',
    inputSummary: j['inputSummary'] ?? '',
    resultSummary: j['resultSummary'] ?? '',
    status: j['status'] ?? 'started',
    startedAt: j['startedAt'] ?? 0,
    schemaVersion: j['schemaVersion'] ?? 1,
    risk: j['risk'] ?? 'read',
  );
}

enum EntityKind { character, scene, item }

String entityKindLabel(EntityKind kind) => switch (kind) {
  EntityKind.character => '角色',
  EntityKind.scene => '场景',
  EntityKind.item => '物品',
};

EntityKind parseEntityKind(String value) => switch (value) {
  'character' => EntityKind.character,
  'scene' => EntityKind.scene,
  'item' => EntityKind.item,
  _ => EntityKind.character,
};

/// 实体卡：人物/场景/物品描述卡；canon 状态是插图链路的正典资格。
class EntityCard {
  final String id, workId, name, status;
  final EntityKind kind;
  final List<String> aliases;
  final Map<String, String> attributes;
  final String? portraitBlobId;
  final int createdAt;
  const EntityCard({
    required this.id,
    required this.workId,
    required this.name,
    required this.kind,
    this.aliases = const [],
    this.attributes = const {},
    this.status = 'draft',
    this.portraitBlobId,
    this.createdAt = 0,
  });
  bool get isCanon => status == 'canon';
  Map<String, dynamic> toJson() => {
    'id': id,
    'workId': workId,
    'kind': kind.name,
    'name': name,
    'aliases': aliases,
    'attributes': attributes,
    'status': status,
    'portraitBlobId': portraitBlobId,
    'createdAt': createdAt,
  };
  factory EntityCard.fromJson(Map<String, dynamic> j) => EntityCard(
    id: j['id'],
    workId: j['workId'],
    kind: parseEntityKind(j['kind'] as String? ?? 'character'),
    name: j['name'] ?? '',
    aliases: (j['aliases'] as List? ?? const [])
        .map((e) => e as String)
        .toList(),
    attributes: Map<String, String>.from(j['attributes'] as Map? ?? {}),
    status: j['status'] ?? 'draft',
    portraitBlobId: j['portraitBlobId'] as String?,
    createdAt: j['createdAt'] ?? 0,
  );
}

/// 插图：经锚点挂到章节段落（paraIndex 为空表示章节封面位）。
class Illustration {
  final String id, workId, prompt, providerId, model, blobId, status, chapterId;
  final int? paraIndex;
  final List<String> entityCardIds;
  final int createdAt;
  const Illustration({
    required this.id,
    required this.workId,
    required this.prompt,
    required this.providerId,
    required this.model,
    required this.blobId,
    required this.chapterId,
    this.paraIndex,
    this.status = 'draft',
    this.entityCardIds = const [],
    this.createdAt = 0,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'workId': workId,
    'prompt': prompt,
    'providerId': providerId,
    'model': model,
    'blobId': blobId,
    'chapterId': chapterId,
    if (paraIndex != null) 'paraIndex': paraIndex,
    'status': status,
    'entityCardIds': entityCardIds,
    'createdAt': createdAt,
  };
  factory Illustration.fromJson(Map<String, dynamic> j) => Illustration(
    id: j['id'],
    workId: j['workId'],
    prompt: j['prompt'] ?? '',
    providerId: j['providerId'] ?? '',
    model: j['model'] ?? '',
    blobId: j['blobId'] ?? '',
    chapterId: j['chapterId'] ?? '',
    paraIndex: j['paraIndex'] as int?,
    status: j['status'] ?? 'draft',
    entityCardIds: (j['entityCardIds'] as List? ?? const [])
        .map((e) => e as String)
        .toList(),
    createdAt: j['createdAt'] ?? 0,
  );
}

class BlobRec {
  final String id, workId, kind, mime, sha256, storageKey;
  final int byteSize;
  const BlobRec({
    required this.id,
    required this.workId,
    required this.storageKey,
    required this.kind,
    this.mime = 'application/octet-stream',
    this.sha256 = '',
    this.byteSize = 0,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'workId': workId,
    'kind': kind,
    'mime': mime,
    'sha256': sha256,
    'storageKey': storageKey,
    'byteSize': byteSize,
  };
  factory BlobRec.fromJson(Map<String, dynamic> j) => BlobRec(
    id: j['id'],
    workId: j['workId'],
    storageKey: j['storageKey'],
    kind: j['kind'] ?? 'text',
    mime: j['mime'] ?? 'application/octet-stream',
    sha256: j['sha256'] ?? '',
    byteSize: j['byteSize'] ?? 0,
  );
}

class BundleData {
  final Work work;
  final List<Chapter> chapters;
  final Map<String, String> texts;
  final List<Anchor> anchors;
  final List<BlobRec> blobs;
  final List<Prompt> prompts;
  final List<Proposal> proposals;
  final List<AgentRun> runs;
  final List<ToolCall> toolCalls;
  final List<Revision> revisions;
  final List<EntityCard> entityCards;
  final List<Illustration> illustrations;
  const BundleData({
    required this.work,
    this.chapters = const [],
    this.texts = const {},
    this.anchors = const [],
    this.blobs = const [],
    this.prompts = const [],
    this.proposals = const [],
    this.runs = const [],
    this.toolCalls = const [],
    this.revisions = const [],
    this.entityCards = const [],
    this.illustrations = const [],
  });
  Map<String, dynamic> toJson() => {
    'work': work.toJson(),
    'chapters': chapters.map((x) => x.toJson()).toList(),
    'texts': texts,
    'anchors': anchors.map((x) => x.toJson()).toList(),
    'blobs': blobs.map((x) => x.toJson()).toList(),
    'prompts': prompts.map((x) => x.toJson()).toList(),
    'proposals': proposals.map((x) => x.toJson()).toList(),
    'runs': runs.map((x) => x.toJson()).toList(),
    'toolCalls': toolCalls.map((x) => x.toJson()).toList(),
    'revisions': revisions.map((x) => x.toJson()).toList(),
    'entityCards': entityCards.map((x) => x.toJson()).toList(),
    'illustrations': illustrations.map((x) => x.toJson()).toList(),
  };
}

Map<String, dynamic> decodeMap(String s) =>
    jsonDecode(s) as Map<String, dynamic>;
Uint8List utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));
