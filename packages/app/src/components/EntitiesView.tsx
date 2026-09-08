// 实体卡（spec §4.4）：AI 提取 → 逐卡确认/修正 → 正典化；定妆照 AI 生成或上传。

import { useCallback, useEffect, useRef, useState } from "react";
import { sha256Hex, uuidv7, type EntityCard, type Work } from "@marginal/core";
import { store, useStore } from "../store";
import { extractEntities, genPortrait as genPortraitAction, toggleCanon as toggleCanonAction } from "../actions";

export function EntitiesView({ work }: { work: Work }) {
  useStore();
  const [cards, setCards] = useState<EntityCard[]>([]);
  const [busy, setBusy] = useState("");
  const uploadRef = useRef<HTMLInputElement>(null);
  const [uploadTarget, setUploadTarget] = useState<EntityCard | null>(null);

  const load = useCallback(async () => {
    setCards(await store.repo.listEntityCards(work.id));
  }, [work.id]);
  useEffect(() => { void load(); }, [load]);

  async function extract() {
    setBusy("AI 提取设定中…");
    try {
      await extractEntities(work);
      await load();
    } catch (err) {
      store.notify(`提取失败：${err instanceof Error ? err.message : err}`);
    } finally {
      setBusy("");
    }
  }

  async function toggleCanon(card: EntityCard) {
    if (card.status === "canon" && !window.confirm(`将「${card.name}」降回草稿？其参考图资格随之失效。`)) return;
    await toggleCanonAction(card);
    await load();
  }

  function genPortrait(card: EntityCard) {
    genPortraitAction(work, card);
  }

  async function onUpload(file: File) {
    if (!uploadTarget) return;
    const bytes = new Uint8Array(await file.arrayBuffer());
    const blobId = uuidv7();
    const storageKey = `${work.id}/${blobId}`;
    await store.repo.putBlob({
      id: blobId, workId: work.id, kind: "image", byteSize: bytes.length,
      mime: file.type || "image/png", sha256: await sha256Hex(bytes), storageKey,
    }, bytes);
    await store.repo.putEntityCard({ ...uploadTarget, portraitBlobId: blobId });
    setUploadTarget(null);
    await load();
    store.notify("定妆照已上传");
  }

  function editCard(card: EntityCard) {
    const attrs = window.prompt(
      `编辑「${card.name}」的属性（每行一个 key：value）`,
      Object.entries(card.attributes).map(([k, v]) => `${k}：${v}`).join("\n"),
    );
    if (!attrs) return;
    const attributes = Object.fromEntries(
      attrs.split("\n").map((l) => {
        const at = l.indexOf("：") >= 0 ? l.indexOf("：") : l.indexOf(":");
        return at > 0 ? [l.slice(0, at).trim(), l.slice(at + 1).trim()] : [l.trim(), ""];
      }).filter(([k]) => k),
    );
    void store.repo.putEntityCard({ ...card, attributes }).then(load);
  }

  return (
    <div>
      <div className="card row">
        <button className="primary" disabled={!!busy} onClick={extract}>🤖 AI 全文提取设定</button>
        {busy && <span className="muted">{busy}</span>}
        <span className="muted">确认（正典）= 参考图资格；正典卡必须有定妆照才能为插图提供参考</span>
      </div>
      <input ref={uploadRef} type="file" accept="image/*" hidden onChange={(e) => e.target.files?.[0] && onUpload(e.target.files[0])} />
      <div className="card">
        {cards.length === 0 && <div className="muted">还没有实体卡——先执行 AI 提取。</div>}
        <table className="list">
          <tbody>
            {cards.map((c) => (
              <tr key={c.id}>
                <td>{c.kind === "character" ? "👤" : c.kind === "scene" ? "🏞" : "📦"}</td>
                <td><b>{c.name}</b>{c.aliases.length > 0 && <span className="muted">（{c.aliases.join("、")}）</span>}</td>
                <td className="muted" style={{ maxWidth: 320 }}>{Object.entries(c.attributes).map(([k, v]) => `${k}：${v}`).join("；").slice(0, 120)}</td>
                <td><span className={`badge ${c.status}`}>{c.status === "canon" ? "正典" : "草稿"}</span></td>
                <td style={{ textAlign: "right" }}>
                  <button onClick={() => toggleCanon(c)}>{c.status === "draft" ? "✓ 确认正典" : "降回草稿"}</button>{" "}
                  <button onClick={() => genPortrait(c)} disabled={c.status !== "canon"}>生成定妆照</button>{" "}
                  <button onClick={() => { setUploadTarget(c); uploadRef.current?.click(); }}>上传定妆照</button>{" "}
                  <button onClick={() => editCard(c)}>编辑</button>{" "}
                  <button className="danger" onClick={() => window.confirm(`删除「${c.name}」？`) && store.repo.deleteEntityCard(c.id).then(load)}>删除</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
