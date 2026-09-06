// 书架：导入 TXT（切分预览 → 确认建书）、全书包导入/导出、删除。

import { useRef, useState } from "react";
import { decodeText, store, useStore } from "../store";
import { BUNDLE_EXT, buildBundle, proposeStructure, readBundle, reidForCopy, sliceChapterText, type ProposedChapter } from "@marginal/core";

export function LibraryView() {
  useStore();
  const [importing, setImporting] = useState<{ filename: string; text: string; chapters: ProposedChapter[] } | null>(null);
  const [bundleBusy, setBundleBusy] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const bundleRef = useRef<HTMLInputElement>(null);

  async function onFile(file: File) {
    const buf = await file.arrayBuffer();
    const text = decodeText(buf);
    const chapters = proposeStructure(text); // 纯本地启发式，预览界面必经（spec §4.2）
    setImporting({ filename: file.name, text, chapters });
  }

  async function confirmImport(title: string) {
    if (!importing) return;
    const chapterData = importing.chapters.map((c) => ({ title: c.title, text: sliceChapterText(importing.text, c.startLine, c.endLine) }));
    const work = await store.createWorkFromText(title || importing.filename.replace(/\.txt$/i, ""), importing.filename, importing.text, chapterData);
    setImporting(null);
    store.notify(`已导入 ${chapterData.length} 章`);
    store.navigate({ name: "work", workId: work.id, tab: "reader" });
  }

  async function exportBundle(workId: string) {
    setBundleBusy(true);
    try {
      const repo = store.repo;
      const work = await repo.getWork(workId);
      if (!work) return;
      const chapters = await repo.listChapters(workId);
      const chapterTexts: Record<string, string> = {};
      for (const c of chapters) chapterTexts[c.id] = await repo.getChapterText(c.id);
      const blobs = await repo.listBlobs(workId);
      const revisions = await repo.listRevisions(workId);
      const runs = await repo.listRuns(workId);
      const cards = await repo.listEntityCards(workId);
      const illus = await repo.listIllustrations(workId);
      const anchors = await repo.listAnchors(workId);
      const blobData: Record<string, Uint8Array> = {};
      for (const b of blobs) {
        const data = await repo.getBlobData(b.storageKey);
        if (data) blobData[b.storageKey] = data;
      }
      const zip = buildBundle({ work, chapters, chapterTexts, runs, revisions, entityCards: cards, illustrations: illus, anchors, blobs }, blobData);
      const url = URL.createObjectURL(new Blob([zip as BlobPart], { type: "application/octet-stream" }));
      const a = document.createElement("a");
      a.href = url;
      a.download = `${work.title}${BUNDLE_EXT}`;
      a.click();
      URL.revokeObjectURL(url);
      store.notify("全书包已导出");
    } finally {
      setBundleBusy(false);
    }
  }

  async function importBundleFile(file: File) {
    setBundleBusy(true);
    try {
      const zipBytes = new Uint8Array(await file.arrayBuffer());
      const { payload, blobData } = readBundle(zipBytes);
      const existing = (await store.repo.listWorks()).map((w) => w.id);
      const mode = await new Promise<"replace" | "copy">((resolve) => {
        const exists = existing.includes(payload.manifest.workId);
        if (!exists) return resolve("replace");
        const same = true; // v1：不做逐字段比对，直接提供二选一
        void same;
        const choice = window.prompt(
          `该书已存在。输入 1 覆盖本地版本，输入 2 作为副本导入：`,
          "2",
        );
        resolve(choice === "1" ? "replace" : "copy");
      });
      const finalPayload = mode === "copy" ? reidForCopy(payload) : payload;
      await store.repo.importBundle(finalPayload, blobData, mode, existing);
      await store.refreshWorks();
      store.notify("全书包已导入");
    } catch (err) {
      store.notify(`导入失败：${err instanceof Error ? err.message : err}`);
    } finally {
      setBundleBusy(false);
    }
  }

  return (
    <div>
      <div className="card row">
        <button className="primary" onClick={() => fileRef.current?.click()}>📥 导入 TXT 小说</button>
        <button onClick={async () => {
          const res = await fetch("/sample-novel.txt");
          const text = await res.text();
          await onFile(new File([text], "sample-novel.txt", { type: "text/plain" }));
        }}>🧪 导入示例书（含广告/乱码/错字）</button>
        <button disabled={bundleBusy} onClick={() => bundleRef.current?.click()}>📦 导入全书包</button>
        <input ref={fileRef} type="file" accept=".txt" hidden onChange={(e) => e.target.files?.[0] && onFile(e.target.files[0])} />
        <input ref={bundleRef} type="file" accept={BUNDLE_EXT} hidden onChange={(e) => e.target.files?.[0] && importBundleFile(e.target.files[0])} />
        <span className="muted">v1 仅 TXT（UTF-8 / GBK 自动检测）· 全书包 .mabk 用于双端手动同步</span>
      </div>
      <div className="card">
        {store.works.length === 0 && <div className="muted">书架还是空的——先导入一本小说。</div>}
        <table className="list">
          <tbody>
            {store.works.map((w) => (
              <tr key={w.id}>
                <td style={{ width: "45%" }}><b>{w.title}</b></td>
                <td className="muted">{w.importSource}</td>
                <td className="muted">{new Date(w.updatedAt).toLocaleString()}</td>
                <td style={{ textAlign: "right" }}>
                  <button className="primary" onClick={() => store.navigate({ name: "work", workId: w.id, tab: "reader" })}>打开</button>{" "}
                  <button disabled={bundleBusy} onClick={() => exportBundle(w.id)}>导出全书包</button>{" "}
                  <button className="danger" onClick={() => window.confirm(`删除《${w.title}》及其全部数据？`) && store.deleteWork(w.id)}>删除</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {importing && <SplitPreview importing={importing} onCancel={() => setImporting(null)} onConfirm={confirmImport} />}
    </div>
  );
}

function SplitPreview({ importing, onCancel, onConfirm }: {
  importing: { filename: string; text: string; chapters: ProposedChapter[] };
  onCancel: () => void;
  onConfirm: (title: string) => void;
}) {
  const [chapters, setChapters] = useState(importing.chapters);
  const [title, setTitle] = useState(importing.filename.replace(/\.txt$/i, ""));

  function mergeUp(i: number) {
    if (i <= 0) return;
    const next = [...chapters];
    next[i - 1] = { ...next[i - 1], endLine: next[i].endLine };
    next.splice(i, 1);
    setChapters(next);
  }
  function splitAt(i: number, relLine: number) {
    const ch = chapters[i];
    if (relLine <= ch.startLine || relLine >= ch.endLine) return;
    const text = importing.text.split(/\r\n|\r|\n/);
    const next = [...chapters];
    next.splice(i, 1,
      { title: text[relLine]?.trim().slice(0, 60) || `部分 ${relLine}`, startLine: ch.startLine, endLine: relLine, lowConfidence: false },
      { title: "（未命名）", startLine: relLine, endLine: ch.endLine, lowConfidence: false });
    setChapters(next);
  }

  const lowCount = chapters.filter((c) => c.lowConfidence).length;
  return (
    <div className="modal-mask">
      <div className="modal">
        <h3>切分预览 —— 确认后才应用（spec §4.2）</h3>
        <div className="row" style={{ marginBottom: 10 }}>
          <label>书名：<input value={title} onChange={(e) => setTitle(e.target.value)} /></label>
          <span className="muted">{chapters.length} 章{lowCount > 0 ? ` · ${lowCount} 章低置信（可导入后用 LLM 复核）` : ""}</span>
        </div>
        <div style={{ maxHeight: "46vh", overflow: "auto" }}>
          <table className="list">
            <tbody>
              {chapters.map((c, i) => (
                <tr key={i}>
                  <td>{i + 1}</td>
                  <td>{c.title}</td>
                  <td className="muted">{c.endLine - c.startLine} 行{c.lowConfidence ? " · 低置信" : ""}</td>
                  <td>
                    <button disabled={i === 0} onClick={() => mergeUp(i)}>并入上一章</button>{" "}
                    <button onClick={() => {
                      const line = window.prompt(`在第 ${c.startLine + 1}~${c.endLine} 行内选择拆分行号：`, String(Math.floor((c.startLine + c.endLine) / 2)));
                      if (line) splitAt(i, parseInt(line, 10));
                    }}>拆分</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="row" style={{ marginTop: 14 }}>
          <button className="primary" onClick={() => onConfirm(title)}>确认导入</button>
          <button onClick={onCancel}>取消</button>
        </div>
      </div>
    </div>
  );
}
