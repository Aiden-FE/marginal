import { useCallback, useEffect, useState } from "react";
import type { Work } from "@marginal/core";
import { exportBundle } from "../actions";
import { store, useStore } from "../store";
import { ActionSheet, BottomSheet } from "./shared";
import type { MobileWorkTab } from "./types";

export function MobileLibrary({
  onImport,
  onOpenWork,
}: {
  onImport: () => void;
  onOpenWork: (workId: string, tab: MobileWorkTab) => void;
}) {
  const version = useStore();
  const [chapterCounts, setChapterCounts] = useState<Record<string, number>>({});
  const [actionWork, setActionWork] = useState<Work | null>(null);
  const [confirmDelete, setConfirmDelete] = useState<Work | null>(null);
  const [busy, setBusy] = useState("");

  const loadCounts = useCallback(async () => {
    const entries = await Promise.all(store.works.map(async (work) => [work.id, (await store.repo.listChapters(work.id)).length] as const));
    setChapterCounts(Object.fromEntries(entries));
  }, [version]);
  useEffect(() => { void loadCounts(); }, [loadCounts]);

  async function doExport(work: Work) {
    setBusy(work.id);
    try {
      await exportBundle(work.id);
    } catch (error) {
      store.notify(`导出失败：${error instanceof Error ? error.message : error}`);
    } finally {
      setBusy("");
    }
  }

  return (
    <section className="m-page m-library" aria-label="书架">
      <div className="m-hero-card">
        <div>
          <span className="m-eyebrow">MARGINAL LIBRARY</span>
          <h2>{store.works.length ? `${store.works.length} 本书稿` : "从一本小说开始"}</h2>
          <p>TXT 导入、AI 修复、实体卡与段落插图，都保存在当前设备。</p>
        </div>
        <button className="m-primary m-hero-action" onClick={onImport}>＋ 导入小说</button>
      </div>

      <div className="m-section-title">
        <h2>最近书稿</h2>
        <span>{store.works.length} 本</span>
      </div>

      {store.works.length === 0 && (
        <button className="m-empty-card" onClick={onImport}>
          <span className="m-empty-icon">＋</span>
          <strong>书架还是空的</strong>
          <small>导入本地 TXT，或试试内置示例书</small>
        </button>
      )}

      <div className="m-book-list">
        {store.works.map((work, index) => (
          <article className="m-book-card" key={work.id} onClick={() => onOpenWork(work.id, "reader")}>
            <div className={`m-book-cover cover-${index % 4}`}><span>{work.title.slice(0, 1)}</span></div>
            <div className="m-book-info">
              <h3>{work.title}</h3>
              <p>{chapterCounts[work.id] ?? "…"} 章 · {new Date(work.updatedAt).toLocaleDateString()}</p>
              <span>{work.importSource}</span>
            </div>
            <button
              className="m-icon-btn m-book-more"
              aria-label={`管理《${work.title}》`}
              onClick={(event) => { event.stopPropagation(); setActionWork(work); }}
            >⋯</button>
          </article>
        ))}
      </div>

      {actionWork && (
        <ActionSheet
          title={`《${actionWork.title}》`}
          onClose={() => setActionWork(null)}
          actions={[
            { icon: "📖", label: "继续阅读", onClick: () => onOpenWork(actionWork.id, "reader") },
            { icon: "🔧", label: "修复与修订", onClick: () => onOpenWork(actionWork.id, "repair") },
            { icon: "👤", label: "实体卡", onClick: () => onOpenWork(actionWork.id, "entities") },
            { icon: "🖼", label: "插图", onClick: () => onOpenWork(actionWork.id, "illustrations") },
            { icon: "📦", label: busy === actionWork.id ? "导出中…" : "导出全书包", disabled: !!busy, onClick: () => void doExport(actionWork) },
            { icon: "🗑", label: "删除书稿", danger: true, onClick: () => setConfirmDelete(actionWork) },
          ]}
        />
      )}

      {confirmDelete && (
        <BottomSheet title="删除书稿" onClose={() => setConfirmDelete(null)}>
          <div className="m-confirm-copy">
            <div className="m-danger-icon">!</div>
            <h3>删除《{confirmDelete.title}》？</h3>
            <p>章节、修订、实体卡和插图将从当前设备永久删除。</p>
          </div>
          <div className="m-stack-actions">
            <button className="m-danger-solid" onClick={() => void store.deleteWork(confirmDelete.id).then(() => setConfirmDelete(null))}>确认删除</button>
            <button onClick={() => setConfirmDelete(null)}>保留书稿</button>
          </div>
        </BottomSheet>
      )}
    </section>
  );
}
