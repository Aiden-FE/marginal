// SQLite WASM worker：OPFS-sahpool VFS（无需 COOP/COEP 头，research/001 结论）。
// 必须运行在 Worker 内（OPFS 同步句柄仅限 worker）。

/// <reference lib="webworker" />
import sqlite3InitModule from "@sqlite.org/sqlite-wasm";

type SqlValue = string | number | bigint | Uint8Array | null;

interface ExecMsg {
  id: number;
  type: "exec" | "rows";
  sql: string;
  bind?: SqlValue[];
}

let db: any;

async function init(): Promise<void> {
  try {
    const sqlite3 = await (sqlite3InitModule as unknown as (opts: unknown) => Promise<any>)({
      print: () => {},
      printErr: (e: unknown) => console.error("sqlite:", e),
    });
    db = new sqlite3.oo1.DB("opfs-sahpool:/marginal.sqlite3", "ct");
    initSchema();
    postMessage({ ready: true });
  } catch (err) {
    console.error("sqlite worker init failed:", err);
    postMessage({ ready: false, error: err instanceof Error ? `${err.message}\n${err.stack}` : String(err) });
  }
}

function initSchema(): void {
  db.exec(`
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
    CREATE TABLE IF NOT EXISTS bindata(storage_key TEXT PRIMARY KEY, data BLOB);
    CREATE INDEX IF NOT EXISTS idx_chapters_work ON chapters(work_id, idx);
  `);
}

self.onmessage = (ev: MessageEvent<ExecMsg>) => {
  const { id, type, sql, bind } = ev.data;
  try {
    if (type === "exec") {
      if (bind?.length) {
        db.exec({ sql, bind: bind as any[] });
      } else {
        db.exec(sql);
      }
      postMessage({ id });
    } else {
      const rows: Record<string, any>[] = [];
      db.exec({
        sql,
        bind: (bind ?? []) as any[],
        rowMode: "object",
        callback: (row: Record<string, any>) => rows.push(row),
      });
      postMessage({ id, rows });
    }
  } catch (err) {
    postMessage({ id, error: err instanceof Error ? err.message : String(err) });
  }
};

void init();
