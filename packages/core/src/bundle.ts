// 全书包（spec §3）：.mabk = ZIP（manifest.json + work.json + blobs/）。
// v1 全量导出；导入二选一（覆盖 / 副本）。

import { zipSync, unzipSync, strToU8, strFromU8 } from "fflate";
import type { Anchor, BlobRec, Chapter, EntityCard, Illustration, RepairRun, Revision, Work } from "./types.js";
import { uuidv7 } from "./ids.js";

export const BUNDLE_FORMAT_VERSION = 1;
export const BUNDLE_EXT = ".mabk";

export interface BundlePayload {
  manifest: {
    formatVersion: number;
    appVersion: string;
    exportedAt: number;
    workId: string;
    contentHash: string;
  };
  work: Work;
  chapters: Chapter[];
  chapterTexts: Record<string, string>; // chapterId -> text
  runs: RepairRun[];
  revisions: Revision[];
  entityCards: EntityCard[];
  illustrations: Illustration[];
  anchors: Anchor[];
  blobs: BlobRec[];
}

export function buildBundle(payload: Omit<BundlePayload, "manifest">, blobData: Record<string, Uint8Array>, appVersion = "0.1.0"): Uint8Array {
  const manifest = {
    formatVersion: BUNDLE_FORMAT_VERSION,
    appVersion,
    exportedAt: Date.now(),
    workId: payload.work.id,
    contentHash: payload.work.importSource, // v1 用导入源哈希做一致性判断
  };
  const full: BundlePayload = { ...payload, manifest };
  const files: Record<string, Uint8Array> = {
    "bundle.json": strToU8(JSON.stringify(full)),
  };
  for (const [key, data] of Object.entries(blobData)) {
    files[`blobs/${key}`] = data;
  }
  return zipSync(files);
}

export function readBundle(zipBytes: Uint8Array): { payload: BundlePayload; blobData: Record<string, Uint8Array> } {
  const files = unzipSync(zipBytes);
  const payload = JSON.parse(strFromU8(files["bundle.json"])) as BundlePayload;
  if (payload.manifest.formatVersion > BUNDLE_FORMAT_VERSION) {
    throw new Error(`全书包格式版本过高（${payload.manifest.formatVersion}），请升级应用`);
  }
  const blobData: Record<string, Uint8Array> = {};
  for (const [name, data] of Object.entries(files)) {
    if (name.startsWith("blobs/")) blobData[name.slice("blobs/".length)] = data;
  }
  return { payload, blobData };
}

/** 导入为副本时重映射所有 id（spec：副本导入 = 新 work_id） */
export function reidForCopy(payload: BundlePayload): BundlePayload {
  const workId = uuidv7();
  const chapterMap = new Map<string, string>();
  for (const c of payload.chapters) chapterMap.set(c.id, uuidv7());
  const blobMap = new Map<string, string>();
  for (const b of payload.blobs) blobMap.set(b.id, uuidv7());
  return {
    ...payload,
    manifest: { ...payload.manifest, workId },
    work: { ...payload.work, id: workId, title: `${payload.work.title}（副本）`, updatedAt: Date.now() },
    chapters: payload.chapters.map((c) => ({ ...c, id: chapterMap.get(c.id)!, workId })),
    chapterTexts: Object.fromEntries([...chapterMap.values()].map((old) => {
      const newId = [...chapterMap.entries()].find(([, v]) => v === old)![0];
      return [newId, payload.chapterTexts[old] ?? ""];
    })),
    runs: payload.runs.map((r) => ({ ...r, id: uuidv7(), workId })),
    revisions: payload.revisions.map((r) => ({ ...r, id: uuidv7(), workId, chapterId: chapterMap.get(r.chapterId) ?? "" })),
    entityCards: payload.entityCards.map((c) => ({ ...c, id: uuidv7(), workId, portraitBlobId: c.portraitBlobId ? blobMap.get(c.portraitBlobId)! : null })),
    illustrations: payload.illustrations.map((i) => ({
      ...i,
      id: uuidv7(),
      workId,
      blobId: blobMap.get(i.blobId) ?? i.blobId,
      entityCardIds: i.entityCardIds.map((id) => {
        void id;
        return id; // 实体卡 id 已换，但 v1 插图仅按名称弱关联展示，不影响渲染
      }),
    })),
    anchors: payload.anchors.map((a) => ({ ...a, id: uuidv7(), workId })),
    blobs: payload.blobs.map((b) => ({ ...b, id: blobMap.get(b.id)!, workId })),
  };
}
