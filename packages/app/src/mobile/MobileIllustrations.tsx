import { useCallback, useEffect, useState } from "react";
import { pickCandidateParagraphs, type Illustration, type Work } from "@marginal/core";
import { enqueueIllustrations, setBudgetLimit } from "../actions";
import { store, useStore } from "../store";
import { BlobImage } from "./shared";

interface Candidate {
  chapterKey: string;
  paraIndex: number;
  preview: string;
  chapterTitle: string;
}

export function MobileIllustrations({ work }: { work: Work }) {
  const version = useStore();
  const [chapters, setChapters] = useState<{ id: string; idx: number; title: string }[]>([]);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const [budget, setBudget] = useState(work.settings.budgetLimit);
  const [illus, setIllus] = useState<Illustration[]>([]);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setChapters(await store.repo.listChapters(work.id));
    setIllus(await store.repo.listIllustrations(work.id));
    setBudget((await store.repo.getWork(work.id))?.settings.budgetLimit ?? 0);
  }, [work.id, version]);
  useEffect(() => { void load(); }, [load]);

  async function scan() {
    setBusy(true);
    try {
      const all = await store.repo.listChapters(work.id);
      const texts = Object.fromEntries(await Promise.all(all.map(async (chapter) => [chapter.id, await store.repo.getChapterText(chapter.id)] as const)));
      const list = pickCandidateParagraphs(texts).slice(0, 60);
      const titleMap = new Map(all.map((chapter) => [chapter.id, chapter.title]));
      const view: Candidate[] = list.map((item) => ({
        ...item,
        chapterTitle: titleMap.get(item.chapterKey) ?? "",
        preview: `《${titleMap.get(item.chapterKey) ?? ""}》段${item.paraIndex + 1}: ${item.preview}`,
      }));
      setCandidates(view);
      setSelected(new Set(view.map((item) => `${item.chapterKey}:${item.paraIndex}`)));
      store.notify(`预扫到 ${view.length} 个候选段落，勾选后入队`);
    } finally {
      setBusy(false);
    }
  }

  function toggleKey(key: string) {
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(key)) next.delete(key); else next.add(key);
      return next;
    });
  }

  async function enqueue() {
    const list = candidates.filter((item) => selected.has(`${item.chapterKey}:${item.paraIndex}`));
    setBusy(true);
    try {
      await enqueueIllustrations(work, list);
      setCandidates([]);
      setSelected(new Set());
      await load();
    } finally {
      setBusy(false);
    }
  }

  async function adjustBudget(delta: number) {
    const next = Math.max(0, budget + delta);
    setBudget(next);
    await setBudgetLimit(work, next);
    await load();
  }

  const accepted = illus.filter((item) => item.status === "accepted");
  const drafts = illus.filter((item) => item.status === "draft");

  return (
    <section className="m-page m-illustrations">
      <div className="m-card">
        <div className="m-card-head"><h3>段落插图</h3><span className="m-chip">{illus.length}</span></div>
        <p className="m-hint">选择候选段落入队生成；正典实体卡的定妆照将作为参考图。</p>
        <button className="m-primary m-wide" disabled={busy} onClick={() => void scan()}>🔍 预扫候选段落</button>
      </div>

      {candidates.length > 0 && (
        <div className="m-card">
          <div className="m-card-head">
            <h3>候选段落</h3>
            <span className="m-hint">已选 {selected.size}</span>
          </div>
          <div className="m-candidate-list">
            {candidates.map((item, index) => {
              const key = `${item.chapterKey}:${item.paraIndex}`;
              return (
                <label className="m-candidate-item" key={index}>
                  <input type="checkbox" checked={selected.has(key)} onChange={(event) => toggleKey(key)} />
                  <span>{item.preview}</span>
                </label>
              );
            })}
          </div>
          <button className="m-primary m-wide" disabled={!selected.size || busy} onClick={() => void enqueue()}>
            🖼 入队生成（{selected.size}）
          </button>
        </div>
      )}

      <div className="m-card">
        <div className="m-card-head"><h3>预算上限</h3><span className="m-hint">触顶自动暂停</span></div>
        <div className="m-budget-row">
          <button aria-label="减少预算" onClick={() => void adjustBudget(-5)}>−</button>
          <div><strong>{budget || "不设限"}</strong><span>{budget ? "次调用" : "未设上限"}</span></div>
          <button aria-label="增加预算" onClick={() => void adjustBudget(5)}>＋</button>
        </div>
        <p className="m-hint">设置后对下一次/当前入队的插图任务生效。</p>
      </div>

      {accepted.length > 0 && (
        <div className="m-card">
          <div className="m-card-head"><h3>已接受</h3><span className="m-chip ok">{accepted.length}</span></div>
          <div className="m-illus-grid">
            {accepted.map((item) => (
              <div key={item.id} className="m-illus-item">
                <BlobImage workId={work.id} blobId={item.blobId} alt={item.prompt.slice(0, 20)} className="m-illus-thumb" />
              </div>
            ))}
          </div>
        </div>
      )}

      {drafts.length > 0 && (
        <div className="m-card">
          <div className="m-card-head"><h3>草稿</h3><span className="m-chip">{drafts.length}</span></div>
          <div className="m-illus-grid">
            {drafts.map((item) => (
              <div key={item.id} className="m-illus-item">
                <BlobImage workId={work.id} blobId={item.blobId} alt={item.prompt.slice(0, 20)} className="m-illus-thumb" />
              </div>
            ))}
          </div>
        </div>
      )}

      {illus.length === 0 && !busy && (
        <div className="m-empty-card"><span className="m-empty-icon">🖼</span><strong>还没有插图</strong><small>先预扫候选段落</small></div>
      )}
    </section>
  );
}
