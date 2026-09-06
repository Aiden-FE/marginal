// 插图管理（spec §4.4）：批量预扫候选段落 → 可编辑任务清单 → 入队；画廊接受/删除。

import { useCallback, useEffect, useState } from "react";
import { buildIllustrationPrompt, pickCandidateParagraphs, sha256Hex, uuidv7, splitParagraphs, type Illustration, type Work } from "@marginal/core";
import { store, useStore } from "../store";

export function IllustrationsView({ work }: { work: Work }) {
  useStore();
  const [illus, setIllus] = useState<Illustration[]>([]);
  const [candidates, setCandidates] = useState<{ chapterKey: string; paraIndex: number; preview: string }[]>([]);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [scene, setScene] = useState("全书扫描");
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setIllus(await store.repo.listIllustrations(work.id));
  }, [work.id]);
  useEffect(() => { void load(); }, [load]);

  function scan() {
    void (async () => {
      setBusy(true);
      const cs = await store.repo.listChapters(work.id);
      const texts: Record<string, string> = {};
      for (const c of cs) texts[c.id] = c.title;
      const cand = pickCandidateParagraphs(
        Object.fromEntries(await Promise.all(cs.map(async (c) => [c.id, await store.repo.getChapterText(c.id)] as const))),
      );
      // 附上章节标题预览
      const titleMap = new Map(cs.map((c) => [c.id, c.title]));
      setCandidates(cand.slice(0, 60).map((c) => ({ ...c, preview: `《${titleMap.get(c.chapterKey) ?? ""}》段${c.paraIndex + 1}: ${c.preview}` })));
      setSelected(new Set(cand.slice(0, 60).map((c) => `${c.chapterKey}:${c.paraIndex}`)));
      void texts;
      setBusy(false);
      store.notify(`预扫到 ${Math.min(cand.length, 60)} 个候选段落，勾选后入队`);
    })();
  }

  function enqueue() {
    void (async () => {
      const cfg = work.settings.taskConfigs.illustration ?? store.defaultTaskConfig("illustration");
      const client = store.getClient(cfg.providerId);
      const cards = (await store.repo.listEntityCards(work.id)).filter((c) => c.status === "canon");
      const cs = await store.repo.listChapters(work.id);
      const limit = work.settings.budgetLimit;
      if (limit > 0) store.queue.setBudgetLimit(limit);
      let enqueued = 0;
      for (const c of candidates) {
        const key = `${c.chapterKey}:${c.paraIndex}`;
        if (!selected.has(key)) continue;
        const ch = cs.find((x) => x.id === c.chapterKey);
        if (!ch) continue;
        const fullText = await store.repo.getChapterText(ch.id);
        const paraText = splitParagraphs(fullText)[c.paraIndex] ?? "";
        enqueued++;
        store.queue.add(`插图：${ch.title}·段${c.paraIndex + 1}`, async () => {
          const references: { mime: string; dataBase64: string }[] = [];
          for (const card of cards.slice(0, 3)) {
            if (!card.portraitBlobId) continue;
            const meta = (await store.repo.listBlobs(work.id)).find((b) => b.id === card.portraitBlobId);
            if (!meta) continue;
            const data = await store.repo.getBlobData(meta.storageKey);
            if (!data) continue;
            let bin = "";
            for (let i = 0; i < data.length; i += 0x8000) bin += String.fromCharCode(...data.subarray(i, i + 0x8000));
            references.push({ mime: meta.mime, dataBase64: btoa(bin) });
          }
          const prompt = buildIllustrationPrompt(paraText.slice(0, 200), cards.slice(0, 3), references.length > 0);
          const result = await client.generateImage({ prompt, references, model: cfg.model });
          const bytes = Uint8Array.from(atob(result.dataBase64), (c2) => c2.charCodeAt(0));
          const blobId = uuidv7();
          const storageKey = `${work.id}/${blobId}`;
          await store.repo.putBlob({
            id: blobId, workId: work.id, kind: "image", byteSize: bytes.length,
            mime: result.mime, sha256: await sha256Hex(bytes), storageKey,
          }, bytes);
          const illus2: Illustration = {
            id: uuidv7(), workId: work.id, prompt, providerId: cfg.providerId, model: cfg.model,
            blobId, status: "draft", genMeta: { referenceBlobIds: references.map((_, i) => String(i)) },
            entityCardIds: cards.map((c2) => c2.id), createdAt: Date.now(),
          };
          await store.repo.putIllustration(illus2);
          await load();
        });
      }
      store.notify(`已入队 ${enqueued} 个插图任务${limit > 0 ? `（预算上限 ${limit} 次）` : ""}`);
      setScene(`${scene} · ${enqueued}`);
    })();
  }

  async function accept(i: Illustration) {
    await store.repo.putIllustration({ ...i, status: "accepted" });
    await load();
  }
  async function remove(i: Illustration) {
    await store.repo.deleteAnchor?.(i.id).catch?.(() => {});
    await store.repo.putIllustration({ ...i, status: "draft" });
    await load();
  }

  return (
    <div>
      <div className="card row">
        <button className="primary" disabled={busy} onClick={scan}>🔍 预扫候选段落</button>
        <input value={scene} onChange={(e) => setScene(e.target.value)} style={{ width: 160 }} />
        <button className="primary" disabled={candidates.length === 0} onClick={enqueue}>🖼 入队生成（{selected.size}）</button>
        <span className="muted">预算上限在书设置中配置，触顶自动暂停</span>
      </div>
      {candidates.length > 0 && (
        <div className="card" style={{ maxHeight: "34vh", overflow: "auto" }}>
          <b>候选清单（spec §4.4：预扫 → 可删改 → 入队）</b>
          {candidates.map((c) => {
            const key = `${c.chapterKey}:${c.paraIndex}`;
            return (
              <div key={key} className="row" style={{ padding: "3px 0" }}>
                <input type="checkbox" checked={selected.has(key)} onChange={(e) => {
                  const next = new Set(selected);
                  if (e.target.checked) next.add(key); else next.delete(key);
                  setSelected(next);
                }} />
                <span className="muted">{c.preview}</span>
              </div>
            );
          })}
        </div>
      )}
      <div className="card">
        <b>插图画廊</b>
        <div className="row" style={{ alignItems: "flex-start" }}>
          {illus.length === 0 && <span className="muted">暂无插图</span>}
          {illus.map((i) => <GalleryItem key={i.id} illus={i} workId={work.id} onAccept={() => accept(i)} />)}
        </div>
      </div>
    </div>
  );
}

function GalleryItem({ illus, workId, onAccept }: { illus: Illustration; workId: string; onAccept: () => void }) {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    void (async () => {
      const meta = (await store.repo.listBlobs(workId)).find((b) => b.id === illus.blobId);
      if (!meta) return;
      const data = await store.repo.getBlobData(meta.storageKey);
      if (!data) return;
      setUrl(URL.createObjectURL(new Blob([data as BlobPart], { type: meta.mime })));
    })();
  }, [illus.blobId, workId]);
  return (
    <div style={{ width: 200, border: "1px solid #2a2e36", borderRadius: 8, padding: 8 }}>
      {url ? <img src={url} style={{ width: "100%", borderRadius: 4 }} alt={illus.prompt.slice(0, 30)} /> : <div className="muted">加载中…</div>}
      <div className="muted" style={{ marginTop: 4 }}>{illus.prompt.slice(0, 50)}…</div>
      <div className="row" style={{ marginTop: 6 }}>
        <span className={`badge ${illus.status === "accepted" ? "canon" : "draft"}`}>{illus.status === "accepted" ? "已接受" : "草稿"}</span>
        {illus.status === "draft" && <button onClick={onAccept}>接受</button>}
      </div>
    </div>
  );
}
