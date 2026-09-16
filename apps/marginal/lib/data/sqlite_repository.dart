import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../core/bundle.dart';
import '../core/repository.dart';
import '../core/types.dart';

/// 原生 SQLite 驱动（Wayfinder 002 §5 / 工单 005）。
/// schema：UUID 主键、revisions 类只追加语义由 Repository 调用方保证、
/// 章正文与 blob 存 blob 行，anchors 存章内段落索引 + 字符偏移。
class SqliteRepository implements Repository {
  final Database db;
  bool _closed = false;
  int _transactionDepth = 0;

  SqliteRepository(this.db) {
    db.execute('PRAGMA journal_mode = WAL;');
    _migrate();
  }

  int get schemaVersion => 1;

  void _migrate() {
    db.execute(
      'CREATE TABLE IF NOT EXISTS works(id TEXT PRIMARY KEY, json TEXT NOT NULL, updated_at INTEGER NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS chapters(id TEXT PRIMARY KEY, work_id TEXT NOT NULL, idx INTEGER NOT NULL, json TEXT NOT NULL, text TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS anchors(id TEXT PRIMARY KEY, work_id TEXT NOT NULL, json TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS prompts(id TEXT PRIMARY KEY, work_id TEXT NOT NULL, json TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS proposals(id TEXT PRIMARY KEY, work_id TEXT NOT NULL, json TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS revisions(id TEXT PRIMARY KEY, work_id TEXT NOT NULL, json TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS agent_runs(id TEXT PRIMARY KEY, work_id TEXT NOT NULL, json TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS repair_runs(id TEXT PRIMARY KEY, work_id TEXT NOT NULL, json TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS repair_jobs(id TEXT PRIMARY KEY, work_id TEXT NOT NULL, json TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS tool_calls(id TEXT PRIMARY KEY, run_id TEXT NOT NULL, json TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS blobs(id TEXT PRIMARY KEY, work_id TEXT NOT NULL, storage_key TEXT NOT NULL, json TEXT NOT NULL, data BLOB NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS entity_cards(id TEXT PRIMARY KEY, work_id TEXT NOT NULL, json TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS illustrations(id TEXT PRIMARY KEY, work_id TEXT NOT NULL, json TEXT NOT NULL)',
    );
  }

