import { splitParagraphs, type ProposedChapter, type QueueTask } from "@marginal/core";

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
  const max = scrollHeight - clientHeight;
  // 内容不足一屏时视为整章已读（短尾声章也能拿到"读完"判定）
  if (max <= 0) return 1;
  return clampRatio(scrollTop / max);
}

export function scrollTopForRatio(ratio: number, scrollHeight: number, clientHeight: number): number {
  return clampRatio(ratio) * Math.max(0, scrollHeight - clientHeight);
}

export function clampFontSize(value: number): number {
  return Math.max(14, Math.min(30, value));
}

export type ReaderTheme = "paper" | "eyecare" | "dark";

export function normalizeReaderTheme(value: string | null): ReaderTheme {
  return value === "eyecare" || value === "dark" ? value : "paper";
}

export function nextReaderTheme(theme: ReaderTheme): ReaderTheme {
  return theme === "paper" ? "eyecare" : theme === "eyecare" ? "dark" : "paper";
}

export function clampAutoScrollSpeed(value: number): number {
  if (!Number.isFinite(value)) return 60;
  return Math.max(20, Math.min(180, Math.round(value)));
}

export interface WorkGroupMap { [workId: string]: string }

export const WORK_GROUPS_KEY = "marginal.work-groups.v1";

export function loadWorkGroups(storage: Pick<Storage, "getItem">): WorkGroupMap {
  try {
    const raw = storage.getItem(WORK_GROUPS_KEY);
    if (!raw) return {};
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
    return Object.fromEntries(Object.entries(parsed).filter((entry): entry is [string, string] => (
      typeof entry[0] === "string" && typeof entry[1] === "string" && entry[1].trim().length > 0
    )).map(([id, group]) => [id, group.trim().slice(0, 30)]));
  } catch {
    return {};
  }
}

export function saveWorkGroups(storage: Pick<Storage, "setItem">, groups: WorkGroupMap): void {
  storage.setItem(WORK_GROUPS_KEY, JSON.stringify(groups));
}

export function setWorkGroup(
  storage: Pick<Storage, "getItem" | "setItem">,
  workId: string,
  group: string,
): WorkGroupMap {
  const groups = loadWorkGroups(storage);
  const normalized = group.trim().slice(0, 30);
  if (normalized) groups[workId] = normalized;
  else delete groups[workId];
  saveWorkGroups(storage, groups);
  return groups;
}

export function workGroupNames(groups: WorkGroupMap): string[] {
  return [...new Set(Object.values(groups).filter(Boolean))].sort((a, b) => a.localeCompare(b, "zh-CN"));
}

export function isWorkFinished(
  position: ReadingPosition | null,
  chapters: { id: string }[],
  threshold = 0.98,
): boolean {
  if (!position || chapters.length === 0) return false;
  return chapters[chapters.length - 1].id === position.chapterId && position.scrollRatio >= threshold;
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

export interface ParagraphFavorite {
  chapterId: string;
  chapterTitle: string;
  paraIndex: number;
  text: string;
  savedAt: number;
}

type FavoriteStorage = Pick<Storage, "getItem" | "setItem">;

export function favoritesKey(workId: string): string {
  return `marginal.favorites.${workId}.v1`;
}

export function listFavorites(storage: Pick<Storage, "getItem">, workId: string): ParagraphFavorite[] {
  const raw = storage.getItem(favoritesKey(workId));
  if (!raw) return [];
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(
      (item): item is ParagraphFavorite =>
        typeof item === "object" && item !== null &&
        typeof (item as ParagraphFavorite).chapterId === "string" &&
        typeof (item as ParagraphFavorite).paraIndex === "number" &&
        typeof (item as ParagraphFavorite).text === "string",
    );
  } catch {
    return [];
  }
}

export function saveFavorites(storage: Pick<Storage, "setItem">, workId: string, favorites: ParagraphFavorite[]): void {
  storage.setItem(favoritesKey(workId), JSON.stringify(favorites));
}

export function toggleFavorite(
  storage: FavoriteStorage,
  workId: string,
  favorite: ParagraphFavorite,
): { favorites: ParagraphFavorite[]; added: boolean } {
  const favorites = listFavorites(storage, workId);
  const index = favorites.findIndex(
    (item) => item.chapterId === favorite.chapterId && item.paraIndex === favorite.paraIndex,
  );
  if (index >= 0) {
    favorites.splice(index, 1);
    saveFavorites(storage, workId, favorites);
    return { favorites, added: false };
  }
  const next = [favorite, ...favorites];
  saveFavorites(storage, workId, next);
  return { favorites: next, added: true };
}

export interface ChapterBookmark {
  chapterId: string;
  chapterTitle: string;
  addedAt: number;
}

export function chapterBookmarksKey(workId: string): string {
  return `marginal.bookmarks.${workId}.v1`;
}

export function listChapterBookmarks(storage: Pick<Storage, "getItem">, workId: string): ChapterBookmark[] {
  const raw = storage.getItem(chapterBookmarksKey(workId));
  if (!raw) return [];
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(
      (item): item is ChapterBookmark =>
        typeof item === "object" && item !== null &&
        typeof (item as ChapterBookmark).chapterId === "string" &&
        typeof (item as ChapterBookmark).chapterTitle === "string",
    );
  } catch {
    return [];
  }
}

export function saveChapterBookmarks(storage: Pick<Storage, "setItem">, workId: string, bookmarks: ChapterBookmark[]): void {
  storage.setItem(chapterBookmarksKey(workId), JSON.stringify(bookmarks));
}

export function toggleChapterBookmark(
  storage: Pick<Storage, "getItem" | "setItem">,
  workId: string,
  chapterId: string,
  chapterTitle: string,
): { bookmarks: ChapterBookmark[]; added: boolean } {
  const bookmarks = listChapterBookmarks(storage, workId);
  const index = bookmarks.findIndex((item) => item.chapterId === chapterId);
  if (index >= 0) {
    bookmarks.splice(index, 1);
    saveChapterBookmarks(storage, workId, bookmarks);
    return { bookmarks, added: false };
  }
  const next = [{ chapterId, chapterTitle, addedAt: Date.now() }, ...bookmarks];
  saveChapterBookmarks(storage, workId, next);
  return { bookmarks: next, added: true };
}


export interface BookSearchHit {
  chapterId: string;
  chapterTitle: string;
  idx: number;
  firstParaIndex: number;
  context: string;
  count: number;
}

interface BookSearchRepository {
  listChapters(workId: string): Promise<{ id: string; idx: number; title: string }[]>;
  getChapterText(chapterId: string): Promise<string>;
}

export async function searchChapters(
  repo: BookSearchRepository,
  workId: string,
  rawQuery: string,
): Promise<BookSearchHit[]> {
  const query = rawQuery.trim().toLocaleLowerCase();
  if (!query) return [];
  const chapters = await repo.listChapters(workId);
  const hits: BookSearchHit[] = [];
  for (const chapter of chapters) {
    const paragraphs = splitParagraphs(await repo.getChapterText(chapter.id));
    const matches: number[] = [];
    for (let index = 0; index < paragraphs.length; index++) {
      if (paragraphs[index].toLocaleLowerCase().includes(query)) matches.push(index);
    }
    if (matches.length === 0) continue;
    const firstParaIndex = matches[0];
    hits.push({
      chapterId: chapter.id,
      chapterTitle: chapter.title,
      idx: chapter.idx,
      firstParaIndex,
      context: paragraphs[firstParaIndex].slice(0, 100),
      count: matches.length,
    });
  }
  return hits;
}
