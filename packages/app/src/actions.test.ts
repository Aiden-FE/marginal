import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Work } from "@marginal/core";

vi.mock("@marginal/data", () => ({
  engineInfo: { reason: "" },
  openRepository: vi.fn(),
}));

import { confirmImport } from "./actions";
import { store } from "./store";
import { mergeChapterUp, splitChapterAt } from "./mobile/logic";

const createdWork: Work = {
  id: "work-1",
  title: "改后书名",
  author: "",
  importSource: "sample.txt",
  createdAt: 1,
  updatedAt: 1,
  settings: { taskConfigs: {}, autoNormalize: false, budgetLimit: 0 },
};

describe("confirmImport", () => {
  beforeEach(() => {
    store.view = { name: "library" };
    store.toast = "";
  });

  it("使用 SplitPreview 回传的并入结果，而不是初始提案", async () => {
    const text = [
      "第一章 起点",
      "一。",
      "第二章 转折",
      "二。",
      "第三章 终点",
      "三。",
    ].join("\n");
    const initial = [
      { title: "第一章 起点", startLine: 0, endLine: 2, lowConfidence: false },
      { title: "第二章 转折", startLine: 2, endLine: 4, lowConfidence: false },
      { title: "第三章 终点", startLine: 4, endLine: 6, lowConfidence: false },
    ];
    const edited = mergeChapterUp(initial, 1);
    const create = vi.spyOn(store, "createWorkFromText").mockResolvedValue(createdWork);

    await confirmImport("改后书名", "sample.txt", text, edited);

    expect(create).toHaveBeenCalledTimes(1);
    const [, , , chapters] = create.mock.calls[0];
    expect(chapters).toHaveLength(2);
    expect(chapters[0].title).toBe("第一章 起点");
    expect(chapters[0].text).toContain("第二章 转折");
    expect(chapters[1].title).toBe("第三章 终点");
    expect(store.view).toEqual({ name: "work", workId: "work-1", tab: "reader" });
    create.mockRestore();
  });

  it("使用 SplitPreview 回传的拆分结果", async () => {
    const text = ["第一章", "甲。", "拆分标题", "乙。", "丙。"].join("\n");
    const initial = [{ title: "第一章", startLine: 0, endLine: 5, lowConfidence: false }];
    const edited = splitChapterAt(text, initial, 0, 2);
    const create = vi.spyOn(store, "createWorkFromText").mockResolvedValue(createdWork);

    await confirmImport("拆分书", "split.txt", text, edited);

    const [, , , chapters] = create.mock.calls[0];
    expect(chapters).toHaveLength(2);
    expect(chapters[0]).toEqual({ title: "拆分标题", text: "第一章\n甲。\n" });
    expect(chapters[1]).toEqual({ title: "（未命名）", text: "拆分标题\n乙。\n丙。\n" });
    create.mockRestore();
  });
});
