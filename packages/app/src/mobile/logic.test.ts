import { describe, expect, it } from "vitest";
import { proposeStructure, type ProposedChapter } from "@marginal/core";
import {
  clampFontSize,
  clampRatio,
  detectUiMode,
  loadReadingPosition,
  mergeChapterUp,
  queueProgress,
  readingPositionKey,
  saveReadingPosition,
  scrollRatio,
  scrollTopForRatio,
  splitChapterAt,
} from "./logic";

const memory = () => {
  const backing = new Map<string, string>();
  return {
    setItem: (key: string, value: string) => void backing.set(key, value),
    getItem: (key: string) => backing.get(key) ?? null,
    dump: () => backing,
  };
};

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
  const text = [
    "第一章 起点",
    "正文一。",
    "正文二。",
    "第二章 转折",
    "正文三。",
    "正文四。",
    "第三章 终点",
    "正文五。",
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
    expect(split[0]).toMatchObject({ title: "正文二。", startLine: 0, endLine: 2 });
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

  it("不可滚动时比率为 0", () => {
    expect(scrollRatio(0, 500, 500)).toBe(0);
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
