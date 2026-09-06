// 修复流水线编排（spec §4.2，工单 004 决议）：
// 结构 = 启发式先行 + LLM 兜底低置信区间 + 预览确认；
// 内容 = 结构化建议 + diff 审核制；修订按批次分组、只追加、可回滚。

import { assembleChapters, proposeInnerSplits, sliceChapterText, splitByHeuristics } from "./split.js";
import type { ProposedChapter } from "./split.js";
import { splitParagraphs } from "./anchors.js";
import type { ContentPatch, Revision, SuggestionCategory, Work } from "./types.js";
import { uuidv7 } from "./ids.js";
import type { LLMClient } from "./provider.js";

export { assembleChapters, sliceChapterText, splitByHeuristics, proposeInnerSplits };
export type { ProposedChapter };

/** 第一步：纯本地结构提案（不需要网络），预览界面直接消费 */
export function proposeStructure(text: string): ProposedChapter[] {
  const { points } = splitByHeuristics(text);
  return assembleChapters(text, { points });
}

const CLEAN_SYSTEM = `你是中文小说文本清洗助手。对给定正文找出：乱码字符、广告/水印/推广行、明显错字。
只输出 JSON：{"suggestions":[{"paraIndex":整数,"charOffset":整数,"original":"原文片段(≤120字)","replacement":"修正后片段(整段删除广告时为空字符串)","category":"乱码|广告|错字|其他","reason":"一句话理由"}]}
规则：不得改写情节、对话风格与叙述语气；不确定的不要提；广告/水印行 replacement 为空串；charOffset 是片段在该段的字符偏移。`;

const INNER_SPLIT_SYSTEM = `你是小说章节边界助手。给定一章超长正文，判断是否应在内部切成多章。只输出 JSON：{"splitAfterParagraphs":[整数段落序号],"reasons":["一句话"]}`;
const LOWCONF_SYSTEM = `你是小说章节边界助手。以下文本来自自动切分结果中置信度低的部分。判断其中真正的章标题行。只输出 JSON：{"titleLines":[整数行号(相对本段)]}`;

/** 第二步（可选网络）：低置信区间的 LLM 边界复核 */
export async function refineLowConfidence(llm: LLMClient, model: string, text: string, chapters: ProposedChapter[]): Promise<ProposedChapter[]> {
  const lows = chapters.filter((c) => c.lowConfidence);
  if (!lows.length) return chapters;
  const out = [...chapters];
  for (const ch of lows) {
    const chunk = sliceChapterText(text, ch.startLine, Math.min(ch.endLine, ch.startLine + 400));
    const lines = chunk.split(/\r\n|\r|\n/);
    try {
      const res = await llm.chatJson<{ titleLines: number[] }>(
        [
          { role: "system", content: LOWCONF_SYSTEM },
          { role: "user", content: lines.map((l, i) => `${i}: ${l.slice(0, 60)}`).join("\n") },
        ],
        model,
        { temperature: 0 },
      );
      // LLM 找到更精确的标题行 → 拆分该低置信提案（保持行区间语义）
      const found = (res.titleLines ?? []).filter((n: number) => n > 0 && n < lines.length).slice(0, 20);
      if (found.length) {
        const idx = out.indexOf(ch);
        const parts: ProposedChapter[] = [];
        let cursor = ch.startLine;
        for (const rel of found) {
          const abs = ch.startLine + rel;
          parts.push({ title: lines[rel]?.trim().slice(0, 60) || `段落 ${abs}`, startLine: cursor, endLine: abs, lowConfidence: false });
          cursor = abs;
        }
        parts.push({ title: ch.title, startLine: cursor, endLine: ch.endLine, lowConfidence: false });
        out.splice(idx, 1, ...parts);
      } else {
        ch.lowConfidence = false; // LLM 复核无新发现，标记已复核
      }
    } catch {
      ch.lowConfidence = false;
    }
  }
  return out;
}

