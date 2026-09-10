// 领域类型 —— 与 docs/SPEC.md §3 一一对应。主键 UUIDv7，历史只追加。

export interface Work {
  id: string;
  title: string;
  author: string;
  importSource: string;
  createdAt: number;
  updatedAt: number;
  settings: WorkSettings;
}

export interface WorkSettings {
  /** 每任务类型的 provider/model 配置（spec §4.5） */
  taskConfigs: Partial<Record<TaskKind, TaskConfig>>;
  /** 无语义变化规范化是否自动应用，默认关闭（spec §4.2） */
  autoNormalize: boolean;
  /** 每本书预算上限（调用次数），触顶暂停（spec §4.6） */
  budgetLimit: number;
}

export type TaskKind = "repair" | "restructure" | "extract" | "illustration";

export interface TaskConfig {
  providerId: string;
  model: string;
  /** 默认经 Agent 网关执行；旧配置缺省时按 agent 迁移。 */
  mode?: "direct" | "agent";
}

export interface Chapter {
  id: string;
  workId: string;
  idx: number;
  title: string;
  wordCount: number;
  contentHash: string;
}

/** 章正文存 blob（spec §3），blob 行只存元数据 */
export interface BlobRec {
  id: string;
  workId: string;
  kind: "text" | "image";
  byteSize: number;
  mime: string;
  sha256: string;
  storageKey: string;
}

export interface RepairRun {
  id: string;
  workId: string;
  kind: "structure" | "content";
  providerId: string;
  model: string;
  startedAt: number;
  finishedAt: number | null;
  status: "running" | "done" | "failed";
}

export type RevisionKind = "structure" | "content";

export interface AnchorPoint {
  paraIndex: number;
  charOffset: number;
}

/** 内容修订的单条补丁（spec §3） */
export interface ContentPatch {
  anchor: AnchorPoint;
  original: string;
  replacement: string;
  category: SuggestionCategory;
  reason: string;
  status: "accepted" | "rejected" | "undone";
}

export type SuggestionCategory = "乱码" | "广告" | "错字" | "其他";

export interface Revision {
  id: string;
  workId: string;
  runId: string | null;
  chapterId: string;
  kind: RevisionKind;
  /** 结构修订：切分前后边界快照；内容修订：补丁列表 */
  payload: StructurePayload | ContentPayload;
  createdAt: number;
}

export interface StructurePayload {
  before: { idx: number; title: string }[];
  after: { idx: number; title: string }[];
}

export interface ContentPayload {
  patches: ContentPatch[];
}

export type EntityKind = "character" | "scene" | "item";

export interface EntityCard {
  id: string;
  workId: string;
  kind: EntityKind;
  name: string;
  aliases: string[];
  attributes: Record<string, string>;
  status: "draft" | "canon";
  portraitBlobId: string | null;
  createdAt: number;
}

export interface Illustration {
  id: string;
  workId: string;
  prompt: string;
  providerId: string;
  model: string;
  blobId: string;
  status: "draft" | "accepted";
  genMeta: { seed?: string; referenceBlobIds: string[]; cost?: number };
  entityCardIds: string[];
  createdAt: number;
}

export interface Anchor {
  id: string;
  workId: string;
  chapterId: string;
  paraIndex: number;
  charOffset: number;
  targetType: "illustration";
  targetId: string;
  state: "active" | "orphaned";
}

// ---------- 供应商 ----------

export interface ProviderConfig {
  id: string;
  name: string;
  baseUrl: string;
  apiKey: string;
  /** 连通性诊断结果（spec §4.7） */
  diagnostic: "unknown" | "direct" | "needs-proxy" | "checking";
}

/** 图像 adapter 能力位（spec §4.5） */
export interface ImageCapability {
  supportsReference: boolean;
  maxReferences: number;
}

export interface ImageRequest {
  prompt: string;
  references: { mime: string; dataBase64: string }[];
  model: string;
  size?: string;
}

export interface ImageResult {
  mime: string;
  dataBase64: string;
}

export interface ChatMessage {
  role: "system" | "user";
  content: string;
}
