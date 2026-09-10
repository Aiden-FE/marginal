import { describe, expect, it } from "vitest";
import { proposeStructure, type ProposedChapter } from "@marginal/core";
import {
  clampAutoScrollSpeed,
  clampFontSize,
  clampRatio,
  detectUiMode,
  isWorkFinished,
  loadWorkGroups,
  listChapterBookmarks,
  listFavorites,
  loadReadingPosition,
  mergeChapterUp,
  nextReaderTheme,
  normalizeReaderTheme,
  queueProgress,
  readingPositionKey,
  saveReadingPosition,
  saveWorkGroups,
  setWorkGroup,
  workGroupNames,
  searchChapters,
  scrollRatio,
  scrollTopForRatio,
  splitChapterAt,
  toggleChapterBookmark,
  toggleFavorite,
} from "./logic";
import { wrapPosterText } from "./poster";

const memory = () => {
  const backing = new Map<string, string>();
  return {
    setItem: (key: string, value: string) => void backing.set(key, value),
    getItem: (key: string) => backing.get(key) ?? null,
    dump: () => backing,
  };
};

describe("阅读器扩展设置", () => {
  it("主题按日间、护眼、夜间循环并兼容损坏值", () => {
    expect(normalizeReaderTheme("eyecare")).toBe("eyecare");
    expect(normalizeReaderTheme("unknown")).toBe("paper");
    expect(nextReaderTheme("paper")).toBe("eyecare");
    expect(nextReaderTheme("eyecare")).toBe("dark");
    expect(nextReaderTheme("dark")).toBe("paper");
  });

  it("自动阅读速度钳制到可用范围", () => {
    expect(clampAutoScrollSpeed(1)).toBe(20);
    expect(clampAutoScrollSpeed(80)).toBe(80);
    expect(clampAutoScrollSpeed(999)).toBe(180);
    expect(clampAutoScrollSpeed(Number.NaN)).toBe(60);
  });

  it("只有最后一章接近结尾才判定读完", () => {
    const chapters = [{ id: "c1" }, { id: "c2" }];
    expect(isWorkFinished({ chapterId: "c2", scrollRatio: 0.99 }, chapters)).toBe(true);
    expect(isWorkFinished({ chapterId: "c2", scrollRatio: 0.5 }, chapters)).toBe(false);
    expect(isWorkFinished({ chapterId: "c1", scrollRatio: 1 }, chapters)).toBe(false);
    expect(isWorkFinished(null, chapters)).toBe(false);
  });

  it("书架分组可设置、清除、过滤损坏数据并列出名称", () => {
    const storage = memory();
    let groups = setWorkGroup(storage, "w1", "武侠");
    groups = setWorkGroup(storage, "w2", " 科幻 ");
    expect(loadWorkGroups(storage)).toEqual({ w1: "武侠", w2: "科幻" });
    expect(workGroupNames(groups)).toEqual(["科幻", "武侠"]);
    groups = setWorkGroup(storage, "w1", "");
    expect(groups).toEqual({ w2: "科幻" });
    saveWorkGroups(storage, { w3: "x".repeat(40) });
    expect(loadWorkGroups(storage).w3).toHaveLength(30);
    storage.setItem("marginal.work-groups.v1", "bad json");
    expect(loadWorkGroups(storage)).toEqual({});
  });

  it("海报正文可断行并限制最大行数", () => {
    expect(wrapPosterText("短句")).toEqual(["短句"]);
    const lines = wrapPosterText("这是一段需要制作成分享海报的很长中文正文".repeat(20), 10, 4);
    expect(lines).toHaveLength(4);
    expect(lines[3].endsWith("…")).toBe(true);
    expect(wrapPosterText("一二三四五六七八九十", 5, 2)).toEqual(["一二三四五", "六七八九十"]);
  });
});

describe("detectUiMode", () => {
  it("?ui 参数强制覆盖设备特征", () => {
    expect(detectUiMode("?ui=mobile", { coarsePointer: false, width: 1920 })).toBe("mobile");
    expect(detectUiMode("?ui=desktop&a=1", { coarsePointer: true, width: 390 })).toBe("desktop");
  });

  it("coarse 指针或窄屏判定移动端", () => {
    expect(detectUiMode("", { coarsePointer: true, width: 1280 })).toBe("mobile");
    expect(detectUiMode("", { coarsePointer: false, width: 600 })).toBe("mobile");
    expect(detectUiMode("", { coarsePointer: false, width: 767 })).toBe("mobile");
    expect(detectUiMode("", { coarsePointer: false, width: 768 })).toBe("desktop");
  });
});

