import { useCallback, useEffect, useMemo, useState } from "react";
import type { Work } from "@marginal/core";
import { exportBundle } from "../actions";
import { store, useStore } from "../store";
import { ActionSheet, BottomSheet } from "./shared";
import {
  isWorkFinished, loadReadingPosition, loadWorkGroups, saveWorkGroups, setWorkGroup, workGroupNames,
  type WorkGroupMap,
} from "./logic";
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
  const [readingLabels, setReadingLabels] = useState<Record<string, string>>({});
  const [finished, setFinished] = useState<Record<string, boolean>>({});
  const [groups, setGroups] = useState<WorkGroupMap>(() => loadWorkGroups(localStorage));
  const [groupFilter, setGroupFilter] = useState("");
  const [groupWork, setGroupWork] = useState<Work | null>(null);
  const [groupInput, setGroupInput] = useState("");
  const [actionWork, setActionWork] = useState<Work | null>(null);
  const [confirmDelete, setConfirmDelete] = useState<Work | null>(null);
  const [busy, setBusy] = useState("");

  const loadCounts = useCallback(async () => {
    const entries = await Promise.all(store.works.map(async (work) => {
      const chapters = await store.repo.listChapters(work.id);
      const position = loadReadingPosition(localStorage, work.id);
      const done = isWorkFinished(position, chapters);
      const index = position ? chapters.findIndex((chapter) => chapter.id === position.chapterId) : -1;
      return [work.id, {
        count: chapters.length,
        done,
        label: done ? "已读完" : index >= 0 ? `上次读到 第${index + 1}章` : "",
      }] as const;
    }));
    setChapterCounts(Object.fromEntries(entries.map(([id, value]) => [id, value.count])));
    setReadingLabels(Object.fromEntries(entries.map(([id, value]) => [id, value.label])));
    setFinished(Object.fromEntries(entries.map(([id, value]) => [id, value.done])));
    const stored = loadWorkGroups(localStorage);
    const validIds = new Set(store.works.map((work) => work.id));
    const cleaned = Object.fromEntries(Object.entries(stored).filter(([id]) => validIds.has(id)));
    if (Object.keys(cleaned).length !== Object.keys(stored).length) saveWorkGroups(localStorage, cleaned);
    setGroups(cleaned);
  }, [version]);
  useEffect(() => { void loadCounts(); }, [loadCounts]);

  const groupNames = useMemo(() => workGroupNames(groups), [groups]);
  const visibleWorks = useMemo(() => (
    groupFilter ? store.works.filter((work) => groups[work.id] === groupFilter) : store.works
  ), [groupFilter, groups, version]);

  function openGroupEditor(work: Work) {
    setGroupWork(work);
    setGroupInput(groups[work.id] ?? "");
  }

  function applyGroup(value = groupInput) {
    if (!groupWork) return;
    const next = setWorkGroup(localStorage, groupWork.id, value);
    setGroups(next);
    setGroupWork(null);
    store.notify(value.trim() ? `已将《${groupWork.title}》加入「${value.trim()}」` : "已移出分组");
  }

  async function deleteConfirmed(work: Work) {
    await store.deleteWork(work.id);
    setGroups(setWorkGroup(localStorage, work.id, ""));
    setConfirmDelete(null);
  }

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
        <h2>{groupFilter || "最近书稿"}</h2>
        <span>{visibleWorks.length} 本</span>
      </div>

      {store.works.length > 0 && (
        <div className="m-group-chips" aria-label="书架分组">
          <button className={`m-group-chip${groupFilter === "" ? " active" : ""}`} onClick={() => setGroupFilter("")}>全部</button>
          {groupNames.map((name) => (
            <button key={name} className={`m-group-chip${groupFilter === name ? " active" : ""}`} onClick={() => setGroupFilter(name)}>
              {name} · {store.works.filter((work) => groups[work.id] === name).length}
            </button>
          ))}
        </div>
      )}

      {store.works.length === 0 && (
        <button className="m-empty-card" onClick={onImport}>
          <span className="m-empty-icon">＋</span>
          <strong>书架还是空的</strong>
          <small>导入本地 TXT，或试试内置示例书</small>
        </button>
      )}

      <div className="m-book-list">
        {visibleWorks.map((work, index) => (
          <article className="m-book-card" key={work.id} onClick={() => onOpenWork(work.id, "reader")}>
            <div className={`m-book-cover cover-${index % 4}`}><span>{work.title.slice(0, 1)}</span></div>
            <div className="m-book-info">
              <h3>{work.title}{groups[work.id] ? ` · ${groups[work.id]}` : ""}</h3>
              <p>
                {chapterCounts[work.id] ?? "…"} 章 · {new Date(work.updatedAt).toLocaleDateString()}
                {finished[work.id] && <span className="m-book-done">已读完</span>}
              </p>
              <span>{readingLabels[work.id] || work.importSource}</span>
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
            { icon: "📁", label: groups[actionWork.id] ? `分组：${groups[actionWork.id]}` : "设置分组", onClick: () => openGroupEditor(actionWork) },
            { icon: "📦", label: busy === actionWork.id ? "导出中…" : "导出全书包", disabled: !!busy, onClick: () => void doExport(actionWork) },
            { icon: "🗑", label: "删除书稿", danger: true, onClick: () => setConfirmDelete(actionWork) },
          ]}
        />
      )}

      {groupWork && (
        <BottomSheet title={`设置《${groupWork.title}》的分组`} onClose={() => setGroupWork(null)}>
          <label className="m-field">
            <span>分组名称</span>
            <input aria-label="分组名称" value={groupInput} onChange={(event) => setGroupInput(event.target.value)} placeholder="例如：武侠、待读、收藏" maxLength={30} autoFocus />
          </label>
          {groupNames.length > 0 && (
            <div className="m-group-chips">
              {groupNames.map((name) => <button key={name} className="m-group-chip" onClick={() => setGroupInput(name)}>{name}</button>)}
            </div>
          )}
          <div className="m-inline-actions">
            <button className="m-primary" disabled={!groupInput.trim()} onClick={() => applyGroup()}>保存分组</button>
            {groups[groupWork.id] && <button onClick={() => applyGroup("")}>移出分组</button>}
          </div>
        </BottomSheet>
      )}

      {confirmDelete && (
        <BottomSheet title="删除书稿" onClose={() => setConfirmDelete(null)}>
          <div className="m-confirm-copy">
            <div className="m-danger-icon">!</div>
            <h3>删除《{confirmDelete.title}》？</h3>
            <p>章节、修订、实体卡和插图将从当前设备永久删除。</p>
          </div>
          <div className="m-stack-actions">
            <button className="m-danger-solid" onClick={() => void deleteConfirmed(confirmDelete)}>确认删除</button>
            <button onClick={() => setConfirmDelete(null)}>保留书稿</button>
          </div>
        </BottomSheet>
      )}
    </section>
  );
}
