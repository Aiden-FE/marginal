// Repository 接口（spec §2：接口在 core，实现按端）。
// 实现方：data 包的 SQLite(WASM/OPFS) 与 IndexedDB 降级。

import type {
  Anchor,
  BlobRec,
  Chapter,
  EntityCard,
  Illustration,
  RepairRun,
  Revision,
  Work,
} from "./types.js";

export interface ChapterWithText extends Chapter {
  text: string;
}

export interface Repository {
  init(): Promise<void>;
  close(): Promise<void>;
  readonly engine: string;

  // works
  listWorks(): Promise<Work[]>;
  getWork(id: string): Promise<Work | null>;
  putWork(work: Work): Promise<void>;
  deleteWork(id: string): Promise<void>;

  // chapters（正文按章存 blob）
  listChapters(workId: string): Promise<Chapter[]>;
  getChapterText(chapterId: string): Promise<string>;
  putChapter(workId: string, chapter: Chapter, text: string): Promise<void>;
  /** 整本替换章节结构（结构修订应用） */
  replaceChapters(workId: string, chapters: { chapter: Chapter; text: string }[]): Promise<void>;
  deleteChapters(workId: string): Promise<void>;

  // runs & revisions（只追加）
  putRun(run: RepairRun): Promise<void>;
  listRuns(workId: string): Promise<RepairRun[]>;
  putRevision(revision: Revision): Promise<void>;
  listRevisions(workId: string): Promise<Revision[]>;
  updateRevision(revision: Revision): Promise<void>;

  // entity cards
  listEntityCards(workId: string): Promise<EntityCard[]>;
  putEntityCard(card: EntityCard): Promise<void>;
  deleteEntityCard(id: string): Promise<void>;

  // illustrations & anchors
  listIllustrations(workId: string): Promise<Illustration[]>;
  putIllustration(illus: Illustration): Promise<void>;
  listAnchors(workId: string): Promise<Anchor[]>;
  putAnchor(anchor: Anchor): Promise<void>;
  deleteAnchor(id: string): Promise<void>;
  /** 修复重跑后的锚点批量重映射（须与修订追加同事务语义） */
  remapAnchors(workId: string, remaps: { id: string; chapterId?: string; paraIndex?: number; charOffset?: number; state?: "active" | "orphaned" }[]): Promise<void>;

  // blobs（二进制）
  putBlob(blob: BlobRec, data: Uint8Array): Promise<void>;
  getBlobData(storageKey: string): Promise<Uint8Array | null>;
  listBlobs(workId: string): Promise<BlobRec[]>;

  // 全书包（spec §3）
  exportAll(): Promise<{ works: Work[]; blobData: Record<string, Uint8Array> }>;
  importBundle(payload: import("./bundle.js").BundlePayload, blobData: Record<string, Uint8Array>, mode: "replace" | "copy", existingWorkIds: string[]): Promise<void>;
  wipe(): Promise<void>;
}
