// 修复与修订（spec §4.2）：结构重切 + LLM 低置信复核；正文清洗建议 diff 审核；
// 修订历史与单条/整批回滚。

import { useCallback, useEffect, useState } from "react";
import { type ContentPatch, type Revision, type Work } from "@marginal/core";
import { store, useStore } from "../store";
import {
  applySuggestions as applySuggestionsAction,
  genCleanSuggestions,
  restructure as restructureAction,
  rollback as rollbackAction,
} from "../actions";

export function RepairView({ work }: { work: Work }) {
  useStore();
  const [chapters, setChapters] = useState<{ id: string; idx: number; title: string }[]>([]);
  const [chapterId, setChapterId] = useState("");
  const [suggestions, setSuggestions] = useState<ContentPatch[] | null>(null);
  const [revisions, setRevisions] = useState<Revision[]>([]);
  const [busy, setBusy] = useState("");

  const load = useCallback(async () => {
    const cs = await store.repo.listChapters(work.id);
    setChapters(cs.map((c) => ({ id: c.id, idx: c.idx, title: c.title })));
    if (!chapterId && cs[0]) setChapterId(cs[0].id);
    setRevisions(await store.repo.listRevisions(work.id));
  }, [work.id, chapterId]);

  useEffect(() => { void load(); }, [load]);

  /** 结构重切（自动 + 可重跑；spec §4.2） */
  async function restructure() {
    setBusy("重新切分中…");
    try {
      await restructureAction(work);
      setChapterId("");
      await load();
    } catch (err) {
      store.notify(`切分失败：${err instanceof Error ? err.message : err}`);
    } finally {
      setBusy("");
    }
  }

  /** 正文清洗建议（diff 审核制；spec §4.2） */
  async function clean() {
    if (!chapterId) return;
    setBusy("AI 生成清洗建议中…");
    try {
      setSuggestions(await genCleanSuggestions(work, chapterId));
      await load();
    } catch (err) {
      store.notify(`清洗失败：${err instanceof Error ? err.message : err}`);
    } finally {
      setBusy("");
    }
  }

  async function applySuggestions() {
    if (!suggestions || !chapterId) return;
    await applySuggestionsAction(work, chapterId, suggestions);
    setSuggestions(null);
    await load();
  }

  /** 回滚内容修订：逆补丁 + 原补丁标 undone（spec §4.2） */
  async function rollback(rev: Revision) {
    if (rev.kind !== "content") {
      store.notify("v1 暂不支持结构修订回滚（结构可重跑替代）");
      return;
    }
    await rollbackAction(work, rev);
    await load();
  }

  const cat = (c: string) => suggestions?.filter((s) => s.category === c) ?? [];
  const categories = ["乱码", "广告", "错字", "其他"] as const;

  return (
    <div>
      <div className="card">
        <b>结构修复</b>
        <p className="muted">启发式切分自动重跑，低置信区间可选 LLM 复核；重跑产生新结构修订，不覆盖历史。</p>
        <button className="primary" disabled={!!busy} onClick={restructure}>🔄 重新切分章节</button>{" "}
        {busy && <span className="muted">{busy}</span>}
      </div>

      <div className="card">
        <b>正文清洗（diff 审核制）</b>
        <div className="row" style={{ margin: "10px 0" }}>
          <select value={chapterId} onChange={(e) => { setChapterId(e.target.value); setSuggestions(null); }}>
            {chapters.map((c) => <option key={c.id} value={c.id}>{c.idx + 1}. {c.title}</option>)}
          </select>
          <button className="primary" disabled={!chapterId || !!busy} onClick={clean}>🤖 生成清洗建议</button>
          <span className="muted">建议不会直接改文，逐条/按类目审核后应用</span>
        </div>
        {suggestions && (
          <>
            {categories.filter((c) => cat(c).length).map((c) => (
              <div key={c} style={{ marginBottom: 8 }}>
                <div className="row">
                  <b>{c}</b> <span className="muted">{cat(c).length} 条</span>
                  <button onClick={() => setSuggestions(suggestions!.map((s) => (s.category === c ? { ...s, status: "accepted" } : s)))}>全接受</button>
                  <button onClick={() => setSuggestions(suggestions!.map((s) => (s.category === c ? { ...s, status: "rejected" } : s)))}>全拒绝</button>
                </div>
                {cat(c).map((s, i) => (
                  <div key={i} className="row" style={{ alignItems: "flex-start", padding: "4px 0", borderBottom: "1px solid #2a2e36" }}>
                    <input type="checkbox" checked={s.status === "accepted"} onChange={(e) =>
                      setSuggestions(suggestions!.map((x) => (x === s ? { ...x, status: e.target.checked ? "accepted" : "rejected" } : x)))
                    } />
                    <div style={{ flex: 1 }}>
                      <del style={{ color: "var(--danger)" }}>{s.original || "(空)"}</del>
                      {" → "}
                      <ins style={{ color: "var(--ok)" }}>{s.replacement || "(删除)"}</ins>
                      <div className="muted">段 {s.anchor.paraIndex + 1} · {s.reason}</div>
                    </div>
                  </div>
                ))}
              </div>
            ))}
            <div className="row">
              <button className="primary" onClick={applySuggestions}>应用已接受（{suggestions.filter((s) => s.status === "accepted").length} 条）</button>
              <button onClick={() => setSuggestions(null)}>放弃</button>
            </div>
          </>
        )}
      </div>

      <div className="card">
        <b>修订历史（只追加，可回滚）</b>
        <table className="list">
          <tbody>
            {revisions.length === 0 && <tr><td className="muted">暂无修订</td></tr>}
            {[...revisions].reverse().map((r) => (
              <tr key={r.id}>
                <td>{r.kind === "structure" ? "结构" : "内容"}</td>
                <td className="muted">{new Date(r.createdAt).toLocaleString()}</td>
                <td>{r.kind === "content" ? `${(r.payload as import("@marginal/core").ContentPayload).patches.length} 条补丁` : `${(r.payload as import("@marginal/core").StructurePayload).after.length} 章`}</td>
                <td>{r.runId ? <span className="badge">批次 {r.runId.slice(0, 6)}</span> : <span className="badge">手动</span>}</td>
                <td style={{ textAlign: "right" }}>
                  {r.kind === "content" && <button className="danger" onClick={() => rollback(r)}>回滚</button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
