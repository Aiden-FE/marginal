// SQLite WASM worker：OPFS-sahpool VFS（无需 COOP/COEP 头，research/001 结论）。
// 必须运行在 Worker 内（OPFS 同步句柄仅限 worker）。建表由 Repository 基类统一执行。

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
    postMessage({ ready: true });
  } catch (err) {
    console.error("sqlite worker init failed:", err);
    postMessage({ ready: false, error: err instanceof Error ? `${err.message}\n${err.stack}` : String(err) });
  }
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