  @override
  String get engine => 'sqlite';

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) async {
    if (_transactionDepth > 0) return action();
    db.execute('BEGIN');
    _transactionDepth++;
    try {
      final result = await action();
      db.execute('COMMIT');
      return result;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      _transactionDepth--;
    }
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> close() async {
    if (!_closed) {
      db.dispose();
      _closed = true;
    }
  }

  @override
  Future<void> putWork(Work value) async => db.execute(
    'INSERT INTO works(id,json,updated_at) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET json=excluded.json, updated_at=excluded.updated_at',
    [value.id, _enc(value.toJson()), value.updatedAt],
  );

  @override
  Future<List<Work>> listWorks() async => db
      .select('SELECT json FROM works ORDER BY updated_at DESC')
      .map((r) => Work.fromJson(_dec(r['json'] as String)))
      .toList();

  @override
  Future<Work?> getWork(String id) async {
    final rows = db.select('SELECT json FROM works WHERE id=?', [id]);
    return rows.isEmpty
        ? null
        : Work.fromJson(_dec(rows.first['json'] as String));
  }

  void _deleteWorkSync(String id) {
    db.execute(
      'DELETE FROM tool_calls WHERE run_id IN (SELECT id FROM agent_runs WHERE work_id=?)',
      [id],
    );
    for (final table in [
      'chapters',
      'anchors',
      'prompts',
      'proposals',
      'revisions',
      'entity_cards',
      'illustrations',
      'agent_runs',
      'repair_runs',
      'repair_jobs',
      'blobs',
    ]) {
      db.execute('DELETE FROM $table WHERE work_id=?', [id]);
    }
    db.execute('DELETE FROM works WHERE id=?', [id]);
  }

  @override
  Future<void> deleteWork(String id) async {
    final outermost = _transactionDepth == 0;
    if (outermost) db.execute('BEGIN');
    try {
      _deleteWorkSync(id);
      if (outermost) db.execute('COMMIT');
    } catch (_) {
      if (outermost) db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<List<Chapter>> listChapters(String workId) async => db
      .select('SELECT json FROM chapters WHERE work_id=? ORDER BY idx', [
        workId,
      ])
      .map((r) => Chapter.fromJson(_dec(r['json'] as String)))
      .toList();

  @override
  Future<String> getChapterText(String chapterId) async {
    final rows = db.select('SELECT text FROM chapters WHERE id=?', [chapterId]);
    return rows.isEmpty ? '' : rows.first['text'] as String;
  }

  @override
  Future<String> readChapterRange(
    String chapterId,
    int start,
    int length,
  ) async {
    final safeStart = start.clamp(0, 1 << 30);
    final safeLength = length.clamp(0, 1 << 30);
    final rows = db.select(
      'SELECT substr(text, ?, ?) AS chunk FROM chapters WHERE id=?',
      [safeStart + 1, safeLength, chapterId],
    );
    return rows.isEmpty ? '' : rows.first['chunk'] as String? ?? '';
  }

  @override
  Future<void> putChapter(String workId, Chapter chapter, String text) async {
    if (chapter.workId != workId) throw ArgumentError('workId mismatch');
    db.execute(
      'INSERT INTO chapters(id,work_id,idx,json,text) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET work_id=excluded.work_id,idx=excluded.idx,json=excluded.json,text=excluded.text',
      [chapter.id, workId, chapter.idx, _enc(chapter.toJson()), text],
    );
  }

  @override
  Future<void> replaceChapters(
    String workId,
    List<MapEntry<Chapter, String>> chapters,
  ) async {
    final outermost = _transactionDepth == 0;
    if (outermost) db.execute('BEGIN');
    try {
      await deleteChapters(workId);
      for (final entry in chapters) {
        await putChapter(workId, entry.key, entry.value);
      }
      if (outermost) db.execute('COMMIT');
    } catch (_) {
      if (outermost) db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> deleteChapters(String workId) async {
    db.execute('DELETE FROM chapters WHERE work_id=?', [workId]);
  }

  @override
  Future<List<Anchor>> listAnchors(String workId) async => db
      .select('SELECT json FROM anchors WHERE work_id=?', [workId])
      .map((r) => Anchor.fromJson(_dec(r['json'] as String)))
      .toList();

  @override
  Future<void> putAnchor(Anchor value) async => db.execute(
    'INSERT INTO anchors(id,work_id,json) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET work_id=excluded.work_id,json=excluded.json',
    [value.id, value.workId, _enc(value.toJson())],
  );

  @override
  Future<void> deleteAnchor(String id) async =>
      db.execute('DELETE FROM anchors WHERE id=?', [id]);

  @override
  Future<void> remapAnchors(String workId, List<Anchor> values) async {
    final outermost = _transactionDepth == 0;
    if (outermost) db.execute('BEGIN');
    try {
      db.execute('DELETE FROM anchors WHERE work_id=?', [workId]);
      for (final value in values) {
        if (value.workId == workId) await putAnchor(value);
      }
      if (outermost) db.execute('COMMIT');
    } catch (_) {
      if (outermost) db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<List<T>> _list<T>(
    String table,
    String workId,
    T Function(String) decode,
  ) async => db
      .select('SELECT json FROM $table WHERE work_id=?', [workId])
      .map((r) => decode(r['json'] as String))
      .toList();

  @override
  Future<List<Prompt>> listPrompts(String workId) =>
      _list('prompts', workId, (s) => Prompt.fromJson(_dec(s)));
  @override
  Future<void> putPrompt(Prompt value) async => db.execute(
    'INSERT INTO prompts(id,work_id,json) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET work_id=excluded.work_id,json=excluded.json',
    [value.id, value.workId, _enc(value.toJson())],
  );
  @override
  Future<List<Proposal>> listProposals(String workId) =>
      _list('proposals', workId, (s) => Proposal.fromJson(_dec(s)));
  @override
  Future<void> putProposal(Proposal value) async => db.execute(
    'INSERT INTO proposals(id,work_id,json) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET work_id=excluded.work_id,json=excluded.json',
    [value.id, value.workId, _enc(value.toJson())],
  );
  @override
  Future<void> updateProposal(Proposal value) async {
    db.execute('UPDATE proposals SET work_id=?,json=? WHERE id=?', [
      value.workId,
      _enc(value.toJson()),
      value.id,
    ]);
    if (db.updatedRows == 0) throw StateError('proposal not found');
  }

  @override
  Future<List<Revision>> listRevisions(String workId) =>
      _list('revisions', workId, (s) => Revision.fromJson(_dec(s)));
  @override
  Future<void> putRevision(Revision value) async => db.execute(
    'INSERT INTO revisions(id,work_id,json) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET work_id=excluded.work_id,json=excluded.json',
    [value.id, value.workId, _enc(value.toJson())],
  );

  @override
  Future<List<EntityCard>> listEntityCards(String workId) =>
      _list('entity_cards', workId, (s) => EntityCard.fromJson(_dec(s)));
  @override
  Future<void> putEntityCard(EntityCard value) async => db.execute(
    'INSERT INTO entity_cards(id,work_id,json) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET work_id=excluded.work_id,json=excluded.json',
    [value.id, value.workId, _enc(value.toJson())],
  );
  @override
  Future<void> deleteEntityCard(String id) async {
    final outermost = _transactionDepth == 0;
    if (outermost) db.execute('BEGIN');
    try {
      db.execute('DELETE FROM entity_cards WHERE id=?', [id]);
      final rows = db.select('SELECT json FROM illustrations');
      for (final row in rows) {
        final illustration = Illustration.fromJson(_dec(row['json'] as String));
        if (!illustration.entityCardIds.contains(id)) continue;
        await putIllustration(
          Illustration(
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
          ),
        );
      }
      if (outermost) db.execute('COMMIT');
    } catch (_) {
      if (outermost) db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<List<Illustration>> listIllustrations(String workId) =>
      _list('illustrations', workId, (s) => Illustration.fromJson(_dec(s)));
  @override
  Future<void> putIllustration(Illustration value) async => db.execute(
    'INSERT INTO illustrations(id,work_id,json) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET work_id=excluded.work_id,json=excluded.json',
    [value.id, value.workId, _enc(value.toJson())],
  );
  @override
  Future<void> deleteIllustration(String id) async =>
      db.execute('DELETE FROM illustrations WHERE id=?', [id]);

  @override
  Future<List<AgentRun>> listAgentRuns(String workId) =>
      _list('agent_runs', workId, (s) => AgentRun.fromJson(_dec(s)));
  @override
  Future<void> putAgentRun(AgentRun value) async => db.execute(
    'INSERT INTO agent_runs(id,work_id,json) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET work_id=excluded.work_id,json=excluded.json',
    [value.id, value.workId, _enc(value.toJson())],
  );
  @override
  Future<List<RepairRun>> listRepairRuns(String workId) =>
      _list('repair_runs', workId, (s) => RepairRun.fromJson(_dec(s)));
  @override
  Future<void> putRepairRun(RepairRun value) async => db.execute(
    'INSERT INTO repair_runs(id,work_id,json) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET work_id=excluded.work_id,json=excluded.json',
    [value.id, value.workId, _enc(value.toJson())],
  );
  @override
  Future<List<RepairJob>> listRepairJobs(String workId) =>
      _list('repair_jobs', workId, (s) => RepairJob.fromJson(_dec(s)));
  @override
  Future<void> putRepairJob(RepairJob value) async => db.execute(
    'INSERT INTO repair_jobs(id,work_id,json) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET work_id=excluded.work_id,json=excluded.json',
    [value.id, value.workId, _enc(value.toJson())],
  );
  @override
  Future<List<ToolCall>> listToolCalls(String runId) async => db
      .select('SELECT json FROM tool_calls WHERE run_id=?', [runId])
      .map((r) => ToolCall.fromJson(_dec(r['json'] as String)))
      .toList();
  @override
  Future<void> putToolCall(ToolCall value) async => db.execute(
    'INSERT INTO tool_calls(id,run_id,json) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET run_id=excluded.run_id,json=excluded.json',
    [value.id, value.runId, _enc(value.toJson())],
  );

  @override
  Future<void> putBlob(BlobRec blob, Uint8List data) async => db.execute(
    'INSERT INTO blobs(id,work_id,storage_key,json,data) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET work_id=excluded.work_id,storage_key=excluded.storage_key,json=excluded.json,data=excluded.data',
    [blob.id, blob.workId, blob.storageKey, _enc(blob.toJson()), data],
  );
  @override
  Future<Uint8List?> getBlobData(String storageKey) async {
    final rows = db.select('SELECT data FROM blobs WHERE storage_key=?', [
      storageKey,
    ]);
    return rows.isEmpty
        ? null
        : Uint8List.fromList(List<int>.from(rows.first['data'] as List));
  }

  @override
  Future<List<BlobRec>> listBlobs(String workId) =>
      _list('blobs', workId, (s) => BlobRec.fromJson(_dec(s)));

  @override
  Future<BundleData> exportAll(String workId) async {
    final work = await getWork(workId);
    if (work == null) throw StateError('work not found');
    final chapters = await listChapters(workId);
    final runs = await listAgentRuns(workId);
    final repairRuns = await listRepairRuns(workId);
    final repairJobs = await listRepairJobs(workId);
    return BundleData(
      work: work,
      chapters: chapters,
      texts: {for (final c in chapters) c.id: await getChapterText(c.id)},
      anchors: await listAnchors(workId),
      blobs: await listBlobs(workId),
      prompts: await listPrompts(workId),
      proposals: await listProposals(workId),
      revisions: await listRevisions(workId),
      entityCards: await listEntityCards(workId),
      illustrations: await listIllustrations(workId),
      runs: runs,
      repairRuns: repairRuns,
      repairJobs: repairJobs,
      toolCalls: [for (final r in runs) ...await listToolCalls(r.id)],
    );
  }

  @override
  Future<void> importBundle(
    BundleData data, {
    required bool copy,
    Map<String, Uint8List> blobData = const {},
  }) async {
    final payload = copy ? reidForCopy(data) : data;
    final outermost = _transactionDepth == 0;
    if (outermost) db.execute('BEGIN');
    try {
      if (!copy) _deleteWorkSync(payload.work.id);
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
      for (final r in payload.revisions) {
        await putRevision(r);
      }
      for (final c in payload.entityCards) {
        await putEntityCard(c);
      }
      for (final i in payload.illustrations) {
        await putIllustration(i);
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
      if (outermost) db.execute('COMMIT');
    } catch (_) {
      if (outermost) db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> wipe() async {
    final outermost = _transactionDepth == 0;
    if (outermost) db.execute('BEGIN');
    try {
      for (final table in [
        'tool_calls',
        'agent_runs',
        'repair_runs',
        'repair_jobs',
        'proposals',
        'revisions',
        'entity_cards',
        'illustrations',
        'prompts',
        'anchors',
        'chapters',
        'blobs',
        'works',
      ]) {
        db.execute('DELETE FROM $table');
      }
      if (outermost) db.execute('COMMIT');
    } catch (_) {
      if (outermost) db.execute('ROLLBACK');
      rethrow;
    }
  }

  static String _enc(Map<String, dynamic> json) => jsonEncode(json);
  static Map<String, dynamic> _dec(String raw) =>
      Map<String, dynamic>.from(jsonDecode(raw));
}
