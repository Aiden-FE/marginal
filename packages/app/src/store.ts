// 全局状态：repository、供应商、当前书、队列。极简 store + useSyncExternalStore。

import { useSyncExternalStore } from "react";
import {
  DemoProvider,
  ProviderClient,
  createDirectAgentGateway,
  createToolAgentGateway,
  TaskQueue,
  uuidv7,
  sha256Hex,
  type ProviderConfig,
  type Repository,
  type Work,
  type WorkSettings,
  type AgentGateway,
  type AgentSkill,
  type TaskKind,
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

/** 内置 Agent skills：每类任务的执行说明；后续可叠加工具与远端 Pi/MCP 适配器。 */
export const AGENT_SKILLS: Record<TaskKind, AgentSkill[]> = {
  repair: [{ id: "clean-suggestions", description: "文本清洗建议（乱码/广告/错字）", systemPrompt: "输出结构化清洗建议 JSON，不改写情节与语气。" }],
  restructure: [{ id: "chapter-boundaries", description: "章节边界识别", systemPrompt: "识别真正的章节标题行，拒绝正文短句、列表编号与日期。" }],
  extract: [{ id: "entity-cards", description: "实体卡提取", systemPrompt: "从正文中提取人物/场景/物品实体卡，输出 JSON。" }],
  illustration: [{ id: "illustration-prompt", description: "插图提示词组装", systemPrompt: "结合正典实体设定组装插图提示词。" }],
};

function readTaskConfig(kind: TaskKind): { providerId: string; model: string; mode: "direct" | "agent" } {
  const demo = { providerId: "demo", model: "demo", mode: "agent" as const };
  try {
    const raw = localStorage.getItem(`marginal.task.${kind}`);
    if (!raw) return demo;
    const parsed = JSON.parse(raw) as { providerId?: string; model?: string; mode?: string };
    return {
      providerId: typeof parsed.providerId === "string" && parsed.providerId ? parsed.providerId : demo.providerId,
      model: typeof parsed.model === "string" && parsed.model ? parsed.model : demo.model,
      mode: parsed.mode === "direct" ? "direct" : "agent", // 旧配置缺省迁移为 agent
    };
  } catch {
    return demo;
  }
}

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

  /** 任务级 Agent 工厂：所有 AI 调用的唯一入口（供应商 transport + skill/tool 网关）。 */
  getAgent(kind: TaskKind, work?: Work): { agent: AgentGateway; model: string; providerId: string } {
    const config = work?.settings.taskConfigs[kind]
      ? {
        providerId: work.settings.taskConfigs[kind]!.providerId,
        model: work.settings.taskConfigs[kind]!.model,
        mode: work.settings.taskConfigs[kind]!.mode === "direct" ? "direct" : "agent",
      }
      : readTaskConfig(kind);
    const transport = this.getClient(config.providerId);
    const options = { skills: AGENT_SKILLS[kind] };
    const agent = config.mode === "direct"
      ? createDirectAgentGateway(transport, options)
      : createToolAgentGateway(transport, options);
    return { agent, model: config.model, providerId: config.providerId };
  }

  defaultTaskConfig(kind: TaskKind): { providerId: string; model: string; mode: "direct" | "agent" } {
    return readTaskConfig(kind);
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
