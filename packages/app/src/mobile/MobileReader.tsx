import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { splitParagraphs, type Anchor, type Work } from "@marginal/core";
import { generateIllustration } from "../actions";
import { store, useStore } from "../store";
import { IllustrationImage } from "../components/IllustrationImage";
import { ActionSheet, BottomSheet, MiniQueueProgress } from "./shared";
import {
  clampAutoScrollSpeed, clampFontSize, listChapterBookmarks, listFavorites, loadReadingPosition,
  nextReaderTheme, normalizeReaderTheme, saveChapterBookmarks, saveFavorites, saveReadingPosition,
  scrollRatio, scrollTopForRatio, searchChapters, toggleChapterBookmark, toggleFavorite,
  type BookSearchHit, type ChapterBookmark, type ParagraphFavorite, type ReaderTheme,
} from "./logic";
import { renderParagraphPoster, type ParagraphPosterInput } from "./poster";
import type { MobileWorkTab } from "./types";

const FONT_KEY = "marginal.reader.fontSize.v1";
const THEME_KEY = "marginal.reader.theme.v1";
const IMMERSIVE_KEY = "marginal.reader.immersive.v1";
const AUTO_SPEED_KEY = "marginal.reader.autoSpeed.v1";
const THEME_COLOR: Record<ReaderTheme, string> = { paper: "#f4eddc", eyecare: "#cfe3d2", dark: "#171816" };

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
  const [immersive, setImmersive] = useState(() => localStorage.getItem(IMMERSIVE_KEY) !== "off");
  const [chrome, setChrome] = useState(() => localStorage.getItem(IMMERSIVE_KEY) !== "off" ? false : true);
  const [showChapters, setShowChapters] = useState(false);
  const [scene, setScene] = useState<{ paraIndex: number; text: string } | null>(null);
  const [fontSize, setFontSize] = useState(() => clampFontSize(Number(localStorage.getItem(FONT_KEY)) || 19));
  const [theme, setTheme] = useState<ReaderTheme>(() => normalizeReaderTheme(localStorage.getItem(THEME_KEY)));
  const [autoScroll, setAutoScroll] = useState(false);
  const [autoSpeed, setAutoSpeed] = useState(() => clampAutoScrollSpeed(Number(localStorage.getItem(AUTO_SPEED_KEY)) || 60));
  const [showAutoSettings, setShowAutoSettings] = useState(false);
  const [poster, setPoster] = useState<ParagraphPosterInput | null>(null);
  const [progress, setProgress] = useState(0);
  const [menu, setMenu] = useState(false);
  const [paraMenu, setParaMenu] = useState<{ paraIndex: number; text: string } | null>(null);
  const [favorites, setFavorites] = useState<ParagraphFavorite[]>([]);
  const [showFavorites, setShowFavorites] = useState(false);
  const [bookmarks, setBookmarks] = useState<ChapterBookmark[]>([]);
  const [showBookmarks, setShowBookmarks] = useState(false);
  const [showSearch, setShowSearch] = useState(false);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<BookSearchHit[]>([]);
  const [searching, setSearching] = useState(false);
  const [loadingChapterId, setLoadingChapterId] = useState("");
  const viewportRef = useRef<HTMLDivElement>(null);
  const chapterIdRef = useRef("");
  const restoredRef = useRef(false);
  const ratioRef = useRef(0);
  const saveTimer = useRef<number | null>(null);
  const hideTimer = useRef<number | null>(null);
  const chromeLockUntilRef = useRef(0);
  const autoSpeedRef = useRef(autoSpeed);
  const autoAdvancingRef = useRef(false);
  const autoBottomSinceRef = useRef(0);
  const posterCanvasRef = useRef<HTMLCanvasElement>(null);
  const loadSeqRef = useRef(0);
  const searchSeqRef = useRef(0);

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
  const bookmarkIds = useMemo(() => new Set(bookmarks.map((item) => item.chapterId)), [bookmarks]);

  const scrollTo = useCallback((ratio: number) => {
    const viewport = viewportRef.current;
    if (!viewport) return;
    viewport.scrollTop = scrollTopForRatio(ratio, viewport.scrollHeight, viewport.clientHeight);
  }, []);

  // 沉浸模式：工具栏短暂显示后自动收起；交互会续期；用户手动唤出后短暂锁定，避免滚动立刻收起
  const armAutoHide = useCallback(() => {
    if (hideTimer.current) window.clearTimeout(hideTimer.current);
    hideTimer.current = window.setTimeout(() => {
      hideTimer.current = null;
      setImmersive((currentImmersive) => {
        if (currentImmersive) setChrome(false);
        return currentImmersive;
      });
    }, 8000);
  }, []);

  const userShowsChrome = useCallback(() => {
    chromeLockUntilRef.current = performance.now() + 8000;
    armAutoHide();
  }, [armAutoHide]);

  useEffect(() => {
    if (chrome && immersive) armAutoHide();
    else if (hideTimer.current) {
      window.clearTimeout(hideTimer.current);
      hideTimer.current = null;
    }
    return () => {
      if (hideTimer.current) window.clearTimeout(hideTimer.current);
    };
  }, [chrome, immersive, armAutoHide]);

  // 阅读背景与浏览器状态栏/地址栏颜色融合（viewport-fit=cover）
  useEffect(() => {
    const meta = document.querySelector('meta[name="theme-color"]');
    if (!meta) return;
    const previous = meta.getAttribute("content");
    meta.setAttribute("content", THEME_COLOR[theme]);
    return () => {
      if (previous) meta.setAttribute("content", previous);
    };
  }, [theme]);

  useEffect(() => {
    autoSpeedRef.current = autoSpeed;
    localStorage.setItem(AUTO_SPEED_KEY, String(autoSpeed));
  }, [autoSpeed]);

  useEffect(() => {
    if (!poster) return;
    try {
      if (posterCanvasRef.current) renderParagraphPoster(posterCanvasRef.current, poster);
    } catch {
      setPoster(null);
      store.notify("当前浏览器不支持海报生成");
    }
  }, [poster]);

  const flushPosition = useCallback(() => {
    if (saveTimer.current) {
      window.clearTimeout(saveTimer.current);
      saveTimer.current = null;
    }
    if (chapterIdRef.current) {
      saveReadingPosition(localStorage, work.id, { chapterId: chapterIdRef.current, scrollRatio: ratioRef.current });
    }
  }, [work.id]);

  // 统一的安全切章：先快照保存旧章，正文+锚点读全后一次性提交，过期请求直接丢弃
  const switchChapter = useCallback(async (id: string, ratio: number) => {
    const seq = ++loadSeqRef.current;
    const previousId = chapterIdRef.current;
    const previousRatio = ratioRef.current;
    if (saveTimer.current) {
      window.clearTimeout(saveTimer.current);
      saveTimer.current = null;
    }
    if (previousId) saveReadingPosition(localStorage, work.id, { chapterId: previousId, scrollRatio: previousRatio });
    setLoadingChapterId(id);
    const [nextText, allAnchors] = await Promise.all([
      store.repo.getChapterText(id),
      store.repo.listAnchors(work.id),
    ]);
    if (seq !== loadSeqRef.current) return false;
    chapterIdRef.current = id;
    setChapterId(id);
    setText(nextText);
    setAnchors(allAnchors.filter((anchor) => anchor.chapterId === id && anchor.state === "active"));
    setProgress(ratio);
    ratioRef.current = ratio;
    setLoadingChapterId("");
    requestAnimationFrame(() => requestAnimationFrame(() => scrollTo(ratio)));
    return true;
  }, [work.id, scrollTo]);

  // 自动阅读：等速滚动；章末停留后自动切下一章；任何弹层打开时暂停
  useEffect(() => {
    if (!autoScroll) return;
    const overlayOpen = showChapters || menu || paraMenu || showSearch || showFavorites || showBookmarks || scene || showAutoSettings || poster;
    if (overlayOpen) return;
    const viewport = viewportRef.current;
    const pauseForManualScroll = () => {
      setAutoScroll(false);
      autoBottomSinceRef.current = 0;
      store.notify("已暂停自动阅读");
    };
    viewport?.addEventListener("touchstart", pauseForManualScroll, { passive: true });
    viewport?.addEventListener("wheel", pauseForManualScroll, { passive: true });
    let raf = 0;
    let last = performance.now();
    const tick = (now: number) => {
      const viewport = viewportRef.current;
      if (!viewport) {
        raf = requestAnimationFrame(tick);
        return;
      }
      const dt = Math.min(0.12, (now - last) / 1000);
      last = now;
      const atBottom = viewport.scrollTop + viewport.clientHeight >= viewport.scrollHeight - 1;
      if (atBottom) {
        if (autoBottomSinceRef.current === 0) autoBottomSinceRef.current = now;
        const dwelled = now - autoBottomSinceRef.current >= 1500;
        const index = chapters.findIndex((chapter) => chapter.id === chapterIdRef.current);
        const next = chapters[index + 1];
        if (dwelled && !autoAdvancingRef.current) {
          if (next) {
            autoAdvancingRef.current = true;
            void switchChapter(next.id, 0).finally(() => {
              autoAdvancingRef.current = false;
              autoBottomSinceRef.current = 0;
            });
          } else {
            setAutoScroll(false);
            autoBottomSinceRef.current = 0;
            store.notify("已自动读完最后一章");
            return;
          }
        }
      } else {
        autoBottomSinceRef.current = 0;
        viewport.scrollTop += autoSpeedRef.current * dt;
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => {
      cancelAnimationFrame(raf);
      viewport?.removeEventListener("touchstart", pauseForManualScroll);
      viewport?.removeEventListener("wheel", pauseForManualScroll);
    };
  }, [autoScroll, showChapters, menu, paraMenu, showSearch, showFavorites, showBookmarks, scene, showAutoSettings, poster, chapters, switchChapter]);

  // 首次进入：恢复上次阅读位置；章节结构重切后位置失效则回退并提示
  useEffect(() => {
    void (async () => {
      const all = await store.repo.listChapters(work.id);
      setChapters(all.map((chapter) => ({ id: chapter.id, idx: chapter.idx, title: chapter.title })));
      setFavorites(listFavorites(localStorage, work.id));
      setBookmarks(listChapterBookmarks(localStorage, work.id));
      const saved = loadReadingPosition(localStorage, work.id);
      if (saved && !all.some((chapter) => chapter.id === saved.chapterId)) {
        store.notify("原阅读位置因章节结构变更已失效，已回到第一章");
      }
      const target = all.find((chapter) => chapter.id === saved?.chapterId) ?? all[0];
      if (target) {
        await switchChapter(target.id, saved && target.id === saved.chapterId ? saved.scrollRatio : 0);
      }
      restoredRef.current = true;
    })();
    return () => {
      loadSeqRef.current++;
      flushPosition();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [work.id]);

  // 章节重切后清理失效的书签/收藏（旧章节 ID 已不存在）
  useEffect(() => {
    if (chapters.length === 0) return;
    const validIds = new Set(chapters.map((chapter) => chapter.id));
    const rawBookmarks = listChapterBookmarks(localStorage, work.id);
    const rawFavorites = listFavorites(localStorage, work.id);
    const cleanBookmarks = rawBookmarks.filter((item) => validIds.has(item.chapterId));
    const cleanFavorites = rawFavorites.filter((item) => validIds.has(item.chapterId));
    if (cleanBookmarks.length !== rawBookmarks.length) {
      saveChapterBookmarks(localStorage, work.id, cleanBookmarks);
      setBookmarks(cleanBookmarks);
    }
    if (cleanFavorites.length !== rawFavorites.length) {
      saveFavorites(localStorage, work.id, cleanFavorites);
      setFavorites(cleanFavorites);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chapters, work.id]);

  // 移动端后台/关页时同步落盘，React 卸载不保证发生
  useEffect(() => {
    const onHidden = () => {
      if (document.visibilityState === "hidden") flushPosition();
    };
    window.addEventListener("pagehide", flushPosition);
    document.addEventListener("visibilitychange", onHidden);
    return () => {
      window.removeEventListener("pagehide", flushPosition);
      document.removeEventListener("visibilitychange", onHidden);
    };
  }, [flushPosition]);

  // 队列有新插图落地时刷新锚点（不重置滚动位置）
  useEffect(() => {
    if (!restoredRef.current || !chapterIdRef.current) return;
    void (async () => {
      setChapters((await store.repo.listChapters(work.id)).map((chapter) => ({ id: chapter.id, idx: chapter.idx, title: chapter.title })));
      setAnchors((await store.repo.listAnchors(work.id)).filter((anchor) => anchor.chapterId === chapterIdRef.current && anchor.state === "active"));
    })();
  }, [version, work.id]);

  // 搜索防抖 + 旧结果不覆盖新结果
  useEffect(() => {
    if (!showSearch) return;
    const seq = ++searchSeqRef.current;
    const token = window.setTimeout(() => {
      void (async () => {
        const keyword = query.trim();
        if (!keyword) {
          setResults([]);
          setSearching(false);
          return;
        }
        setSearching(true);
        const hits = await searchChapters(store.repo, work.id, keyword);
        if (seq !== searchSeqRef.current) return;
        setResults(hits);
        setSearching(false);
      })();
    }, 300);
    return () => window.clearTimeout(token);
  }, [query, showSearch, work.id]);

  // 目录打开后把当前章滚到可视区中央
  useEffect(() => {
    if (!showChapters) return;
    requestAnimationFrame(() => {
      document.querySelector(".m-chapter-row > button.active")?.scrollIntoView({ block: "center" });
    });
  }, [showChapters]);

  function onScroll() {
    const viewport = viewportRef.current;
    if (!viewport) return;
    const ratio = scrollRatio(viewport.scrollTop, viewport.scrollHeight, viewport.clientHeight);
    ratioRef.current = ratio;
    setProgress(ratio);
    if (immersive && performance.now() >= chromeLockUntilRef.current) setChrome(false);
    if (saveTimer.current) window.clearTimeout(saveTimer.current);
    const snapshot = { chapterId: chapterIdRef.current, scrollRatio: ratio };
    saveTimer.current = window.setTimeout(() => {
      if (snapshot.chapterId) saveReadingPosition(localStorage, work.id, snapshot);
    }, 400);
  }

  function pickChapter(id: string) {
    setShowChapters(false);
    if (id === chapterId) return;
    void switchChapter(id, 0);
  }

  function stepChapter(delta: number) {
    const index = chapters.findIndex((chapter) => chapter.id === chapterId);
    const next = chapters[index + delta];
    if (next && !loadingChapterId) void switchChapter(next.id, 0);
  }

  function changeFont(delta: number) {
    armAutoHide();
    setFontSize((current) => {
      const next = clampFontSize(current + delta);
      localStorage.setItem(FONT_KEY, String(next));
      return next;
    });
  }

  function toggleTheme() {
    armAutoHide();
    setTheme((current) => {
      const next = nextReaderTheme(current);
      localStorage.setItem(THEME_KEY, next);
      return next;
    });
  }

  function adjustAutoSpeed(delta: number) {
    setAutoSpeed((current) => clampAutoScrollSpeed(current + delta));
  }

  async function sharePosterImage() {
    const canvas = posterCanvasRef.current;
    if (!canvas) return;
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/png"));
    if (blob && typeof navigator.canShare === "function") {
      const file = new File([blob], "paragraph-poster.png", { type: "image/png" });
      if (navigator.canShare({ files: [file] })) {
        try {
          await navigator.share({ files: [file], title: work.title });
          return;
        } catch (error) {
          if (error instanceof DOMException && error.name === "AbortError") return;
        }
      }
    }
    const link = document.createElement("a");
    link.href = canvas.toDataURL("image/png");
    link.download = `《${work.title.slice(0, 20)}》段落海报.png`;
    link.click();
    store.notify("海报已生成；若未自动保存，可长按预览图保存到相册");
  }

  function openPoster(text: string) {
    const chapter = chapters.find((item) => item.id === chapterIdRef.current);
    setPoster({ title: work.title, chapterTitle: chapter?.title ?? "", text });
  }

  function toggleImmersive() {
    setImmersive((current) => {
      const next = !current;
      localStorage.setItem(IMMERSIVE_KEY, next ? "on" : "off");
      setChrome(next ? false : true);
      return next;
    });
  }

  async function enqueueIllustration(paraIndex: number, sceneText: string) {
    setScene(null);
    await generateIllustration(work, chapterIdRef.current, paraIndex, sceneText);
  }

  function toggleChapterMark(chapter: { id: string; title: string }) {
    const { bookmarks: next, added } = toggleChapterBookmark(localStorage, work.id, chapter.id, chapter.title);
    setBookmarks(next);
    store.notify(added ? `已书签「${chapter.title}」` : "已取消书签");
  }

  function removeChapterMark(chapterIdToRemove: string, chapterTitle: string) {
    const { bookmarks: next } = toggleChapterBookmark(localStorage, work.id, chapterIdToRemove, chapterTitle);
    setBookmarks(next);
    store.notify("已取消书签");
  }

  function jumpToBookmarkChapter(bookmarkChapterId: string) {
    setShowBookmarks(false);
    if (bookmarkChapterId !== chapterIdRef.current) void switchChapter(bookmarkChapterId, 0);
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

  function scrollParaIntoView(paraIndex: number) {
    requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(() => {
      document.getElementById(`m-para-${paraIndex}`)?.scrollIntoView({ block: "center" });
    })));
  }

  function jumpToFavorite(favorite: ParagraphFavorite) {
    setShowFavorites(false);
    if (favorite.chapterId !== chapterIdRef.current) {
      void switchChapter(favorite.chapterId, 0).then((applied) => {
        if (applied) scrollParaIntoView(favorite.paraIndex);
      });
    } else {
      scrollParaIntoView(favorite.paraIndex);
    }
  }

  function openSearchHit(hit: BookSearchHit) {
    setShowSearch(false);
    setQuery("");
    setResults([]);
    if (hit.chapterId !== chapterIdRef.current) {
      void switchChapter(hit.chapterId, 0).then((applied) => {
        if (applied) scrollParaIntoView(hit.firstParaIndex);
      });
    } else {
      scrollParaIntoView(hit.firstParaIndex);
    }
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
  const currentBookmarked = chapterId !== "" && bookmarkIds.has(chapterId);

  return (
    <section className={`m-reader theme-${theme}`} aria-label="阅读器">
      <div
        ref={viewportRef}
        className="m-reader-scroll"
        onScroll={onScroll}
        style={{ fontSize }}
      >
        <h2 className="m-reader-title">{chapterTitle}</h2>
        {loadingChapterId && <div className="m-reader-loading">加载中…</div>}
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
        onClick={() => setChrome((value) => {
          if (!value) userShowsChrome();
          return !value;
        })}
      />

      <header className={`m-reader-top${chrome ? "" : " is-hidden"}`} aria-hidden={!chrome}>
        <button className="m-icon-btn" aria-label="返回书架" onClick={onBack}>‹</button>
        <div className="m-reader-heading"><strong>{work.title}</strong><span>{chapterTitle}</span></div>
        <button
          className={`m-icon-btn m-reader-star${currentBookmarked ? " on" : ""}`}
          aria-label={currentBookmarked ? `取消书签：${chapterTitle}` : `书签本章：${chapterTitle}`}
          aria-pressed={currentBookmarked}
          onClick={() => toggleChapterMark({ id: chapterId, title: chapterTitle })}
        >★</button>
        <button className="m-icon-btn" aria-label="章节目录" onClick={() => { armAutoHide(); setShowChapters(true); }}>☰</button>
        <button className="m-icon-btn" aria-label="更多操作" onClick={() => { armAutoHide(); setMenu(true); }}>⋯</button>
      </header>
      <footer className={`m-reader-bottom${chrome ? "" : " is-hidden"}`} aria-hidden={!chrome}>
        <div className="m-reader-progress-row">
          <span>本章 {Math.round(progress * 100)}%</span>
          <div className="m-progress-track"><div style={{ width: `${Math.round(progress * 100)}%` }} /></div>
          <span>{chapters.findIndex((chapter) => chapter.id === chapterId) + 1}/{chapters.length}</span>
        </div>
        <div className="m-reader-actions">
          <button onClick={() => stepChapter(-1)} disabled={loadingChapterId !== "" || chapters.findIndex((chapter) => chapter.id === chapterId) <= 0}>上一章</button>
          <button aria-label="减小字号" onClick={() => changeFont(-2)}>A−</button>
          <button aria-label="增大字号" onClick={() => changeFont(2)}>A＋</button>
          <button onClick={toggleTheme} aria-label={`切换到${nextReaderTheme(theme) === "dark" ? "夜间" : nextReaderTheme(theme) === "eyecare" ? "护眼" : "日间"}模式`}>
            {theme === "paper" ? "🌿 护眼" : theme === "eyecare" ? "🌙 夜间" : "☀️ 日间"}
          </button>
          <button onClick={() => stepChapter(1)} disabled={loadingChapterId !== "" || chapters.findIndex((chapter) => chapter.id === chapterId) === chapters.length - 1}>下一章</button>
        </div>
        <MiniQueueProgress />
      </footer>

      {showChapters && (
        <BottomSheet title="章节目录" onClose={() => setShowChapters(false)}>
          <div className="m-chapter-list">
            {chapters.map((chapter) => (
              <div key={chapter.id} className="m-chapter-row">
                <button
                  className={chapter.id === chapterId ? "active" : ""}
                  onClick={() => pickChapter(chapter.id)}
                >
                  <span>{chapter.idx + 1}</span>{chapter.title}
                </button>
                <button
                  className={`m-toc-bookmark${bookmarkIds.has(chapter.id) ? " on" : ""}`}
                  aria-label={bookmarkIds.has(chapter.id) ? `取消书签：${chapter.title}` : `添加书签：${chapter.title}`}
                  aria-pressed={bookmarkIds.has(chapter.id)}
                  onClick={() => toggleChapterMark(chapter)}
                >★</button>
              </div>
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
            { icon: "📤", label: "制作分享海报", onClick: () => openPoster(paraMenu.text) },
            { icon: "📋", label: "复制段落文本", onClick: () => void shareParagraph(paraMenu.text) },
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

      {showSearch && (
        <BottomSheet title="全书搜索" onClose={() => setShowSearch(false)}>
          <input
            aria-label="搜索关键词"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="输入关键词定位章节"
            autoFocus
          />
          {searching && <p className="m-hint">搜索中…</p>}
          {!searching && query.trim() && results.length === 0 && <p className="m-hint">未找到匹配内容。</p>}
          <div className="m-search-list">
            {results.map((hit) => (
              <button key={hit.chapterId} className="m-search-hit" onClick={() => openSearchHit(hit)}>
                <span className="m-search-chapter">{hit.idx + 1}. {hit.chapterTitle}</span>
                <span className="m-search-context">…{hit.context}…</span>
                <span className="m-search-count">{hit.count} 处</span>
              </button>
            ))}
          </div>
        </BottomSheet>
      )}

      {showBookmarks && (
        <BottomSheet title={`书签（${bookmarks.length}）`} onClose={() => setShowBookmarks(false)}>
          {bookmarks.length === 0 && <p className="m-hint">还没有书签。在章节目录里点 ★ 收藏章节，随时跳回。</p>}
          <div className="m-fav-list">
            {bookmarks.map((bookmark) => (
              <div key={bookmark.chapterId} className="m-fav-item">
                <button className="m-fav-title" onClick={() => jumpToBookmarkChapter(bookmark.chapterId)}>{bookmark.chapterTitle}</button>
                <div className="m-fav-meta">
                  <span>{new Date(bookmark.addedAt).toLocaleDateString()}</span>
                  <div>
                    <button onClick={() => jumpToBookmarkChapter(bookmark.chapterId)}>去阅读</button>
                    <button onClick={() => removeChapterMark(bookmark.chapterId, bookmark.chapterTitle)}>取消书签</button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </BottomSheet>
      )}

      {showFavorites && (
        <BottomSheet title={`精彩段落（${favorites.length}）`} onClose={() => setShowFavorites(false)}>
          {favorites.length === 0 && <p className="m-hint">还没有收藏。点按正文段落即可收藏或分享。</p>}
          <div className="m-fav-list">
            {favorites.map((favorite) => (
              <div key={`${favorite.chapterId}:${favorite.paraIndex}`} className="m-fav-item">
                <p className="m-fav-text">{favorite.text}</p>
                <div className="m-fav-meta">
                  <span>{favorite.chapterTitle || "章节"}</span>
                  <div>
                    <button onClick={() => jumpToFavorite(favorite)}>去阅读</button>
                    <button onClick={() => { setShowFavorites(false); openPoster(favorite.text); }}>海报</button>
                    <button onClick={() => removeFavorite(favorite)}>删除</button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </BottomSheet>
      )}

      {poster && (
        <BottomSheet title="分享海报" onClose={() => setPoster(null)}>
          <canvas ref={posterCanvasRef} className="m-poster-canvas" aria-label="段落分享海报预览" />
          <p className="m-hint">可直接分享图片；不支持文件分享的浏览器会下载 PNG，手机端也可长按预览图保存。</p>
          <div className="m-inline-actions">
            <button className="m-primary" onClick={() => void sharePosterImage()}>分享或保存图片</button>
            <button onClick={() => void copyText(`《${poster.title}》\n${poster.text}`).then((ok) => store.notify(ok ? "段落文本已复制" : "复制失败"))}>复制文字</button>
          </div>
        </BottomSheet>
      )}

      {showAutoSettings && (
        <BottomSheet title="自动阅读设置" onClose={() => setShowAutoSettings(false)}>
          <p className="m-hint">按固定速度连续滚动，章末停留后自动进入下一章。打开目录、搜索或海报时会暂停。</p>
          <div className="m-speed-row">
            <button aria-label="降低自动阅读速度" onClick={() => adjustAutoSpeed(-10)}>−</button>
            <div><strong className="m-speed-value">{autoSpeed}</strong><span> 像素/秒</span></div>
            <button aria-label="提高自动阅读速度" onClick={() => adjustAutoSpeed(10)}>＋</button>
          </div>
          <button className="m-primary m-wide" onClick={() => { setAutoScroll((value) => !value); setShowAutoSettings(false); }}>
            {autoScroll ? "停止自动阅读" : "开始自动阅读"}
          </button>
        </BottomSheet>
      )}

      {menu && (
        <BottomSheet title={work.title} onClose={() => setMenu(false)}>
          <div className="m-stack-actions">
            <button aria-pressed={immersive} onClick={() => { toggleImmersive(); setMenu(false); }}>{immersive ? "☀️ 退出沉浸阅读" : "🌙 开启沉浸阅读"}</button>
            <button aria-pressed={autoScroll} onClick={() => { setAutoScroll((value) => !value); setMenu(false); }}>{autoScroll ? "⏸ 停止自动阅读" : "▶️ 开始自动阅读"}</button>
            <button onClick={() => { setMenu(false); setShowAutoSettings(true); }}>⏱ 自动阅读速度 · {autoSpeed}px/秒</button>
            <button onClick={() => { setMenu(false); setShowSearch(true); }}>🔍 全书搜索</button>
            <button onClick={() => { setMenu(false); onOpenWorkTab("repair"); }}>🔧 修复与修订</button>
            <button onClick={() => { setMenu(false); onOpenWorkTab("entities"); }}>👤 实体卡</button>
            <button onClick={() => { setMenu(false); onOpenWorkTab("illustrations"); }}>🖼 插图任务</button>
            <button onClick={() => { setMenu(false); setShowBookmarks(true); }}>🔖 书签（{bookmarks.length}）</button>
            <button onClick={() => { setMenu(false); setShowFavorites(true); }}>⭐ 精彩段落（{favorites.length}）</button>
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
