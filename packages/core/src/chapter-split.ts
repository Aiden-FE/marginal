// AI 章节切分（spec §4.2 的 LLM 结构提案路径）：
// 把带绝对行号的全文大纲交给 LLM，返回章节边界提案；行号幻觉与孤立短章在本地兜底。
// 纯函数 + LLMClient 注入，无平台依赖。

import { mergeTinyChapters, type ProposedChapter } from "./split.js";
import type { LLMClient } from "./provider.js";

export const RESTRUCTURE_SKILL_SYSTEM = `你是小说章节结构助手。给定一份带绝对行号的小说文本，找出所有真正的章节标题行。
规则：
- 只把独立成行、形如「第X章」「第X回」「Chapter N」「一、标题」的行视为章节标题；
- 正文段落、对话、场景短句、列表编号、日期都不是章节标题；
- 从第一个章节标题行开始，按行号升序输出；
- line 必须是输入中出现过的绝对行号，且该行确实形如章节标题。
只输出 JSON：{"chapters":[{"line":整数行号,"title":"章节标题(≤30字)"}]}`;

export interface AiChapterMarker {
  line: number;
  title: string;
}

export interface SplitChaptersWithAiOptions {
  /** 每块发送的行数上限（默认 1200，避免上下文超限） */
  chunkLines?: number;
  /** 每块完成后的进度回调（已完成块数, 总块数） */
  onProgress?: (done: number, total: number) => void;
}

/** 用 LLM 识别章节边界；识别不出任何标题时抛错，由调用方决定回退策略。 */
export async function splitChaptersWithAi(
  llm: LLMClient,
  model: string,
  text: string,
  options: SplitChaptersWithAiOptions = {},
): Promise<ProposedChapter[]> {
  const lines = text.split(/\r\n|\r|\n/);
  const chunkLines = options.chunkLines ?? 1200;
  const total = Math.max(1, Math.ceil(lines.length / chunkLines));
  const markers: AiChapterMarker[] = [];
  for (let chunkIndex = 0; chunkIndex < total; chunkIndex++) {
    const startLine = chunkIndex * chunkLines;
    const endLine = Math.min(lines.length, startLine + chunkLines);
    const outline = lines
      .slice(startLine, endLine)
      .map((line, offset) => `${startLine + offset}: ${line.slice(0, 60)}`)
      .join("\n")
      .slice(0, 60_000);
    const res = await llm.chatJson<{ chapters?: AiChapterMarker[] }>(
      [
        { role: "system", content: RESTRUCTURE_SKILL_SYSTEM },
        { role: "user", content: outline },
      ],
      model,
      { temperature: 0 },
    );
    options.onProgress?.(chunkIndex + 1, total);
    for (const item of res.chapters ?? []) {
      if (typeof item?.line !== "number" || !Number.isInteger(item.line)) continue;
      // 行号幻觉防护：落在块外的行号直接丢弃
      if (item.line < startLine || item.line >= endLine) continue;
      if (typeof item.title !== "string" || !item.title.trim()) continue;
      markers.push({ line: item.line, title: item.title.trim() });
    }
  }
  markers.sort((a, b) => a.line - b.line);
  const chapters = assembleAiMarkers(text, markers);
  if (chapters.length === 0) throw new Error("AI 未识别出任何章节标题");
  return chapters;
}

/** 与 splitChaptersWithAi 同一协议的本地校验器：把任意 markers 装配为安全章节提案。 */
export function assembleAiMarkers(text: string, rawMarkers: AiChapterMarker[]): ProposedChapter[] {
  const lines = text.split(/\r\n|\r|\n/);
  const markers = rawMarkers
    .filter((marker) => Number.isInteger(marker.line) && marker.line >= 0 && marker.line < lines.length && typeof marker.title === "string" && marker.title.trim())
    .sort((a, b) => a.line - b.line);
  const unique = markers.filter((marker, index) => index === 0 || marker.line !== markers[index - 1].line);
  if (unique.length === 0) return [];
  return mergeTinyChapters(
    text,
    unique.map((marker, index) => ({
      title: marker.title.trim().slice(0, 60),
      // 第一个标题行之前若还有正文，沿用启发式语义：归入第一章
      startLine: index === 0 && marker.line > 0 ? 0 : marker.line,
      endLine: index + 1 < unique.length ? unique[index + 1].line : lines.length,
      lowConfidence: false,
    })),
  );
}