describe("章节编辑（切分预览共用逻辑）", () => {
  // 章节正文刻意写得足够长：低于最小体量的章会被合并保护并掉，这里要测的是手动编辑逻辑
  const text = [
    "第一章 起点",
    ...Array.from({ length: 8 }, (_, i) => `起点章第${i + 1}段正文，保持足够的章节体量，避免触发短章合并保护。`),
    "第二章 转折",
    ...Array.from({ length: 8 }, (_, i) => `转折章第${i + 1}段正文，保持足够的章节体量，避免触发短章合并保护。`),
    "第三章 终点",
    ...Array.from({ length: 8 }, (_, i) => `终点章第${i + 1}段正文，保持足够的章节体量，避免触发短章合并保护。`),
  ].join("\n");
  const chapters: ProposedChapter[] = proposeStructure(text);

  it("proposeStructure 产出基准章节", () => {
    expect(chapters.length).toBeGreaterThanOrEqual(3);
    expect(chapters[0].title).toContain("第一章");
  });

  it("并入上一章：移除后章并把行区间并给前章", () => {
    const merged = mergeChapterUp(chapters, 1);
    expect(merged).toHaveLength(chapters.length - 1);
    expect(merged[0].endLine).toBe(chapters[1].endLine);
    // 不修改原数组
    expect(chapters).toHaveLength(3);
  });

  it("第 0 章不能并入上一章", () => {
    expect(mergeChapterUp(chapters, 0)).toBe(chapters);
  });

  it("在行边界拆分：标题取自拆分行", () => {
    const split = splitChapterAt(text, chapters, 0, 2);
    expect(split).toHaveLength(chapters.length + 1);
    expect(split[0]).toMatchObject({ title: text.split("\n")[2], startLine: 0, endLine: 2 });
    expect(split[1]).toMatchObject({ title: "（未命名）", startLine: 2, endLine: chapters[0].endLine });
  });

  it("拆分行越界时返回原列表", () => {
    expect(splitChapterAt(text, chapters, 0, chapters[0].startLine)).toBe(chapters);
    expect(splitChapterAt(text, chapters, 0, chapters[0].endLine)).toBe(chapters);
  });
});

describe("阅读位置记忆", () => {
  it("保存/读取往返，且比率被钳制到 0~1", () => {
    const storage = memory();
    saveReadingPosition(storage, "w1", { chapterId: "c1", scrollRatio: 1.5 });
    expect(loadReadingPosition(storage, "w1")).toEqual({ chapterId: "c1", scrollRatio: 1 });
    saveReadingPosition(storage, "w2", { chapterId: "c2", scrollRatio: -1 });
    expect(loadReadingPosition(storage, "w2")).toEqual({ chapterId: "c2", scrollRatio: 0 });
  });

  it("损坏数据返回 null 而不抛错", () => {
    const storage = memory();
    storage.setItem(readingPositionKey("w1"), "{oops");
    expect(loadReadingPosition(storage, "w1")).toBeNull();
    expect(loadReadingPosition(storage, "missing")).toBeNull();
  });
});

describe("滚动与字号计算", () => {
  it("scrollRatio / scrollTopForRatio 互逆", () => {
    const ratio = scrollRatio(250, 1000, 500);
    expect(ratio).toBeCloseTo(0.5);
    expect(scrollTopForRatio(ratio, 1000, 500)).toBeCloseTo(250);
  });

  it("内容不足一屏时比率记 1，短尾声章可判定读完", () => {
    expect(scrollRatio(0, 500, 500)).toBe(1);
    expect(isWorkFinished({ chapterId: "only", scrollRatio: scrollRatio(0, 500, 500) }, [{ id: "only" }])).toBe(true);
  });

  it("字号钳制 14~30", () => {
    expect(clampFontSize(12)).toBe(14);
    expect(clampFontSize(31)).toBe(30);
    expect(clampFontSize(19)).toBe(19);
  });

  it("clampRatio 处理 NaN/Infinity", () => {
    expect(clampRatio(Number.NaN)).toBe(0);
    expect(clampRatio(Number.POSITIVE_INFINITY)).toBe(1);
  });
});

