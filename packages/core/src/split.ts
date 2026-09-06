// 章节切分启发式（spec §4.2）：正则标题模式 + 统计兜底，每个切点带置信度。
// 纯函数、零平台依赖。

export interface SplitPoint {
  /** 原文中的行号（0 起） */
  line: number;
  title: string;
  confidence: number; // 0~1
  source: "pattern" | "stats";
}

export interface SplitResult {
  points: SplitPoint[];
}

const TITLE_PATTERNS: { re: RegExp; base: number }[] = [
  { re: /^\s*(第\s*[0-9一二三四五六七八九十百千两零〇]+\s*[章回节卷集部篇])\s*[:：、\s]*(.*)$/, base: 0.95 },
  { re: /^\s*(Chapter|CHAPTER|chapter)\s+(\d+|[IVXLCivxlc]+)(?:\s*[.:：\-\s]\s*(.*))?$/, base: 0.9 },
  { re: /^\s*([0-9]{1,4})\s*[、.．:：]\s*(\S.{0,30})$/, base: 0.55 },
  { re: /^\s*[（(]\s*([0-9一二三四五六七八九十]+)\s*[)）]\s*(\S.{0,30})$/, base: 0.4 },
  { re: /^\s*(序章|序言|楔子|引子|尾声|终章|番外)\s*.*$/, base: 0.9 },
];

export function splitByHeuristics(text: string): SplitResult {
  const lines = text.split(/\r\n|\r|\n/);
  const points: SplitPoint[] = [];
  const bodyLens: number[] = [];
  for (const line of lines) bodyLens.push(line.length);

  // 统计兜底：正文行平均长度，短行且无句末标点的疑似标题
  const nonEmpty = bodyLens.filter((l) => l > 0);
  const avg = nonEmpty.length ? nonEmpty.reduce((a, b) => a + b, 0) / nonEmpty.length : 40;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!line.trim()) continue;
    let matched: SplitPoint | null = null;
    for (const { re, base } of TITLE_PATTERNS) {
      const m = line.match(re);
      if (m) {
        const title = m.slice(1).filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
        // 置信度修正：行越长越不像标题；后面紧跟正文加分
        let conf = base;
        if (line.length > 50) conf -= 0.35;
        const nextNonEmpty = lines.slice(i + 1).find((l) => l.trim());
        if (nextNonEmpty && nextNonEmpty.length > 30) conf = Math.min(1, conf + 0.05);
        matched = { line: i, title: title.slice(0, 60), confidence: Math.max(0.05, Math.min(1, conf)), source: "pattern" };
        break;
      }
    }
    if (!matched) {
      const short = line.trim().length <= Math.max(20, avg * 0.35);
      const noPunct = !/[。！？…」"’】,.!?]$/.test(line.trim());
      const nextIsLong = (lines[i + 1] ?? "").length > avg * 0.8;
      if (short && noPunct && nextIsLong && line.trim().length >= 2) {
        matched = { line: i, title: line.trim().slice(0, 60), confidence: 0.3, source: "stats" };
      }
    }
    if (matched) points.push(matched);
  }
  return { points };
}

export interface ProposedChapter {
  title: string;
  /** 原文 [start, end) 行区间 */
  startLine: number;
  endLine: number;
  /** 建议该章是否需要 LLM 复核边界 */
  lowConfidence: boolean;
}

/** 把切点装配成章节提案；无切点的整本作为单章提案 */
export function assembleChapters(text: string, result: SplitResult): ProposedChapter[] {
  const lines = text.split(/\r\n|\r|\n/);
  const total = lines.length;
  const chapters: ProposedChapter[] = [];
  const kept = result.points.filter((p) => p.confidence >= 0.25);
  if (kept.length === 0) {
    return [{ title: "全文", startLine: 0, endLine: total, lowConfidence: true }];
  }
  // 第一个切点之前若还有正文，归入第一章
  for (let i = 0; i < kept.length; i++) {
    const p = kept[i];
    const start = i === 0 && p.line > 0 ? 0 : p.line;
    const end = i + 1 < kept.length ? kept[i + 1].line : total;
    chapters.push({ title: p.title, startLine: start, endLine: end, lowConfidence: p.confidence < 0.6 });
  }
  return chapters;
}

export function sliceChapterText(text: string, startLine: number, endLine: number): string {
  const lines = text.split(/\r\n|\r|\n/);
  return lines.slice(startLine, endLine).join("\n").trim() + "\n";
}

/** 超大单章内部再切分建议（spec §4.2）：找内部空行分隔的高密度段落边界 */
export function proposeInnerSplits(chapterText: string, threshold = 20000): number[] {
  if (chapterText.length <= threshold) return [];
  const paras = chapterText.split(/\n\s*\n/);
  if (paras.length < 4) return [];
  const targets = Math.ceil(chapterText.length / threshold);
  const points: number[] = [];
  let acc = 0;
  for (let i = 0; i < paras.length - 1; i++) {
    acc += paras[i].length;
    if (acc >= chapterText.length / targets) {
      points.push(i + 1);
      acc = 0;
    }
  }
  return points;
}
