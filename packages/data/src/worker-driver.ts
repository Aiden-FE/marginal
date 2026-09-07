// web 驱动：sqlite-wasm(opfs-sahpool) Worker RPC。

import type { SqlDriver, SqlValue } from "./sqlite-base.js";

interface Pending {
  resolve: (v: any) => void;
  reject: (e: Error) => void;
}

export class WorkerDriver implements SqlDriver {
  private worker!: Worker;
  private pending = new Map<number, Pending>();
  private seq = 0;

  static async create(timeoutMs = 8000): Promise<WorkerDriver> {
    const d = new WorkerDriver();
    d.worker = new Worker(new URL("./sql-worker.ts", import.meta.url), { type: "module" });
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("sqlite worker 初始化超时")), timeoutMs);
      d.worker.onmessage = (ev: MessageEvent) => {
        const data = ev.data as { ready?: boolean; error?: string };
        if (data.ready) {
          clearTimeout(timer);
          d.worker.onmessage = (e) => d.onMessage(e);
          resolve();
        } else {
          clearTimeout(timer);
          reject(new Error(`sqlite worker 初始化失败: ${data.error ?? "未知错误"}`));
        }
      };
      d.worker.onerror = (e) => {
        clearTimeout(timer);
        reject(new Error(`sqlite worker 加载失败: ${e.message}`));
      };
    });
    return d;
  }

  private onMessage(ev: MessageEvent): void {
    const { id, rows, error } = ev.data as { id: number; rows?: any; error?: string };
    const pending = this.pending.get(id);
    if (!pending) return;
    this.pending.delete(id);
    if (error) pending.reject(new Error(error));
    else pending.resolve(rows);
  }

  exec(sql: string, bind?: SqlValue[]): Promise<void> {
    const id = ++this.seq;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve: () => resolve(), reject });
      this.worker.postMessage({ id, type: "exec", sql, bind });
    });
  }

  rows<T = Record<string, any>>(sql: string, bind?: SqlValue[]): Promise<T[]> {
    const id = ++this.seq;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.worker.postMessage({ id, type: "rows", sql, bind });
    });
  }

  terminate(): void {
    this.worker.terminate();
  }
}
