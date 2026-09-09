import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { splitParagraphs, type Anchor, type Work } from "@marginal/core";
import { generateIllustration } from "../actions";
import { store, useStore } from "../store";
import { IllustrationImage } from "../components/IllustrationImage";
import { ActionSheet, BottomSheet, MiniQueueProgress } from "./shared";
import {
  clampFontSize, listFavorites, loadReadingPosition, saveFavorites, saveReadingPosition,
  scrollRatio, scrollTopForRatio, toggleFavorite, type ParagraphFavorite,
} from "./logic";
import type { MobileWorkTab } from "./types";

const FONT_KEY = "marginal.reader.fontSize.v1";
const THEME_KEY = "marginal.reader.theme.v1";

export function MobileReader({
  work,
  onBack,
  onOpenWorkTab,
}: {
  work: Work;
  onBack: () => void;
  onOpenWorkTab: (tab: MobileWorkTab) => void;
}) {
  const version = useStore();
  const [chapters, setChapters] = useState<{ id: string; idx: number; title: string }[]>([]);
  const [chapterId, setChapterId] = useState("");
  const [text, setText] = useState("");
  const [anchors, setAnchors] = useState<Anchor[]>([]);
  const [chrome, setChrome] = useState(true);
  const [showChapters, setShowChapters] = useState(false);
  const [scene, setScene] = useState<{ paraIndex: number; text: string } | null>(null);
  const [fontSize, setFontSize] = useState(() => clampFontSize(Number(localStorage.getItem(FONT_KEY)) || 19));
  const [theme, setTheme] = useState<"paper" | "dark">(
    () => (localStorage.getItem(THEME_KEY) === "dark" ? "dark" : "paper"),
  );
  const [progress, setProgress] = useState(0);
  const [menu, setMenu] = useState(false);
  const [paraMenu, setParaMenu] = useState<{ paraIndex: number; text: string } | null>(null);
  const [favorites, setFavorites] = useState<ParagraphFavorite[]>([]);
  const [showFavorites, setShowFavorites] = useState(false);
  const viewportRef = useRef<HTMLDivElement>(null);
  const chapterIdRef = useRef("");
  const restoredRef = useRef(false);
  const ratioRef = useRef(0);
  const saveTimer = useRef<number | null>(null);

  const paragraphs = useMemo(() => splitParagraphs(text), [text]);
  const anchorByPara = useMemo(() => {
    const map = new Map<number, Anchor>();
    for (const anchor of anchors) map.set(anchor.paraIndex, anchor);
    return map;
  }, [anchors]);
  const favParas = useMemo(
    () => new Set(favorites.filter((item) => item.chapterId === chapterId).map((item) => item.paraIndex)),
    [favorites, chapterId],
  );

  const scrollTo = useCallback((ratio: number) => {
    const viewport = viewportRef.current;
    if (!viewport) return;
    viewport.scrollTop = scrollTopForRatio(ratio, viewport.scrollHeight, viewport.clientHeight);
  }, []);

  const loadChapter = useCallback(async (id: string, ratio: number) => {
    chapterIdRef.current = id;
    setChapterId(id);
    setText(await store.repo.getChapterText(id));
    setAnchors((await store.repo.listAnchors(work.id)).filter((anchor) => anchor.chapterId === id && anchor.state === "active"));
    setProgress(ratio);
    ratioRef.current = ratio;
    requestAnimationFrame(() => requestAnimationFrame(() => scrollTo(ratio)));
  }, [work.id, scrollTo]);

  // 首次进入：恢复上次阅读位置
  useEffect(() => {
    void (async () => {
      const all = await store.repo.listChapters(work.id);
      setChapters(all.map((chapter) => ({ id: chapter.id, idx: chapter.idx, title: chapter.title })));
      setFavorites(listFavorites(localStorage, work.id));
      const saved = loadReadingPosition(localStorage, work.id);
      const target = all.find((chapter) => chapter.id === saved?.chapterId) ?? all[0];
      if (target) {
        await loadChapter(target.id, saved && target.id === saved.chapterId ? saved.scrollRatio : 0);
      }
      restoredRef.current = true;
    })();
    return () => {
      if (chapterIdRef.current) {
        saveReadingPosition(localStorage, work.id, { chapterId: chapterIdRef.current, scrollRatio: ratioRef.current });
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [work.id]);

  // 队列有新插图落地时刷新锚点（不重置滚动位置）
  useEffect(() => {
    if (!restoredRef.current || !chapterIdRef.current) return;
    void (async () => {
      setChapters((await store.repo.listChapters(work.id)).map((chapter) => ({ id: chapter.id, idx: chapter.idx, title: chapter.title })));
      setAnchors((await store.repo.listAnchors(work.id)).filter((anchor) => anchor.chapterId === chapterIdRef.current && anchor.state === "active"));
    })();
  }, [version, work.id]);

  function onScroll() {
    const viewport = viewportRef.current;
    if (!viewport) return;
    const ratio = scrollRatio(viewport.scrollTop, viewport.scrollHeight, viewport.clientHeight);
    ratioRef.current = ratio;
    setProgress(ratio);
    if (saveTimer.current) window.clearTimeout(saveTimer.current);
    saveTimer.current = window.setTimeout(() => {
      if (chapterIdRef.current) {
        saveReadingPosition(localStorage, work.id, { chapterId: chapterIdRef.current, scrollRatio: ratioRef.current });
      }
    }, 400);
  }

  function pickChapter(id: string) {
    setShowChapters(false);
    if (id === chapterId) return;
    void loadChapter(id, 0);
  }

  function stepChapter(delta: number) {
    const index = chapters.findIndex((chapter) => chapter.id === chapterId);
    const next = chapters[index + delta];
    if (next) void loadChapter(next.id, 0);
  }

  function changeFont(delta: number) {
    setFontSize((current) => {
      const next = clampFontSize(current + delta);
      localStorage.setItem(FONT_KEY, String(next));
      return next;
    });
  }

  function toggleTheme() {
    setTheme((current) => {
      const next = current === "paper" ? "dark" : "paper";
      localStorage.setItem(THEME_KEY, next);
      return next;
    });
  }

  async function enqueueIllustration(paraIndex: number, sceneText: string) {
    setScene(null);
    await generateIllustration(work, chapterIdRef.current, paraIndex, sceneText);
  }

  function toggleCurrentFavorite(paraIndex: number, paraText: string) {
    const chapter = chapters.find((item) => item.id === chapterIdRef.current);
    const { favorites: next, added } = toggleFavorite(localStorage, work.id, {
      chapterId: chapterIdRef.current,
      chapterTitle: chapter?.title ?? "",
      paraIndex,
      text: paraText,
      savedAt: Date.now(),
    });
    setFavorites(next);
    store.notify(added ? "段落已收藏" : "已取消收藏");
  }

  function removeFavorite(favorite: ParagraphFavorite) {
    const next = favorites.filter(
      (item) => !(item.chapterId === favorite.chapterId && item.paraIndex === favorite.paraIndex),
    );
    saveFavorites(localStorage, work.id, next);
    setFavorites(next);
  }

  function jumpToFavorite(favorite: ParagraphFavorite) {
    setShowFavorites(false);
    if (favorite.chapterId !== chapterIdRef.current) {
      void loadChapter(favorite.chapterId, 0).then(() => scrollParaIntoView(favorite.paraIndex));
    } else {
      scrollParaIntoView(favorite.paraIndex);
    }
  }

  function scrollParaIntoView(paraIndex: number) {
    requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(() => {
      document.getElementById(`m-para-${paraIndex}`)?.scrollIntoView({ block: "center" });
    })));
  }

  async function shareParagraph(paraText: string) {
    const payload = `《${work.title}》精彩段落：\n${paraText}`;
    if (typeof navigator.share === "function") {
      try {
        await navigator.share({ title: work.title, text: payload });
        return;
      } catch (error) {
        if (error instanceof DOMException && error.name === "AbortError") return;
      }
    }
    store.notify((await copyText(payload)) ? "段落已复制，可粘贴分享" : "复制失败，请手动选择文本");
  }

  const chapterTitle = chapters.find((chapter) => chapter.id === chapterId)?.title ?? "";

  return (
    <section className={`m-reader theme-${theme}`} aria-label="阅读器">
      <div
        ref={viewportRef}
        className="m-reader-scroll"
        onScroll={onScroll}
        style={{ fontSize }}
      >
        <h2 className="m-reader-title">{chapterTitle}</h2>
        {paragraphs.map((paragraph, index) => {
          const anchor = anchorByPara.get(index);
          return (
            <div key={index}>
              <p id={`m-para-${index}`} className="m-reader-para" onClick={() => setParaMenu({ paraIndex: index, text: paragraph })}>
                {paragraph}
                {anchor && <span className="m-anchor-mark">◆</span>}
                {favParas.has(index) && <span className="m-fav-mark">★</span>}
              </p>
              {anchor && <IllustrationImage anchor={anchor} workId={work.id} />}
            </div>
          );
        })}
        {chapters.length > 0 && (
          <div className="m-reader-end">
            {chapters.findIndex((chapter) => chapter.id === chapterId) === chapters.length - 1
              ? "已读到最后一章"
              : "本章完 · 点击底部「下一章」继续"}
          </div>
        )}
      </div>

      <button
        type="button"
        className="m-reader-tap-toggle"
        aria-label="切换阅读工具栏"
        onClick={() => setChrome((value) => !value)}
      />

      {chrome && (
        <>
          <header className="m-reader-top">
            <button className="m-icon-btn" aria-label="返回书架" onClick={onBack}>‹</button>
            <div className="m-reader-heading"><strong>{work.title}</strong><span>{chapterTitle}</span></div>
            <button className="m-icon-btn" aria-label="章节目录" onClick={() => setShowChapters(true)}>☰</button>
            <button className="m-icon-btn" aria-label="更多操作" onClick={() => setMenu(true)}>⋯</button>
          </header>
          <footer className="m-reader-bottom">
            <div className="m-reader-progress-row">
              <span>本章 {Math.round(progress * 100)}%</span>
              <div className="m-progress-track"><div style={{ width: `${Math.round(progress * 100)}%` }} /></div>
              <span>{chapters.findIndex((chapter) => chapter.id === chapterId) + 1}/{chapters.length}</span>
            </div>
            <div className="m-reader-actions">
              <button onClick={() => stepChapter(-1)} disabled={chapters.findIndex((chapter) => chapter.id === chapterId) <= 0}>上一章</button>
              <button aria-label="减小字号" onClick={() => changeFont(-2)}>A−</button>
              <button aria-label="增大字号" onClick={() => changeFont(2)}>A＋</button>
              <button onClick={toggleTheme}>{theme === "paper" ? "🌙 夜间" : "☀️ 日间"}</button>
              <button onClick={() => stepChapter(1)} disabled={chapters.findIndex((chapter) => chapter.id === chapterId) === chapters.length - 1}>下一章</button>
            </div>
            <MiniQueueProgress />
          </footer>
        </>
      )}

      {showChapters && (
        <BottomSheet title="章节目录" onClose={() => setShowChapters(false)}>
          <div className="m-chapter-list">
            {chapters.map((chapter) => (
              <button key={chapter.id} className={chapter.id === chapterId ? "active" : ""} onClick={() => pickChapter(chapter.id)}>
                <span>{chapter.idx + 1}</span>{chapter.title}
              </button>
            ))}
          </div>
        </BottomSheet>
      )}

      {paraMenu && (
        <ActionSheet
          title={`第 ${paraMenu.paraIndex + 1} 段`}
          onClose={() => setParaMenu(null)}
          actions={[
            { icon: "🎨", label: "为段落配图", onClick: () => setScene({ paraIndex: paraMenu.paraIndex, text: paraMenu.text.slice(0, 120) }) },
            {
              icon: favParas.has(paraMenu.paraIndex) ? "✨" : "⭐",
              label: favParas.has(paraMenu.paraIndex) ? "取消收藏" : "收藏段落",
              onClick: () => toggleCurrentFavorite(paraMenu.paraIndex, paraMenu.text),
            },
            { icon: "📤", label: "分享段落", onClick: () => void shareParagraph(paraMenu.text) },
          ]}
        />
      )}

      {scene && (
        <BottomSheet title="为段落配图" onClose={() => setScene(null)}>
          <p className="m-scene-preview">{scene.text}…</p>
          <IllustrationSceneForm
            key={scene.paraIndex}
            defaultScene={scene.text}
            onSubmit={(value) => void enqueueIllustration(scene.paraIndex, value)}
            onCancel={() => setScene(null)}
          />
        </BottomSheet>
      )}

      {showFavorites && (
        <BottomSheet title={`精彩段落（${favorites.length}）`} onClose={() => setShowFavorites(false)}>
          {favorites.length === 0 && <p className="m-hint">还没有收藏。点按正文段落即可收藏或分享。</p>}
          <div className="m-fav-list">
            {favorites.map((favorite) => (
              <div key={`${favorite.chapterId}:${favorite.paraIndex}`} className="m-fav-item">
                <p className="m-fav-text" onClick={() => jumpToFavorite(favorite)}>{favorite.text}</p>
                <div className="m-fav-meta">
                  <span>{favorite.chapterTitle || "章节"}</span>
                  <div>
                    <button onClick={() => jumpToFavorite(favorite)}>去阅读</button>
                    <button onClick={() => void shareParagraph(favorite.text)}>分享</button>
                    <button onClick={() => removeFavorite(favorite)}>删除</button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </BottomSheet>
      )}

      {menu && (
        <BottomSheet title={work.title} onClose={() => setMenu(false)}>
          <div className="m-stack-actions">
            <button onClick={() => { setMenu(false); onOpenWorkTab("repair"); }}>🔧 修复与修订</button>
            <button onClick={() => { setMenu(false); onOpenWorkTab("entities"); }}>👤 实体卡</button>
            <button onClick={() => { setMenu(false); onOpenWorkTab("illustrations"); }}>🖼 插图任务</button>
            <button onClick={() => { setMenu(false); setShowFavorites(true); }}>⭐ 精彩段落</button>
            <button onClick={() => { setMenu(false); onBack(); }}>📚 回到书架</button>
          </div>
        </BottomSheet>
      )}
    </section>
  );
}

async function copyText(text: string): Promise<boolean> {
  try {
    if (navigator.clipboard) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    // 局域网 HTTP 或剪贴板权限被拒时，退回传统复制方式。
  }
  const area = document.createElement("textarea");
  area.value = text;
  area.style.position = "fixed";
  area.style.opacity = "0";
  document.body.appendChild(area);
  area.select();
  const copied = document.execCommand("copy");
  area.remove();
  return copied;
}

function IllustrationSceneForm({ defaultScene, onSubmit, onCancel }: { defaultScene: string; onSubmit: (value: string) => void; onCancel: () => void }) {
  const [value, setValue] = useState(defaultScene);
  return (
    <div>
      <label className="m-field">
        <span>场景描述</span>
        <textarea rows={4} value={value} onChange={(event) => setValue(event.target.value)} />
      </label>
      <p className="m-hint">正典实体卡的定妆照会作为参考图（最多 3 张）；无正典卡时为草稿质量。</p>
      <div className="m-inline-actions">
        <button className="m-primary" onClick={() => onSubmit(value)}>加入生成队列</button>
        <button onClick={onCancel}>取消</button>
      </div>
    </div>
  );
}