/** 正文清洗：生成结构化建议（不直接改文，spec 立场） */
export async function proposeCleanSuggestions(llm: LLMClient, model: string, chapterText: string): Promise<ContentPatch[]> {
  const paras = splitParagraphs(chapterText);
  // 超长章分批（每批 ~60 段），避免上下文爆
  const batches: { start: number; text: string }[] = [];
  for (let i = 0; i < paras.length; i += 60) {
    batches.push({
      start: i,
      text: paras.slice(i, i + 60).map((p, j) => `[段${i + j}] ${p}`).join("\n").slice(0, 24000),
    });
  }
  const patches: ContentPatch[] = [];
  for (const b of batches) {
    try {
      const res = await llm.chatJson<{ suggestions: ContentPatch[] }>(
        [
          { role: "system", content: CLEAN_SYSTEM },
          { role: "user", content: b.text },
        ],
        model,
        { temperature: 0.1 },
      );
      for (const s of res.suggestions ?? []) {
        patches.push({
          anchor: { paraIndex: (s.anchor?.paraIndex ?? 0) + b.start, charOffset: s.anchor?.charOffset ?? 0 },
          original: s.original ?? "",
          replacement: s.replacement ?? "",
          category: (["乱码", "广告", "错字", "其他"] as SuggestionCategory[]).includes(s.category) ? s.category : "其他",
          reason: s.reason ?? "",
          status: "rejected", // 默认未接受，审核制
        });
      }
    } catch (err) {
      console.warn("清洗批次失败", err);
    }
  }
  return patches;
}

/** 应用已接受的补丁 → 返回新正文（纯函数，供 UI 预览与修订应用共用） */
export function applyPatches(chapterText: string, patches: ContentPatch[]): string {
  const paras = splitParagraphs(chapterText);
  const byPara = new Map<number, ContentPatch[]>();
  for (const p of patches) {
    if (p.status !== "accepted") continue;
    const list = byPara.get(p.anchor.paraIndex) ?? [];
    list.push(p);
    byPara.set(p.anchor.paraIndex, list);
  }
  const out: string[] = [];
  for (let i = 0; i < paras.length; i++) {
    let para = paras[i];
    const list = (byPara.get(i) ?? []).slice().sort((a, b) => b.anchor.charOffset - a.anchor.charOffset);
    for (const p of list) {
      const at = para.indexOf(p.original, Math.max(0, p.anchor.charOffset - 10));
      if (at === -1) continue;
      para = para.slice(0, at) + p.replacement + para.slice(at + p.original.length);
    }
    if (para.trim()) out.push(para);
  }
  return out.join("\n\n") + "\n";
}

/** 超大单章内部切分（先启发式；spec §4.2） */
export function proposeInnerChapterSplits(chapterText: string): number[] {
  return proposeInnerSplits(chapterText);
}

export function makeContentRevision(work: Work, chapterId: string, runId: string | null, patches: ContentPatch[]): Revision {
  return {
    id: uuidv7(),
    workId: work.id,
    runId,
    chapterId,
    kind: "content",
    payload: { patches },
    createdAt: Date.now(),
  };
}

export function makeStructureRevision(workId: string, runId: string | null, before: { idx: number; title: string }[], after: { idx: number; title: string }[]): Revision {
  return {
    id: uuidv7(),
    workId,
    runId,
    chapterId: "",
    kind: "structure",
    payload: { before, after },
    createdAt: Date.now(),
  };
}

/** 回滚内容修订：对"当前正文"应用逆补丁（spec §4.2） */
export function revertPatches(chapterText: string, patches: ContentPatch[]): string {
  const inverse = patches
    .filter((p) => p.status === "accepted")
    .map((p): ContentPatch => ({ ...p, anchor: { ...p.anchor }, original: p.replacement, replacement: p.original, status: "accepted" }));
  return applyPatches(chapterText, inverse);
}
