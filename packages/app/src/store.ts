// 全局状态：repository、供应商、当前书、队列。极简 store + useSyncExternalStore。

import { useSyncExternalStore } from "react";
import {
  DemoProvider,
  ProviderClient,
  TaskQueue,
  uuidv7,
  sha256Hex,
  type ProviderConfig,
  type Repository,
  type Work,
  type WorkSettings,
} from "@marginal/core";
import { openRepository, engineInfo } from "@marginal/data";

export type View =
  | { name: "library" }
  | { name: "work"; workId: string; tab: "reader" | "repair" | "entities" | "illustrations" }
  | { name: "settings" };

export interface ProviderEntry extends ProviderConfig {
  kind: "demo" | "openai";
}

const PROVIDERS_KEY = "marginal.providers.v1";

function defaultSettings(): WorkSettings {
  return { taskConfigs: {}, autoNormalize: false, budgetLimit: 0 };
}

class Store {
  repo!: Repository;
  engine = "";
  works: Work[] = [];
  view: View = { name: "library" };
  providers: ProviderEntry[] = [Object.assign(new DemoProvider(), { kind: "demo" as const })];
  queue = new TaskQueue(2, 3, {
    onTaskDone: () => this.emit(),
    onTaskFailed: () => this.emit(),
    onBudgetExceeded: () => this.emit(),
  });
  toast = "";
  ready = false;
  initError = "";

  private listeners = new Set<() => void>();
  private version = 0;

  subscribe = (cb: () => void) => {
    this.listeners.add(cb);
    return () => this.listeners.delete(cb);
  };
  getSnapshot = () => this.version;
  emit(): void {
    this.version++;
    for (const l of this.listeners) l();
  }
  notify(msg: string): void {
    this.toast = msg;
    this.emit();
    setTimeout(() => {
      if (this.toast === msg) {
        this.toast = "";
        this.emit();
      }
    }, 2600);
  }

  async init(): Promise<void> {
    this.repo = await openRepository();
    this.engine = this.repo.engine + (engineInfo.reason ? `（降级：${engineInfo.reason}）` : "");
    await this.repo.init();
    const saved = localStorage.getItem(PROVIDERS_KEY);
    if (saved) {
      try {
        const custom = JSON.parse(saved) as ProviderEntry[];
        this.providers = [...this.providers, ...custom.filter((p) => p.kind === "openai")];
      } catch {
        // ignore
      }
    }
    await this.refreshWorks();
  }

  async refreshWorks(): Promise<void> {
    this.works = await this.repo.listWorks();
    this.emit();
  }

  saveProviders(): void {
    localStorage.setItem(PROVIDERS_KEY, JSON.stringify(this.providers.filter((p) => p.kind === "openai")));
  }

  getClient(providerId: string): ProviderClient | DemoProvider {
    const entry = this.providers.find((p) => p.id === providerId) ?? this.providers[0];
    if (entry.kind === "demo") return new DemoProvider();
    globalThis.__marginalApiKey = entry.apiKey;
    return new ProviderClient(entry);
  }

  defaultTaskConfig(kind: Work["settings"]["taskConfigs"] extends infer _T ? string : never): { providerId: string; model: string } {
    const demo = { providerId: "demo", model: "demo" };
    if (kind === "illustration") return (localStorage.getItem("marginal.task.illustration") && JSON.parse(localStorage.getItem("marginal.task.illustration")!)) || demo;
    if (kind === "extract") return (localStorage.getItem("marginal.task.extract") && JSON.parse(localStorage.getItem("marginal.task.extract")!)) || demo;
    return (localStorage.getItem("marginal.task.repair") && JSON.parse(localStorage.getItem("marginal.task.repair")!)) || demo;
  }

  navigate(view: View): void {
    this.view = view;
    this.emit();
  }

  async createWorkFromText(title: string, filename: string, text: string, chapters: { title: string; text: string }[]): Promise<Work> {
    const now = Date.now();
    const work: Work = {
      id: uuidv7(),
      title,
      author: "",
      importSource: filename,
      createdAt: now,
      updatedAt: now,
      settings: defaultSettings(),
    };
    await this.repo.putWork(work);
    for (let i = 0; i < chapters.length; i++) {
      const hash = await sha256Hex(new TextEncoder().encode(chapters[i].text));
      await this.repo.putChapter(work.id, {
        id: uuidv7(),
        workId: work.id,
        idx: i,
        title: chapters[i].title,
        wordCount: chapters[i].text.length,
        contentHash: hash,
      }, chapters[i].text);
    }
    await this.refreshWorks();
    return work;
  }

  async deleteWork(id: string): Promise<void> {
    await this.repo.deleteWork(id);
    if (this.view.name === "work" && this.view.workId === id) this.view = { name: "library" };
    await this.refreshWorks();
  }

  async updateWork(work: Work): Promise<void> {
    work.updatedAt = Date.now();
    await this.repo.putWork(work);
    await this.refreshWorks();
  }
}

function decodeText(buf: ArrayBuffer): string {
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(buf);
  } catch {
    return new TextDecoder("gbk").decode(buf); // GBK 回退（spec §4.1）
  }
}

export { decodeText };
export const store = new Store();
// 调试钩子
declare global {
  interface Window { __store?: Store }
}
window.__store = store;
export function useStore(): number {
  return useSyncExternalStore(store.subscribe, store.getSnapshot);
}
