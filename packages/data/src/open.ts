// 引擎选择（spec §2/research/001）：
// 桌面(Tauri) → Rust 原生 SQLite（tauri-plugin-sql）
// web → SQLite WASM/OPFS → 不可用时降级 IndexedDB
// 诊断用 URL 参数：?engine=sqlite|indexeddb

import type { Repository } from "@marginal/core";
import { IdbRepository } from "./idb-repository.js";
import { SqliteRepository, TauriSqliteRepository } from "./sqlite-repository.js";

function isTauri(): boolean {
  return typeof window !== "undefined" && !!(window as any).__TAURI_INTERNALS__;
}

export const engineInfo: { reason: string } = { reason: "" };

export async function openRepository(forceEngine?: "sqlite" | "indexeddb"): Promise<Repository> {
  const param = typeof location !== "undefined" ? new URLSearchParams(location.search).get("engine") : null;
  const wanted = forceEngine ?? ((param as "sqlite" | "indexeddb" | null) ?? undefined);

  if (isTauri() && wanted !== "indexeddb") {
    try {
      return await TauriSqliteRepository.create(); // 桌面：Rust 原生 SQLite
    } catch (err) {
      engineInfo.reason = `Tauri SQLite 失败: ${err instanceof Error ? err.message : err}`;
      console.warn(engineInfo.reason, err);
    }
  }

  if (!isTauri() && wanted !== "indexeddb" && (await probeWebSqlite())) {
    try {
      return await SqliteRepository.create();
    } catch (err) {
      engineInfo.reason = `SQLite WASM 失败: ${err instanceof Error ? err.message : err}`;
      console.warn(engineInfo.reason, err);
    }
  }

  const repo = new IdbRepository();
  await repo.init();
  return repo;
}

async function probeWebSqlite(): Promise<boolean> {
  try {
    await SqliteRepository.create();
    return true;
  } catch {
    return false;
  }
}
