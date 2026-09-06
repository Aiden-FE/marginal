// 引擎选择（spec §2/research/001）：优先 SQLite WASM/OPFS，不可用降级 IndexedDB。

import type { Repository } from "@marginal/core";
import { IdbRepository } from "./idb-repository.js";
import { SqliteRepository } from "./sqlite-repository.js";

export async function openRepository(forceEngine?: "sqlite" | "indexeddb"): Promise<Repository> {
  // 诊断用：?engine=sqlite|indexeddb 强制指定
  const param = typeof location !== "undefined" ? new URLSearchParams(location.search).get("engine") : null;
  const wanted = forceEngine ?? (param as "sqlite" | "indexeddb" | null) ?? undefined;
  if (wanted !== "indexeddb" && (await SqliteRepository.available())) {
    try {
      const repo = new SqliteRepository();
      await repo.init();
      return repo;
    } catch (err) {
      console.warn("SQLite 引擎初始化失败，降级 IndexedDB", err);
    }
  }
  const repo = new IdbRepository();
  await repo.init();
  return repo;
}
