import { useMemo, useRef, useState } from "react";
import { proposeStructure, splitChaptersWithAi, type ProposedChapter } from "@marginal/core";
import { confirmImport } from "../actions";
import { decodeText, store } from "../store";
import { mergeChapterUp, splitChapterAt } from "./logic";

interface ImportDraft {
  filename: string;
  text: string;
  chapters: ProposedChapter[];
}

export function MobileImport({ onBack, onImported }: { onBack: () => void; onImported: (workId: string) => void }) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [draft, setDraft] = useState<ImportDraft | null>(null);
  const [title, setTitle] = useState("");
  const [split, setSplit] = useState<{ index: number; line: number } | null>(null);
  const [busy, setBusy] = useState(false);
  const [aiBusy, setAiBusy] = useState(false);
  const lines = useMemo(() => draft?.text.split(/\r\n|\r|\n/) ?? [], [draft?.text]);

  async function loadFile(file: File) {
    const text = decodeText(await file.arrayBuffer());
    setDraft({ filename: file.name, text, chapters: proposeStructure(text) });
    setTitle(file.name.replace(/\.txt$/i, ""));
    setSplit(null);
  }

  async function loadSample() {
    setBusy(true);
    try {
      const text = await (await fetch("/sample-novel.txt")).text();
      await loadFile(new File([text], "sample-novel.txt", { type: "text/plain" }));
    } catch (error) {
      store.notify(`示例书加载失败：${error instanceof Error ? error.message : error}`);
    } finally {
      setBusy(false);
    }
  }

  function merge(index: number) {
    if (!draft) return;
    setDraft({ ...draft, chapters: mergeChapterUp(draft.chapters, index) });
    setSplit(null);
  }

  function startSplit(index: number) {
    if (!draft) return;
    const chapter = draft.chapters[index];
    const line = Math.max(chapter.startLine + 1, Math.min(chapter.endLine - 1, Math.floor((chapter.startLine + chapter.endLine) / 2)));
    setSplit({ index, line });
  }

  function adjustSplit(delta: number) {
    if (!draft || !split) return;
    const chapter = draft.chapters[split.index];
    setSplit({ ...split, line: Math.max(chapter.startLine + 1, Math.min(chapter.endLine - 1, split.line + delta)) });
  }

  function commitSplit() {
    if (!draft || !split) return;
    setDraft({ ...draft, chapters: splitChapterAt(draft.text, draft.chapters, split.index, split.line) });
    setSplit(null);
  }

  async function aiSplit() {
    if (!draft || aiBusy || busy) return;
    setAiBusy(true);
    try {
      const config = store.defaultTaskConfig("restructure");
      const { agent } = store.getAgent("restructure");
      const chapters = await splitChaptersWithAi(agent, config.model, draft.text);
      setDraft({ ...draft, chapters });
      store.notify(`AI 切分完成：${chapters.length} 章，请确认后导入`);
    } catch (error) {
      store.notify(`AI 切分失败：${error instanceof Error ? error.message : error}，已保留本地提案`);
    } finally {
      setAiBusy(false);
    }
  }

  async function confirm() {
    if (!draft || busy) return;
    setBusy(true);
    try {
      const work = await confirmImport(title, draft.filename, draft.text, draft.chapters);
      onImported(work.id);
    } catch (error) {
      store.notify(`导入失败：${error instanceof Error ? error.message : error}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="m-import-flow">
      <header className="m-flow-header">
        <button className="m-icon-btn" aria-label="返回书架" onClick={onBack}>‹</button>
        <h1>{draft ? "确认章节" : "导入小说"}</h1>
        {draft ? <button className="m-text-btn" onClick={() => { setDraft(null); setSplit(null); }}>重选</button> : <span />}
      </header>

      {!draft ? (
        <div className="m-import-start m-page">
          <div className="m-import-illustration"><span>TXT</span></div>
          <h2>把故事带到这里</h2>
          <p>支持 UTF-8 / GBK 编码的 TXT 小说。文件只在当前设备处理，不会上传。</p>
          <button className="m-primary m-wide" onClick={() => fileRef.current?.click()}>选择 TXT 文件</button>
          <button className="m-secondary m-wide" disabled={busy} onClick={() => void loadSample()}>{busy ? "加载中…" : "🧪 使用示例书"}</button>
          <input ref={fileRef} hidden type="file" accept=".txt,text/plain" onChange={(event) => event.target.files?.[0] && void loadFile(event.target.files[0])} />
          <div className="m-import-notes">
            <span>① 本地识别章节</span><span>② 手动检查切分</span><span>③ 确认后入库</span>
          </div>
        </div>
      ) : (
        <>
          <div className="m-import-preview m-page">
            <label className="m-field">
              <span>书稿名称</span>
              <input aria-label="书稿名称" value={title} onChange={(event) => setTitle(event.target.value)} />
            </label>
            <div className="m-preview-summary">
              <div><strong>{draft.chapters.length}</strong><span>章节</span></div>
              <div><strong>{draft.chapters.filter((chapter) => chapter.lowConfidence).length}</strong><span>低置信</span></div>
              <p>可并入上一章，或用步进器选择正文行拆分。</p>
              <button className="m-secondary m-wide" disabled={aiBusy || busy} onClick={() => void aiSplit()}>
                {aiBusy ? "AI 切分中…" : "✨ AI 智能切分（用「章节切分」任务的供应商）"}
              </button>
            </div>

            <div className="m-chapter-cards">
              {draft.chapters.map((chapter, index) => (
                <article className="m-chapter-card" key={`${chapter.startLine}-${chapter.endLine}-${index}`}>
                  <div className="m-chapter-number">{String(index + 1).padStart(2, "0")}</div>
                  <div className="m-chapter-main">
                    <h3>{chapter.title}</h3>
                    <p>{chapter.endLine - chapter.startLine} 行{chapter.lowConfidence ? " · 低置信" : ""}</p>
                    <div className="m-chapter-actions">
                      <button disabled={index === 0} onClick={() => merge(index)}>并入上一章</button>
                      <button disabled={chapter.endLine - chapter.startLine < 3} onClick={() => startSplit(index)}>拆分</button>
                    </div>
                    {split?.index === index && (
                      <div className="m-split-stepper">
                        <div className="m-stepper-row">
                          <button aria-label="拆分行减一" onClick={() => adjustSplit(-1)}>−</button>
                          <div><strong>第 {split.line + 1} 行</strong><span>{lines[split.line]?.trim().slice(0, 36) || "空行"}</span></div>
                          <button aria-label="拆分行加一" onClick={() => adjustSplit(1)}>＋</button>
                        </div>
                        <div className="m-inline-actions">
                          <button className="m-primary" onClick={commitSplit}>确认拆分</button>
                          <button onClick={() => setSplit(null)}>取消</button>
                        </div>
                      </div>
                    )}
                  </div>
                </article>
              ))}
            </div>
          </div>
          <footer className="m-sticky-footer">
            <button className="m-primary m-wide" disabled={busy || !title.trim()} onClick={() => void confirm()}>{busy ? "导入中…" : `确认导入 ${draft.chapters.length} 章`}</button>
          </footer>
        </>
      )}
    </section>
  );
}
