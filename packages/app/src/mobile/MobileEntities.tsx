import { useCallback, useEffect, useRef, useState } from "react";
import type { EntityCard, Work } from "@marginal/core";
import { extractEntities, genPortrait, toggleCanon, uploadPortrait } from "../actions";
import { store, useStore } from "../store";
import { BottomSheet, BlobImage } from "./shared";

const KIND_ICON: Record<EntityCard["kind"], string> = { character: "👤", scene: "🏞", item: "📦" };
const KIND_LABEL: Record<EntityCard["kind"], string> = { character: "人物", scene: "场景", item: "物品" };

export function MobileEntities({ work }: { work: Work }) {
  const version = useStore();
  const [cards, setCards] = useState<EntityCard[]>([]);
  const [detail, setDetail] = useState<EntityCard | null>(null);
  const [busy, setBusy] = useState("");
  const uploadRef = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    setCards(await store.repo.listEntityCards(work.id));
  }, [work.id, version]);
  useEffect(() => { void load(); }, [load]);

  const shown = detail ? cards.find((card) => card.id === detail.id) ?? detail : null;

  async function extract() {
    setBusy("AI 提取设定中…");
    try {
      await extractEntities(work);
      await load();
    } catch (error) {
      store.notify(`提取失败：${error instanceof Error ? error.message : error}`);
    } finally {
      setBusy("");
    }
  }

  async function onCanon(card: EntityCard) {
    const updated = await toggleCanon(card);
    await load();
    setDetail(updated);
  }

  async function onUpload(file: File) {
    if (!shown) return;
    await uploadPortrait(work, shown, file);
    await load();
  }

  return (
    <section className="m-page m-entities">
      <div className="m-card">
        <div className="m-card-head"><h3>实体卡</h3><span className="m-hint">{cards.length} 张</span></div>
        <p className="m-hint">从全文提取人物/场景设定；确认正典后，定妆照将作为插图参考图。</p>
        <button className="m-primary m-wide" disabled={!!busy} onClick={() => void extract()}>
          {busy ? busy + "…" : "🤖 AI 全文提取设定"}
        </button>
      </div>

      {cards.length === 0 ? (
        <div className="m-empty-card"><span className="m-empty-icon">👤</span><strong>还没有实体卡</strong><small>先执行 AI 提取</small></div>
      ) : (
        <div className="m-entity-grid">
          {cards.map((card) => (
            <button className="m-entity-card" key={card.id} onClick={() => setDetail(card)}>
              <div className="m-entity-portrait">
                {card.portraitBlobId
                  ? <BlobImage workId={work.id} blobId={card.portraitBlobId} alt={`${card.name} 定妆照`} className="m-entity-image" />
                  : <span>{KIND_ICON[card.kind]}</span>}
              </div>
              <strong>{card.name}</strong>
              <span className={`m-badge ${card.status === "canon" ? "canon" : "draft"}`}>{card.status === "canon" ? "正典" : "草稿"}</span>
            </button>
          ))}
        </div>
      )}

      {shown && (
        <BottomSheet title={shown.name} onClose={() => setDetail(null)}>
          <div className="m-entity-detail">
            <div className="m-entity-portrait large">
              {shown.portraitBlobId
                ? <BlobImage workId={work.id} blobId={shown.portraitBlobId} alt={`${shown.name} 定妆照`} className="m-entity-image" />
                : <span>{KIND_ICON[shown.kind]}</span>}
            </div>
            <div className="m-entity-meta">
              <span className="m-chip">{KIND_LABEL[shown.kind]}</span>
              <span className={`m-badge ${shown.status === "canon" ? "canon" : "draft"}`}>{shown.status === "canon" ? "正典" : "草稿"}</span>
              {shown.aliases.length > 0 && <span className="m-hint">别名：{shown.aliases.join("、")}</span>}
            </div>
            {Object.entries(shown.attributes).map(([key, value]) => (
              <div className="m-attr-row" key={key}><span>{key}</span><p>{value}</p></div>
            ))}
          </div>
          <div className="m-stack-actions">
            <button className={shown.status === "draft" ? "m-primary" : ""} onClick={() => void onCanon(shown)}>
              {shown.status === "draft" ? "✓ 确认正典" : "降回草稿"}
            </button>
            <button disabled={shown.status !== "canon"} onClick={() => genPortrait(work, shown)}>生成定妆照</button>
            <button disabled={shown.status !== "canon"} onClick={() => uploadRef.current?.click()}>上传定妆照</button>
          </div>
          <p className="m-hint">生成任务进入队列执行，完成后自动更新；上传立即生效。</p>
          <input ref={uploadRef} hidden type="file" accept="image/*" onChange={(event) => event.target.files?.[0] && void onUpload(event.target.files[0])} />
        </BottomSheet>
      )}
    </section>
  );
}
