// IndexedDB 实现（降级引擎）：与 SQLite 引擎同一 Repository 接口。
// 当 OPFS/SQLite WASM 不可用时兜底，保证应用始终可用。

import type {
  Anchor,
  BlobRec,
  Chapter,
  EntityCard,
  Illustration,
  RepairRun,
  Repository,
  Revision,
  Work,
} from "@marginal/core";
import type { BundlePayload } from "@marginal/core";

const DB_NAME = "marginal";
const DB_VERSION = 1;

export class IdbRepository implements Repository {
  readonly engine = "indexeddb";
  private db!: IDBDatabase;

  async init(): Promise<void> {
    this.db = await new Promise<IDBDatabase>((resolve, reject) => {
      const req = indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = () => {
        const db = req.result;
        for (const store of ["works", "chapters", "texts", "runs", "revisions", "cards", "illustrations", "anchors", "blobs", "bindata"]) {
          if (!db.objectStoreNames.contains(store)) db.createObjectStore(store, { keyPath: store === "texts" || store === "bindata" ? undefined : "id" });
        }
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  }

  async close(): Promise<void> {
    this.db.close();
  }

  private tx<T>(stores: string[], mode: IDBTransactionMode, fn: (tx: IDBTransaction) => Promise<T> | T): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const tx = this.db.transaction(stores, mode);
      Promise.resolve(fn(tx)).then(resolve, reject);
      tx.onabort = () => reject(tx.error);
    });
  }

