// 阅读器：CSS 多栏分页 + 段落锚点图文混排（prototype/reader 验证过的方案）。
// 实现必记两坑（spec §4.3）：栏距=视口宽−栏宽；插图 max-height 适配栏高。

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { splitParagraphs, type Anchor, type Work } from "@marginal/core";
import { store, useStore } from "../store";
import { generateIllustration as generateIllustrationAction } from "../actions";
import { IllustrationImage } from "./IllustrationImage";

export function ReaderView({ work }: { work: Work }) {
  const version = useStore();
  const [chapters, setChapters] = useState<{ id: string; idx: number; title: string }[]>([]);
  const [chapterId, setChapterId] = useState<string>("");
  const [text, setText] = useState("");
  const [anchors, setAnchors] = useState<Anchor[]>([]);
  const [fontSize, setFontSize] = useState(19);
  const [theme, setTheme] = useState<"paper" | "dark">("paper");
  const [selectedPara, setSelectedPara] = useState<number | null>(null);
  const [illusPrompt, setIllusPrompt] = useState<{ paraIndex: number; text: string } | null>(null);
  const viewportRef = useRef<HTMLDivElement>(null);
  const pagesRef = useRef<HTMLDivElement>(null);
  const pageRef = useRef(0);
  const pageCountRef = useRef(1);

  const paragraphs = useMemo(() => splitParagraphs(text), [text]);

  const load = useCallback(async () => {
    const cs = await store.repo.listChapters(work.id);
    setChapters(cs.map((c) => ({ id: c.id, idx: c.idx, title: c.title })));
    const target = cs.find((c) => c.id === chapterId) ?? cs[0];
    if (!target) {
      setText("");
      return;
    }
    setChapterId(target.id);
    setText(await store.repo.getChapterText(target.id));
    setAnchors((await store.repo.listAnchors(work.id)).filter((a) => a.chapterId === (target?.id ?? "") && a.state === "active"));
  }, [work.id, chapterId, version]);

  useEffect(() => {
    void load();
  }, [load]);

  // 分页：栏宽 = 视口宽 − 2×padding；栏距 = 2×padding（步进 = 视口宽，spec 坑 1）
  const paginate = useCallback(() => {
    const vp = viewportRef.current;
    const pages = pagesRef.current;
    if (!vp || !pages) return;
    const w = vp.clientWidth;
    pages.style.setProperty("--page-w", `${w - 64}px`);
    pages.style.setProperty("--page-gap", `64px`);
    pageCountRef.current = Math.max(1, Math.round((pages.scrollWidth + 64) / w));
    applyOffset();
  }, []);

  const applyOffset = useCallback(() => {
    const vp = viewportRef.current;
    const pages = pagesRef.current;
    if (!vp || !pages) return;
    pageRef.current = Math.max(0, Math.min(pageCountRef.current - 1, pageRef.current));
    pages.style.transform = `translateX(${-pageRef.current * vp.clientWidth}px)`;
    const el = document.getElementById("page-indicator");
    if (el) el.textContent = `第 ${pageRef.current + 1} / ${pageCountRef.current} 页`;
  }, []);

  useEffect(() => {
    paginate();
    const ro = new ResizeObserver(() => paginate());
    if (viewportRef.current) ro.observe(viewportRef.current);
    return () => ro.disconnect();
  }, [paginate, text, fontSize, theme, anchors]);

  function go(d: number) {
    pageRef.current += d;
    applyOffset();
  }

  // 在段落锚点处渲染插图（Range 方式的 React 简化版：anchor 段落后插入 <img>）
  const anchorByPara = useMemo(() => {
    const m = new Map<number, Anchor>();
    for (const a of anchors) m.set(a.paraIndex, a);
    return m;
  }, [anchors]);

  async function generateIllustration(paraIndex: number, sceneDescription: string) {
    await generateIllustrationAction(work, chapterId, paraIndex, sceneDescription);
    setIllusPrompt(null);
  }

  const themeVars = theme === "paper"
    ? { "--theme-bg": "#f5efdf", "--theme-fg": "#3a3226" }
    : { "--theme-bg": "#1a1c20", "--theme-fg": "#c9c4b8" };

  return (
    <div>
      <div className="reader-toolbar">
        <select value={chapterId} onChange={(e) => { setChapterId(e.target.value); pageRef.current = 0; }}>
          {chapters.map((c) => <option key={c.id} value={c.id}>{c.idx + 1}. {c.title}</option>)}
        </select>
        <button onClick={() => { setFontSize((f) => f + 2); }}>A+</button>
        <button onClick={() => setFontSize((f) => Math.max(12, f - 2))}>A−</button>
        <button onClick={() => setTheme((t) => (t === "paper" ? "dark" : "paper"))}>{theme === "paper" ? "🌙 夜间" : "☀️ 纸质"}</button>
        <button onClick={() => go(-1)}>← 上一页</button>
        <button onClick={() => go(1)}>下一页 →</button>
        <span id="page-indicator" className="muted">计算中…</span>
        <span className="muted" style={{ marginLeft: "auto" }}>点击段落 → 在此配图</span>
      </div>
      <div id="reader-viewport" ref={viewportRef} style={themeVars as React.CSSProperties}>
        <div className="tap-zone" style={{ left: 0 }} onClick={() => go(-1)} />
        <div className="tap-zone" style={{ right: 0 }} onClick={() => go(1)} />
        <div id="reader-pages" ref={pagesRef} style={{ fontSize }}>
          <h2 style={{ textAlign: "center", margin: "1em 0" }}>{chapters.find((c) => c.id === chapterId)?.title ?? ""}</h2>
          {paragraphs.map((p, i) => {
            const anchor = anchorByPara.get(i);
            return (
              <div key={i} data-p={i}>
                <p
                  className={selectedPara === i ? "sel" : ""}
                  onClick={() => setSelectedPara(selectedPara === i ? null : i)}
                >
                  {p}
                  {anchor && <span> <span className="anchor-mark">◆</span></span>}
                </p>
                {selectedPara === i && (
                  <div style={{ textIndent: 0 }}>
                    <button onClick={() => setIllusPrompt({ paraIndex: i, text: p.slice(0, 120) })}>🎨 在此段配图</button>
                  </div>
                )}
                {anchor && <IllustrationImage anchor={anchor} workId={work.id} />}
              </div>
            );
          })}
        </div>
      </div>
      {illusPrompt && (
        <div className="modal-mask" onClick={() => setIllusPrompt(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h3>为该段落生成插图（spec §4.4）</h3>
            <p className="muted">{illusPrompt.text}…</p>
            <IllusPromptForm
              defaultScene={illusPrompt.text}
              onSubmit={(scene) => generateIllustration(illusPrompt.paraIndex, scene)}
              onCancel={() => setIllusPrompt(null)}
            />
          </div>
        </div>
      )}
    </div>
  );
}

function IllusPromptForm({ defaultScene, onSubmit, onCancel }: { defaultScene: string; onSubmit: (scene: string) => void; onCancel: () => void }) {
  const [scene, setScene] = useState(defaultScene);
  return (
    <div>
      <textarea value={scene} onChange={(e) => setScene(e.target.value)} style={{ width: "100%", minHeight: 80 }} />
      <p className="muted">正典实体卡的定妆照将作为参考图（最多 3 张）传入；无正典卡时为草稿质量。</p>
      <div className="row">
        <button className="primary" onClick={() => onSubmit(scene)}>加入生成队列</button>
        <button onClick={onCancel}>取消</button>
      </div>
    </div>
  );
}
