// SQLite Repository：web（wasm worker）与桌面（Tauri 原生）两个薄壳。

import { SqliteRepositoryBase } from "./sqlite-base.js";
import { WorkerDriver } from "./worker-driver.js";
import { TauriSqlDriver } from "./tauri-driver.js";

export class SqliteRepository extends SqliteRepositoryBase {
  private constructor(driver: WorkerDriver) {
    super(driver, "sqlite-wasm/opfs-sahpool");
  }

  static async create(): Promise<SqliteRepository> {
    const driver = await WorkerDriver.create();
    const repo = new SqliteRepository(driver);
    await repo.init();
    return repo;
  }

  async close(): Promise<void> {
    (this.driver as WorkerDriver).terminate();
  }
}

export class TauriSqliteRepository extends SqliteRepositoryBase {
  private constructor(driver: TauriSqlDriver) {
    super(driver, "sqlite/tauri-plugin-sql");
  }

  static async create(): Promise<TauriSqliteRepository> {
    const driver = await TauriSqlDriver.create();
    const repo = new TauriSqliteRepository(driver);
    await repo.init();
    return repo;
  }
}