  private req<T>(op: IDBRequest): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      op.onsuccess = () => resolve(op.result as T);
      op.onerror = () => reject(op.error);
    });
  }

  async listWorks(): Promise<Work[]> {
    return this.tx(["works"], "readonly", async (tx) => {
      const all = await this.req<Work[]>(tx.objectStore("works").getAll());
      return all.sort((a, b) => b.updatedAt - a.updatedAt);
    });
  }
  async getWork(id: string): Promise<Work | null> {
    return this.tx(["works"], "readonly", async (tx) => (await this.req<Work | undefined>(tx.objectStore("works").get(id))) ?? null);
  }
  async putWork(work: Work): Promise<void> {
    await this.tx(["works"], "readwrite", (tx) => void tx.objectStore("works").put(work));
  }
  async deleteWork(id: string): Promise<void> {
    await this.tx(["works", "chapters", "texts", "runs", "revisions", "cards", "illustrations", "anchors", "blobs", "bindata"], "readwrite", async (tx) => {
      const chapters = await this.req<Chapter[]>(tx.objectStore("chapters").getAll());
      for (const c of chapters.filter((c) => c.workId === id)) {
        tx.objectStore("chapters").delete(c.id);
        tx.objectStore("texts").delete(c.id);
      }
      for (const store of ["works", "runs", "revisions", "cards", "illustrations", "anchors", "blobs"] as const) {
        const all: { id: string; workId: string; storageKey?: string }[] = await this.req(tx.objectStore(store).getAll());
        for (const item of all.filter((x) => x.workId === id)) {
          tx.objectStore(store).delete(item.id);
          if (item.storageKey) tx.objectStore("bindata").delete(item.storageKey);
        }
      }
    });
  }

  async listChapters(workId: string): Promise<Chapter[]> {
    return this.tx(["chapters"], "readonly", async (tx) => {
      const all = await this.req<Chapter[]>(tx.objectStore("chapters").getAll());
      return all.filter((c) => c.workId === workId).sort((a, b) => a.idx - b.idx);
    });
  }
  async getChapterText(chapterId: string): Promise<string> {
    return this.tx(["texts"], "readonly", async (tx) => (await this.req<string | undefined>(tx.objectStore("texts").get(chapterId))) ?? "");
  }
  async putChapter(workId: string, chapter: Chapter, text: string): Promise<void> {
    void workId;
    await this.tx(["chapters", "texts"], "readwrite", (tx) => {
      tx.objectStore("chapters").put(chapter);
      tx.objectStore("texts").put(text, chapter.id);
    });
  }
  async replaceChapters(workId: string, chapters: { chapter: Chapter; text: string }[]): Promise<void> {
    await this.tx(["chapters", "texts"], "readwrite", async (tx) => {
      const old: Chapter[] = await this.req(tx.objectStore("chapters").getAll());
      for (const c of old.filter((c) => c.workId === workId)) {
        tx.objectStore("chapters").delete(c.id);
        tx.objectStore("texts").delete(c.id);
      }
      for (const { chapter, text } of chapters) {
        tx.objectStore("chapters").put(chapter);
        tx.objectStore("texts").put(text, chapter.id);
      }
    });
  }
  async deleteChapters(workId: string): Promise<void> {
    await this.replaceChapters(workId, []);
  }

  async putRun(run: RepairRun): Promise<void> {
    await this.tx(["runs"], "readwrite", (tx) => void tx.objectStore("runs").put(run));
  }
  async listRuns(workId: string): Promise<RepairRun[]> {
    return this.tx(["runs"], "readonly", async (tx) => {
      const all = await this.req<RepairRun[]>(tx.objectStore("runs").getAll());
      return all.filter((r) => r.workId === workId);
    });
  }
  async putRevision(revision: Revision): Promise<void> {
    await this.tx(["revisions"], "readwrite", (tx) => void tx.objectStore("revisions").put(revision));
  }
  async updateRevision(revision: Revision): Promise<void> {
    await this.tx(["revisions"], "readwrite", (tx) => void tx.objectStore("revisions").put(revision));
  }
  async listRevisions(workId: string): Promise<Revision[]> {
    return this.tx(["revisions"], "readonly", async (tx) => {
      const all = await this.req<Revision[]>(tx.objectStore("revisions").getAll());
      return all.filter((r) => r.workId === workId);
    });
  }

  async listEntityCards(workId: string): Promise<EntityCard[]> {
    return this.tx(["cards"], "readonly", async (tx) => {
      const all = await this.req<EntityCard[]>(tx.objectStore("cards").getAll());
      return all.filter((c) => c.workId === workId);
    });
  }
  async putEntityCard(card: EntityCard): Promise<void> {
    await this.tx(["cards"], "readwrite", (tx) => void tx.objectStore("cards").put(card));
  }
  async deleteEntityCard(id: string): Promise<void> {
    await this.tx(["cards"], "readwrite", (tx) => void tx.objectStore("cards").delete(id));
  }

  async listIllustrations(workId: string): Promise<Illustration[]> {
    return this.tx(["illustrations"], "readonly", async (tx) => {
      const all = await this.req<Illustration[]>(tx.objectStore("illustrations").getAll());
      return all.filter((i) => i.workId === workId);
    });
  }
  async putIllustration(illus: Illustration): Promise<void> {
    await this.tx(["illustrations"], "readwrite", (tx) => void tx.objectStore("illustrations").put(illus));
  }
  async listAnchors(workId: string): Promise<Anchor[]> {
    return this.tx(["anchors"], "readonly", async (tx) => {
      const all = await this.req<Anchor[]>(tx.objectStore("anchors").getAll());
      return all.filter((a) => a.workId === workId);
    });
  }
  async putAnchor(anchor: Anchor): Promise<void> {
    await this.tx(["anchors"], "readwrite", (tx) => void tx.objectStore("anchors").put(anchor));
  }
  async deleteAnchor(id: string): Promise<void> {
    await this.tx(["anchors"], "readwrite", (tx) => void tx.objectStore("anchors").delete(id));
  }
  async remapAnchors(workId: string, remaps: { id: string; chapterId?: string; paraIndex?: number; charOffset?: number; state?: "active" | "orphaned" }[]): Promise<void> {
    await this.tx(["anchors"], "readwrite", async (tx) => {
      const all = await this.req<Anchor[]>(tx.objectStore("anchors").getAll());
      const byId = new Map(all.filter((a) => a.workId === workId).map((a) => [a.id, a]));
      for (const r of remaps) {
        const a = byId.get(r.id);
        if (!a) continue;
        tx.objectStore("anchors").put({ ...a, ...r });
      }
    });
  }

  async putBlob(blob: BlobRec, data: Uint8Array): Promise<void> {
    await this.tx(["blobs", "bindata"], "readwrite", (tx) => {
      tx.objectStore("blobs").put(blob);
      tx.objectStore("bindata").put(data, blob.storageKey);
    });
  }
  async getBlobData(storageKey: string): Promise<Uint8Array | null> {
    return this.tx(["bindata"], "readonly", async (tx) => (await this.req<Uint8Array | undefined>(tx.objectStore("bindata").get(storageKey))) ?? null);
  }
  async listBlobs(workId: string): Promise<BlobRec[]> {
    return this.tx(["blobs"], "readonly", async (tx) => {
      const all = await this.req<BlobRec[]>(tx.objectStore("blobs").getAll());
      return all.filter((b) => b.workId === workId);
    });
  }

  async exportAll(): Promise<{ works: Work[]; blobData: Record<string, Uint8Array> }> {
    return this.tx(["works", "bindata"], "readonly", async (tx) => {
      const works = await this.req<Work[]>(tx.objectStore("works").getAll());
      const bindata: { key: IDBValidKey; data: Uint8Array }[] = [];
      await new Promise<void>((resolve) => {
        const cursorReq = tx.objectStore("bindata").openCursor();
        cursorReq.onsuccess = () => {
          const cursor = cursorReq.result;
          if (!cursor) return resolve();
          bindata.push({ key: cursor.key, data: cursor.value as Uint8Array });
          cursor.continue();
        };
        cursorReq.onerror = () => resolve();
      });
      const blobData: Record<string, Uint8Array> = {};
      for (const { key, data } of bindata) blobData[String(key)] = data;
      return { works, blobData };
    });
  }

  async importBundle(payload: BundlePayload, blobData: Record<string, Uint8Array>, mode: "replace" | "copy", existingWorkIds: string[]): Promise<void> {
    void existingWorkIds;
    if (mode === "replace") await this.deleteWork(payload.work.id);
    const storageKeyMap = new Map<string, string>();
    await this.tx(["works", "chapters", "texts", "runs", "revisions", "cards", "illustrations", "anchors", "blobs", "bindata"], "readwrite", async (tx) => {
      for (const b of payload.blobs) {
        const key = mode === "copy" ? `${payload.work.id}/${b.id}` : b.storageKey;
        storageKeyMap.set(b.id, key);
        tx.objectStore("blobs").put({ ...b, storageKey: key });
        const data = blobData[b.storageKey] ?? blobData[b.id];
        if (data) tx.objectStore("bindata").put(data, key);
      }
      tx.objectStore("works").put(payload.work);
      for (const c of payload.chapters) {
        tx.objectStore("chapters").put(c);
        tx.objectStore("texts").put(payload.chapterTexts[c.id] ?? "", c.id);
      }
      for (const r of payload.runs) tx.objectStore("runs").put(r);
      for (const r of payload.revisions) tx.objectStore("revisions").put(r);
      for (const c of payload.entityCards) {
        tx.objectStore("cards").put({ ...c, portraitBlobId: c.portraitBlobId ? storageKeyMap.get(c.portraitBlobId) ?? c.portraitBlobId : null });
      }
      for (const i of payload.illustrations) tx.objectStore("illustrations").put(i);
      for (const a of payload.anchors) tx.objectStore("anchors").put(a);
    });
  }

  async wipe(): Promise<void> {
    await this.tx(["works", "chapters", "texts", "runs", "revisions", "cards", "illustrations", "anchors", "blobs", "bindata"], "readwrite", (tx) => {
      for (const store of ["works", "chapters", "texts", "runs", "revisions", "cards", "illustrations", "anchors", "blobs", "bindata"]) {
        tx.objectStore(store).clear();
      }
    });
  }
}
