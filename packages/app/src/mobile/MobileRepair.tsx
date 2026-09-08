import { useCallback, useEffect, useState } from "react";
import type { ContentPatch, Revision, Work } from "@marginal/core";
import { applySuggestions, genCleanSuggestions, restructure, rollback } from "../actions";
import { store, useStore } from "../store";

const CATEGORIES = ["乱码", "广告", "错字", "其他"] as const;

export function MobileRepair({ work }: { work: Work }) {
  const version = useStore();
  const [chapters, setChapters] = useState<{ id: string; idx: number; title: string }[]>([]);
  const [chapterId, setChapterId] = useState("");
  const [suggestions, setSuggestions] = useState<ContentPatch[] | null>(null);
  const [revisions, setRevisions] = useState<Revision[]>([]);
  const [busy, setBusy] = useState("");

  const load = useCallback(async () => {
    const all = await store.repo.listChapters(work.id);
    setChapters(all.map((chapter) => ({ id: chapter.id, idx: chapter.idx, title: chapter.title })));
    setChapterId((current) => current || all[0]?.id || "");
    setRevisions(await store.repo.listRevisions(work.id));
  }, [work.id, version]);
  useEffect(() => { void load(); }, [load]);

  async function runStructure() {
    setBusy("重新切分中…");
    try {
      await restructure(work);
      setSuggestions(null);
      await load();
    } catch (error) {
      store.notify(`切分失败：${error instanceof Error ? error.message : error}`);
    } finally {
      setBusy("");
    }
  }

  async function runClean() {
    if (!chapterId) return;
    setBusy("生成清洗建议中…");
    try {
      setSuggestions(await genCleanSuggestions(work, chapterId));
    } catch (error) {
      store.notify(`清洗失败：${error instanceof Error ? error.message : error}`);
    } finally {
      setBusy("");
    }
  }

  function setPatchStatus(patch: ContentPatch, status: ContentPatch["status"]) {
    setSuggestions((current) => current?.map((item) => (item === patch ? { ...item, status } : item)) ?? null);
  }

  function setCategoryStatus(category: string, status: ContentPatch["status"]) {
    setSuggestions((current) => current?.map((item) => (item.category === category ? { ...item, status } : item)) ?? null);
  }

  async function apply() {
    if (!suggestions || !chapterId) return;
    setBusy("应用修改中…");
    try {
      await applySuggestions(work, chapterId, suggestions);
      setSuggestions(null);
      await load();
    } catch (error) {
      store.notify(`应用失败：${error instanceof Error ? error.message : error}`);
    } finally {
      setBusy("");
    }
  }

  async function revert(revision: Revision) {
    setBusy("回滚中…");
    try {
      await rollback(work, revision);
      setSuggestions(null);
      await load();
    } catch (error) {
      store.notify(`回滚失败：${error instanceof Error ? error.message : error}`);
    } finally {
      setBusy("");
    }
  }

  const accepted = suggestions?.filter((patch) => patch.status === "accepted").length ?? 0;
  const contentRevisions = [...revisions].filter((revision) => revision.kind === "content").reverse();

  return (
    <section className="m-page m-repair">
      <div className="m-card">
        <div className="m-card-head"><h3>章节清洗</h3><span className="m-chip">diff 审核</span></div>
        <p className="m-hint">选择章节后生成建议；建议不会直接改文，逐条或按类目审核后应用。</p>
        <div className="m-chapter-picker">
          <button className={`m-chip-btn${chapterId === "" ? " active" : ""}`} onClick={() => { setChapterId(chapters[0]?.id ?? ""); setSuggestions(null); }}>
            {chapters[0] ? `第1章 ${chapters[0].title}` : "无章节"}
          </button>
          {chapters.slice(1).map((chapter) => (
            <button
              key={chapter.id}
              className={`m-chip-btn${chapterId === chapter.id ? " active" : ""}`}
              onClick={() => { setChapterId(chapter.id); setSuggestions(null); }}
            >第{chapter.idx + 1}章 {chapter.title}</button>
          ))}
        </div>
        <button className="m-primary m-wide" disabled={!chapterId || !!busy} onClick={() => void runClean()}>
          {busy === "生成清洗建议中…" ? "生成中…" : "🤖 生成清洗建议"}
        </button>
      </div>

      {suggestions && suggestions.length > 0 && (
        <div className="m-card">
          <div className="m-card-head">
            <h3>{suggestions.length} 条建议</h3>
            <span className="m-hint">已接受 {accepted}</span>
          </div>
          {CATEGORIES.map((category) => {
            const items = suggestions.filter((patch) => patch.category === category);
            if (!items.length) return null;
            return (
              <div key={category} className="m-category-block">
                <div className="m-category-head">
                  <span className={`m-chip cat-${category}`}>{category} {items.length}</span>
                  <div>
                    <button className="m-text-btn" onClick={() => setCategoryStatus(category, "accepted")}>全部接受</button>
                    <button className="m-text-btn" onClick={() => setCategoryStatus(category, "rejected")}>全部拒绝</button>
                  </div>
                </div>
                {items.map((patch, index) => (
                  <div className={`m-suggestion-card${patch.status === "accepted" ? " accepted" : patch.status === "rejected" ? " rejected" : ""}`} key={index}>
                    <p className="m-suggestion-original">{patch.original || "(空)"}</p>
                    <p className="m-suggestion-replacement">{patch.replacement || "(删除)"}</p>
                    <span className="m-hint">段 {patch.anchor.paraIndex + 1} · {patch.reason}</span>
                    <div className="m-inline-actions">
                      <button
                        className={patch.status === "accepted" ? "m-primary" : ""}
                        onClick={() => setPatchStatus(patch, "accepted")}
                      >接受</button>
                      <button
                        className={patch.status === "rejected" ? "m-danger" : ""}
                        onClick={() => setPatchStatus(patch, "rejected")}
                      >拒绝</button>
                    </div>
                  </div>
                ))}
              </div>
            );
          })}
          <div className="m-inline-actions">
            <button className="m-primary" disabled={!accepted || !!busy} onClick={() => void apply()}>应用已接受（{accepted}）</button>
            <button onClick={() => setSuggestions(null)}>放弃</button>
          </div>
        </div>
      )}

      {suggestions && suggestions.length === 0 && (
        <div className="m-card"><p className="m-hint">未发现可清洗项，可换一章试试。</p></div>
      )}

      <div className="m-card">
        <div className="m-card-head"><h3>结构修复</h3><span className="m-chip">可重跑</span></div>
        <p className="m-hint">按启发式重新切分全部章节并记录结构修订；低置信边界在真实供应商下由 LLM 复核。</p>
        <button className="m-wide" disabled={!!busy} onClick={() => void runStructure()}>
          {busy === "重新切分中…" ? "重切中…" : "🔄 重新切分章节"}
        </button>
      </div>

      <div className="m-card">
        <div className="m-card-head"><h3>修订批次</h3><span className="m-hint">{revisions.length} 条记录</span></div>
        {contentRevisions.length === 0 && <p className="m-hint">暂无可回滚的内容修订。</p>}
        {contentRevisions.map((revision) => (
          <div className="m-revision-row" key={revision.id}>
            <div>
              <strong>{revision.runId ? `批次 ${revision.runId.slice(0, 8)}` : "手动修订"}</strong>
              <span className="m-hint">{new Date(revision.createdAt).toLocaleString()} · {(revision.payload as { patches: ContentPatch[] }).patches.length} 条补丁</span>
            </div>
            <button className="m-danger" disabled={!!busy} onClick={() => void revert(revision)}>回滚批次</button>
          </div>
        ))}
      </div>
    </section>
  );
}