describe("queueProgress", () => {
  it("统计各状态并给出完成比例", () => {
    const progress = queueProgress([
      { state: "done" },
      { state: "done" },
      { state: "running" },
      { state: "pending" },
      { state: "failed" },
      { state: "cancelled" },
    ]);
    expect(progress).toEqual({ total: 6, active: 2, done: 2, failed: 1, ratio: 0.5 });
  });

  it("空队列比例 0", () => {
    expect(queueProgress([]).ratio).toBe(0);
  });
});

describe("段落收藏", () => {
  const favorite = { chapterId: "c1", chapterTitle: "第一章", paraIndex: 3, text: "精彩段落", savedAt: 1 };

  it("收藏/取消往返，同一章节同段落去重", () => {
    const storage = memory();
    const added = toggleFavorite(storage, "w1", favorite);
    expect(added.added).toBe(true);
    expect(added.favorites).toHaveLength(1);
    const removed = toggleFavorite(storage, "w1", favorite);
    expect(removed.added).toBe(false);
    expect(removed.favorites).toHaveLength(0);
    expect(listFavorites(storage, "w1")).toEqual([]);
  });

  it("不同段落分别收藏，新的排在最前", () => {
    const storage = memory();
    toggleFavorite(storage, "w1", { ...favorite, paraIndex: 1, savedAt: 1 });
    const second = toggleFavorite(storage, "w1", { ...favorite, paraIndex: 5, savedAt: 2 });
    expect(second.favorites.map((item) => item.paraIndex)).toEqual([5, 1]);
  });

  it("损坏数据返回空列表而不抛错", () => {
    const storage = memory();
    storage.setItem("marginal.favorites.w1.v1", "{oops");
    expect(listFavorites(storage, "w1")).toEqual([]);
  });
});

describe("章节书签", () => {
  it("书签/取消往返，同一章节去重", () => {
    const storage = memory();
    const added = toggleChapterBookmark(storage, "w1", "c1", "第一章");
    expect(added.added).toBe(true);
    expect(added.bookmarks).toHaveLength(1);
    expect(added.bookmarks[0]).toMatchObject({ chapterId: "c1", chapterTitle: "第一章" });
    const removed = toggleChapterBookmark(storage, "w1", "c1", "第一章");
    expect(removed.added).toBe(false);
    expect(removed.bookmarks).toHaveLength(0);
  });

  it("多章书签新的排在最前", () => {
    const storage = memory();
    toggleChapterBookmark(storage, "w1", "c1", "一");
    const second = toggleChapterBookmark(storage, "w1", "c2", "二");
    expect(second.bookmarks.map((item) => item.chapterId)).toEqual(["c2", "c1"]);
  });

  it("损坏数据返回空列表而不抛错", () => {
    const storage = memory();
    storage.setItem("marginal.bookmarks.w1.v1", "{oops");
    expect(listChapterBookmarks(storage, "w1")).toEqual([]);
  });
});


describe("全书搜索", () => {
  const repo = {
    listChapters: async () => [
      { id: "c1", idx: 0, title: "第一章" },
      { id: "c2", idx: 1, title: "第二章" },
    ],
    getChapterText: async (id: string) => id === "c1"
      ? "风从北边来。\n\n小满记得那座桥。\n\n后来又说起小满。"
      : "桥下没有人。\n\n灯在雨里亮着。",
  };

  it("跨章扫描并按章节聚合命中", async () => {
    const hits = await searchChapters(repo, "w1", "桥");
    expect(hits).toHaveLength(2);
    expect(hits[0]).toMatchObject({ chapterId: "c1", firstParaIndex: 1, count: 1 });
    expect(hits[1]).toMatchObject({ chapterId: "c2", firstParaIndex: 0, count: 1 });
  });

  it("同一章多处命中只返回一项并累计次数", async () => {
    const hits = await searchChapters(repo, "w1", "小满");
    expect(hits).toHaveLength(1);
    expect(hits[0]).toMatchObject({ chapterTitle: "第一章", count: 2 });
    expect(hits[0].context).toContain("小满");
  });

  it("空关键词或无结果返回空列表", async () => {
    expect(await searchChapters(repo, "w1", "   ")).toEqual([]);
    expect(await searchChapters(repo, "w1", "不存在")).toEqual([]);
  });
});
