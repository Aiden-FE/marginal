// SQL 驱动抽象 + SQLite Repository 基类（spec §3：结构化元数据进 SQLite）。
// 驱动实现：web = sqlite-wasm Worker；桌面(Tauri) = tauri-plugin-sql（Rust 原生 rusqlite）。

import type {
  Anchor,
  BlobRec,
  Chapter,
  EntityCard,
  Illustration,
  RepairRun,
  Repository,
  Revision,
  Work,
} from "@marginal/core";
import type { BundlePayload } from "@marginal/core";

export interface SqlDriver {
  exec(sql: string, bind?: SqlValue[]): Promise<void>;
  rows<T = Record<string, any>>(sql: string, bind?: SqlValue[]): Promise<T[]>;
}

export type SqlValue = string | number | bigint | Uint8Array | null;

const SCHEMA = `
    CREATE TABLE IF NOT EXISTS works(
      id TEXT PRIMARY KEY, title TEXT, author TEXT, import_source TEXT,
      created_at INTEGER, updated_at INTEGER, settings TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS chapters(
      id TEXT PRIMARY KEY, work_id TEXT NOT NULL, idx INTEGER, title TEXT,
      word_count INTEGER, content_hash TEXT
    );
    CREATE TABLE IF NOT EXISTS chapter_texts(chapter_id TEXT PRIMARY KEY, text TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS runs(
      id TEXT PRIMARY KEY, work_id TEXT NOT NULL, payload TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS revisions(
      id TEXT PRIMARY KEY, work_id TEXT NOT NULL, chapter_id TEXT,
      run_id TEXT, kind TEXT, payload TEXT NOT NULL, created_at INTEGER
    );
    CREATE TABLE IF NOT EXISTS entity_cards(
      id TEXT PRIMARY KEY, work_id TEXT NOT NULL, payload TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS illustrations(
      id TEXT PRIMARY KEY, work_id TEXT NOT NULL, payload TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS anchors(
      id TEXT PRIMARY KEY, work_id TEXT NOT NULL, payload TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS blobs(
      id TEXT PRIMARY KEY, work_id TEXT NOT NULL, storage_key TEXT NOT NULL, payload TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS bindata(storage_key TEXT PRIMARY KEY, data TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS idx_chapters_work ON chapters(work_id, idx);
`;

