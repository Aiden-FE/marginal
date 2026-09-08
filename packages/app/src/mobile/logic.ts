import type { ProposedChapter, QueueTask } from "@marginal/core";

export type UiMode = "mobile" | "desktop";

export function detectUiMode(
  search: string,
  environment: { coarsePointer: boolean; width: number },
): UiMode {
  const forced = new URLSearchParams(search).get("ui");
  if (forced === "mobile" || forced === "desktop") return forced;
  return environment.coarsePointer || environment.width < 768 ? "mobile" : "desktop";
}

export function currentUiMode(): UiMode {
  return detectUiMode(window.location.search, {
    coarsePointer: window.matchMedia?.("(pointer: coarse)").matches ?? false,
    width: window.innerWidth,
  });
}

export function mergeChapterUp(chapters: ProposedChapter[], index: number): ProposedChapter[] {
  if (index <= 0 || index >= chapters.length) return chapters;
  const next = chapters.map((chapter) => ({ ...chapter }));
  next[index - 1].endLine = next[index].endLine;
  next.splice(index, 1);
  return next;
}

export function splitChapterAt(
  text: string,
  chapters: ProposedChapter[],
  index: number,
  line: number,
): ProposedChapter[] {
  const chapter = chapters[index];
  if (!chapter || line <= chapter.startLine || line >= chapter.endLine) return chapters;
  const lines = text.split(/\r\n|\r|\n/);
  const next = chapters.map((item) => ({ ...item }));
  next.splice(
    index,
    1,
    {
      title: lines[line]?.trim().slice(0, 60) || `部分 ${line}`,
      startLine: chapter.startLine,
      endLine: line,
      lowConfidence: false,
    },
    {
      title: "（未命名）",
      startLine: line,
      endLine: chapter.endLine,
      lowConfidence: false,
    },
  );
  return next;
}

export interface ReadingPosition {
  chapterId: string;
  scrollRatio: number;
}

export function readingPositionKey(workId: string): string {
  return `marginal.reading.${workId}.v1`;
}

export function clampRatio(value: number): number {
  if (Number.isNaN(value)) return 0;
  return Math.max(0, Math.min(1, value));
}

export function saveReadingPosition(
  storage: Pick<Storage, "setItem">,
  workId: string,
  position: ReadingPosition,
): void {
  storage.setItem(
    readingPositionKey(workId),
    JSON.stringify({ ...position, scrollRatio: clampRatio(position.scrollRatio) }),
  );
}

export function loadReadingPosition(
  storage: Pick<Storage, "getItem">,
  workId: string,
): ReadingPosition | null {
  const raw = storage.getItem(readingPositionKey(workId));
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as Partial<ReadingPosition>;
    if (typeof parsed.chapterId !== "string" || typeof parsed.scrollRatio !== "number") return null;
    return { chapterId: parsed.chapterId, scrollRatio: clampRatio(parsed.scrollRatio) };
  } catch {
    return null;
  }
}

export function scrollRatio(scrollTop: number, scrollHeight: number, clientHeight: number): number {
  return clampRatio(scrollTop / Math.max(1, scrollHeight - clientHeight));
}

export function scrollTopForRatio(ratio: number, scrollHeight: number, clientHeight: number): number {
  return clampRatio(ratio) * Math.max(0, scrollHeight - clientHeight);
}

export function clampFontSize(value: number): number {
  return Math.max(14, Math.min(30, value));
}

export interface QueueProgress {
  total: number;
  active: number;
  done: number;
  failed: number;
  ratio: number;
}

export function queueProgress(tasks: Pick<QueueTask, "state">[]): QueueProgress {
  const total = tasks.length;
  const active = tasks.filter((task) => task.state === "pending" || task.state === "running").length;
  const done = tasks.filter((task) => task.state === "done").length;
  const failed = tasks.filter((task) => task.state === "failed").length;
  // 已取消的任务既不算完成也不算失败，进度按 done+failed 结算（到达 1 表示队列全部收尾）
  const settled = done + failed;
  return { total, active, done, failed, ratio: total ? settled / total : 0 };
}
