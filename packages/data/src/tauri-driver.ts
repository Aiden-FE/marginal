// 桌面(Tauri)驱动：经 tauri-plugin-sql 走 Rust 侧原生 rusqlite（spec §2 桌面壳层）。
// 动态 import，web 构建不含此路径。

import type { SqlDriver, SqlValue } from "./sqlite-base.js";

interface PluginDb {
  execute(sql: string, bind?: unknown[]): Promise<number>;
  select<T>(sql: string, bind?: unknown[]): Promise<T[]>;
}

interface DatabaseClass {
  load(connString: string): Promise<PluginDb>;
}

export class TauriSqlDriver implements SqlDriver {
  private constructor(private db: PluginDb) {}

  static async create(path = "marginal.db"): Promise<TauriSqlDriver> {
    if (!(window as any).__TAURI_INTERNALS__) {
      throw new Error("非 Tauri 环境");
    }
    const mod = await import("@tauri-apps/plugin-sql");
    const Database = mod.default as unknown as DatabaseClass;
    const db = await Database.load(`sqlite:${path}`);
    return new TauriSqlDriver(db);
  }

  async exec(sql: string, bind?: SqlValue[]): Promise<void> {
    const params = (bind ?? []).map(toPluginParam);
    await this.db.execute(sql, params);
  }

  async rows<T = Record<string, any>>(sql: string, bind?: SqlValue[]): Promise<T[]> {
    const params = (bind ?? []).map(toPluginParam);
    return this.db.select<T>(sql, params) as unknown as Promise<T[]>;
  }
}

/** Uint8Array → base64（bindata 已统一 base64 TEXT；其余值直传） */
function toPluginParam(v: SqlValue): unknown {
  if (v instanceof Uint8Array) {
    let bin = "";
    for (let i = 0; i < v.length; i += 0x8000) bin += String.fromCharCode(...v.subarray(i, i + 0x8000));
    return btoa(bin);
  }
  return v;
}