/** 二进制统一以 base64 TEXT 存 bindata（三引擎语义一致；spec §3 blobs 走文件/OPFS 的部分不受影响） */
function toBase64(data: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < data.length; i += 0x8000) bin += String.fromCharCode(...data.subarray(i, i + 0x8000));
  return btoa(bin);
}
function fromBase64(s: string): Uint8Array {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export class SqliteRepositoryBase implements Repository {
  constructor(protected driver: SqlDriver, readonly engine: string) {}

  async init(): Promise<void> {
    for (const stmt of SCHEMA.split(";").map((s) => s.trim()).filter(Boolean)) {
      await this.driver.exec(stmt);
    }
  }

  async close(): Promise<void> {
    // 各驱动自行决定
  }

  private static rowToWork(r: Record<string, any>): Work {
    return {
      id: r.id,
      title: r.title,
      author: r.author,
      importSource: r.import_source,
      createdAt: r.created_at,
      updatedAt: r.updated_at,
      settings: JSON.parse(r.settings),
    };
  }

  async listWorks(): Promise<Work[]> {
    const rs = await this.driver.rows(`SELECT * FROM works ORDER BY updated_at DESC`);
    return rs.map(SqliteRepositoryBase.rowToWork);
  }
  async getWork(id: string): Promise<Work | null> {
    const rs = await this.driver.rows(`SELECT * FROM works WHERE id = ?`, [id]);
    return rs.length ? SqliteRepositoryBase.rowToWork(rs[0]) : null;
  }
  async putWork(w: Work): Promise<void> {
    await this.driver.exec(
      `INSERT INTO works(id,title,author,import_source,created_at,updated_at,settings) VALUES(?,?,?,?,?,?,?)
       ON CONFLICT(id) DO UPDATE SET title=excluded.title, author=excluded.author, updated_at=excluded.updated_at, settings=excluded.settings`,
      [w.id, w.title, w.author, w.importSource, w.createdAt, w.updatedAt, JSON.stringify(w.settings)],
    );
  }
  async deleteWork(id: string): Promise<void> {
    await this.driver.exec(`DELETE FROM works WHERE id = ?`, [id]);
    await this.driver.exec(`DELETE FROM chapters WHERE work_id = ?`, [id]);
    await this.driver.exec(`DELETE FROM chapter_texts WHERE chapter_id NOT IN (SELECT id FROM chapters)`);
    for (const table of ["runs", "revisions", "entity_cards", "illustrations", "anchors", "blobs"]) {
      await this.driver.exec(`DELETE FROM ${table} WHERE work_id = ?`, [id]);
    }
    await this.driver.exec(`DELETE FROM bindata WHERE storage_key LIKE ?`, [`${id}/%`]);
  }

  async listChapters(workId: string): Promise<Chapter[]> {
    const rs = await this.driver.rows(`SELECT * FROM chapters WHERE work_id = ? ORDER BY idx`, [workId]);
    return rs.map((r) => ({ id: r.id, workId: r.work_id, idx: r.idx, title: r.title, wordCount: r.word_count, contentHash: r.content_hash }));
  }
  async getChapterText(chapterId: string): Promise<string> {
    const rs = await this.driver.rows(`SELECT text FROM chapter_texts WHERE chapter_id = ?`, [chapterId]);
    return rs.length ? (rs[0].text as string) : "";
  }
  async putChapter(workId: string, chapter: Chapter, text: string): Promise<void> {
    await this.driver.exec(
      `INSERT INTO chapters(id,work_id,idx,title,word_count,content_hash) VALUES(?,?,?,?,?,?)
       ON CONFLICT(id) DO UPDATE SET idx=excluded.idx, title=excluded.title, word_count=excluded.word_count, content_hash=excluded.content_hash`,
      [chapter.id, workId, chapter.idx, chapter.title, chapter.wordCount, chapter.contentHash],
    );
    await this.driver.exec(`INSERT INTO chapter_texts(chapter_id,text) VALUES(?,?) ON CONFLICT(chapter_id) DO UPDATE SET text=excluded.text`, [chapter.id, text]);
  }
  async replaceChapters(workId: string, chapters: { chapter: Chapter; text: string }[]): Promise<void> {
    await this.driver.exec(`DELETE FROM chapters WHERE work_id = ?`, [workId]);
    await this.driver.exec(`DELETE FROM chapter_texts WHERE chapter_id NOT IN (SELECT id FROM chapters)`);
    for (const { chapter, text } of chapters) await this.putChapter(workId, chapter, text);
  }
  async deleteChapters(workId: string): Promise<void> {
    await this.replaceChapters(workId, []);
  }

  async putRun(run: RepairRun): Promise<void> {
    await this.driver.exec(`INSERT INTO runs(id,work_id,payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload`, [run.id, run.workId, JSON.stringify(run)]);
  }
  async listRuns(workId: string): Promise<RepairRun[]> {
    const rs = await this.driver.rows(`SELECT payload FROM runs WHERE work_id = ?`, [workId]);
    return rs.map((r) => JSON.parse(r.payload));
  }
  async putRevision(r: Revision): Promise<void> {
    await this.driver.exec(
      `INSERT INTO revisions(id,work_id,chapter_id,run_id,kind,payload,created_at) VALUES(?,?,?,?,?,?,?)
       ON CONFLICT(id) DO UPDATE SET payload=excluded.payload`,
      [r.id, r.workId, r.chapterId, r.runId, r.kind, JSON.stringify(r.payload), r.createdAt],
    );
  }
  async updateRevision(r: Revision): Promise<void> {
    await this.putRevision(r);
  }
  async listRevisions(workId: string): Promise<Revision[]> {
    const rs = await this.driver.rows(`SELECT payload FROM revisions WHERE work_id = ? ORDER BY created_at`, [workId]);
    return rs.map((r) => JSON.parse(r.payload));
  }

  async listEntityCards(workId: string): Promise<EntityCard[]> {
    const rs = await this.driver.rows(`SELECT payload FROM entity_cards WHERE work_id = ?`, [workId]);
    return rs.map((r) => JSON.parse(r.payload));
  }
  async putEntityCard(c: EntityCard): Promise<void> {
    await this.driver.exec(`INSERT INTO entity_cards(id,work_id,payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload`, [c.id, c.workId, JSON.stringify(c)]);
  }
  async deleteEntityCard(id: string): Promise<void> {
    await this.driver.exec(`DELETE FROM entity_cards WHERE id = ?`, [id]);
  }

  async listIllustrations(workId: string): Promise<Illustration[]> {
    const rs = await this.driver.rows(`SELECT payload FROM illustrations WHERE work_id = ?`, [workId]);
    return rs.map((r) => JSON.parse(r.payload));
  }
  async putIllustration(i: Illustration): Promise<void> {
    await this.driver.exec(`INSERT INTO illustrations(id,work_id,payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload`, [i.id, i.workId, JSON.stringify(i)]);
  }
  async listAnchors(workId: string): Promise<Anchor[]> {
    const rs = await this.driver.rows(`SELECT payload FROM anchors WHERE work_id = ?`, [workId]);
    return rs.map((r) => JSON.parse(r.payload));
  }
  async putAnchor(a: Anchor): Promise<void> {
    await this.driver.exec(`INSERT INTO anchors(id,work_id,payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload`, [a.id, a.workId, JSON.stringify(a)]);
  }
  async deleteAnchor(id: string): Promise<void> {
    await this.driver.exec(`DELETE FROM anchors WHERE id = ?`, [id]);
  }
  async remapAnchors(workId: string, remaps: { id: string; chapterId?: string; paraIndex?: number; charOffset?: number; state?: "active" | "orphaned" }[]): Promise<void> {
    const all = await this.listAnchors(workId);
    const byId = new Map(all.map((a) => [a.id, a]));
    for (const r of remaps) {
      const a = byId.get(r.id);
      if (a) await this.putAnchor({ ...a, ...r });
    }
  }

  async putBlob(blob: BlobRec, data: Uint8Array): Promise<void> {
    await this.driver.exec(`INSERT INTO blobs(id,work_id,storage_key,payload) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload, storage_key=excluded.storage_key`, [blob.id, blob.workId, blob.storageKey, JSON.stringify(blob)]);
    await this.driver.exec(`INSERT INTO bindata(storage_key,data) VALUES(?,?) ON CONFLICT(storage_key) DO UPDATE SET data=excluded.data`, [blob.storageKey, toBase64(data)]);
  }
  async getBlobData(storageKey: string): Promise<Uint8Array | null> {
    const rs = await this.driver.rows(`SELECT data FROM bindata WHERE storage_key = ?`, [storageKey]);
    return rs.length ? fromBase64(rs[0].data as string) : null;
  }
  async listBlobs(workId: string): Promise<BlobRec[]> {
    const rs = await this.driver.rows(`SELECT payload FROM blobs WHERE work_id = ?`, [workId]);
    return rs.map((r) => JSON.parse(r.payload));
  }

  async exportAll(): Promise<{ works: Work[]; blobData: Record<string, Uint8Array> }> {
    const works = await this.listWorks();
    const rs = await this.driver.rows(`SELECT storage_key, data FROM bindata`);
    const blobData: Record<string, Uint8Array> = {};
    for (const r of rs) blobData[r.storage_key as string] = fromBase64(r.data as string);
    return { works, blobData };
  }

  async importBundle(payload: BundlePayload, blobData: Record<string, Uint8Array>, mode: "replace" | "copy", existingWorkIds: string[]): Promise<void> {
    void existingWorkIds;
    if (mode === "replace") await this.deleteWork(payload.work.id);
    await this.putWork(payload.work);
    for (const c of payload.chapters) await this.putChapter(payload.work.id, c, payload.chapterTexts[c.id] ?? "");
    for (const r of payload.runs) await this.putRun(r);
    for (const r of payload.revisions) await this.putRevision(r);
    for (const c of payload.entityCards) await this.putEntityCard(c);
    for (const i of payload.illustrations) await this.putIllustration(i);
    for (const a of payload.anchors) await this.putAnchor(a);
    for (const b of payload.blobs) {
      const data = blobData[b.storageKey] ?? blobData[b.id];
      if (data) await this.putBlob(b, data);
    }
  }

  async wipe(): Promise<void> {
    for (const table of ["works", "chapters", "chapter_texts", "runs", "revisions", "entity_cards", "illustrations", "anchors", "blobs", "bindata"]) {
      await this.driver.exec(`DELETE FROM ${table}`);
    }
  }
}
