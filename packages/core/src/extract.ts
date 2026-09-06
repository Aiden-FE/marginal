// 实体提取（spec §4.4）：AI 全文/分批提取 → 实体卡（draft）。

import type { EntityCard, EntityKind, Work } from "./types.js";
import { uuidv7 } from "./ids.js";
import type { LLMClient } from "./provider.js";
import { splitParagraphs } from "./anchors.js";

const EXTRACT_SYSTEM = `你是小说设定提取助手。从给定正文提取人物、场景、物品设定。
只输出 JSON：{"cards":[{"kind":"character|scene|item","name":"名称","aliases":["别名"],"attributes":{"外貌":"","性格":"","其他…":""}}]}
规则：人物 attributes 至少含 外貌 与 性别/年龄（若有）；场景 attributes 含 氛围/环境；每类最多 8 个，按重要性排序；名字用原文叫法。`;

/** 提取候选段落（批量配图的预扫，spec §4.4）：新实体登场、场景切换、情绪高点 */
export function pickCandidateParagraphs(chapterTexts: Record<string, string>): { chapterKey: string; paraIndex: number; preview: string }[] {
  const out: { chapterKey: string; paraIndex: number; preview: string }[] = [];
  for (const [chapterKey, text] of Object.entries(chapterTexts)) {
    const paras = splitParagraphs(text);
    paras.forEach((p, i) => {
      const signals = /[骤然|突然|蓦地|只见|眼前|场景|空气|月光|风雪|火焰|血|剑|泪|笑]/.test(p);
      const isScene = /^[「『]?[^"]{10,40}[』」]?$/.test(p) === false && p.length >= 20 && i > 0 && i % 15 === 7;
      if (signals && p.length >= 30 && p.length <= 400) {
        out.push({ chapterKey, paraIndex: i, preview: p.slice(0, 60) });
      } else if (isScene) {
        out.push({ chapterKey, paraIndex: i, preview: p.slice(0, 60) });
      }
    });
  }
  return out;
}

export async function extractEntityCards(llm: LLMClient, model: string, work: Work, chapterTexts: Record<string, string>, maxChapters = 20): Promise<EntityCard[]> {
  const cards: EntityCard[] = [];
  const entries = Object.entries(chapterTexts).slice(0, maxChapters);
  for (const [chapterId, text] of entries) {
    void chapterId;
    const sample = splitParagraphs(text).slice(0, 40).join("\n").slice(0, 20000);
    if (!sample) continue;
    try {
      const res = await llm.chatJson<{ cards: { kind: string; name: string; aliases?: string[]; attributes?: Record<string, string> }[] }>(
        [
          { role: "system", content: EXTRACT_SYSTEM },
          { role: "user", content: `书名：《${work.title}》\n\n${sample}` },
        ],
        model,
        { temperature: 0.2 },
      );
      for (const c of res.cards ?? []) {
        const kind: EntityKind = c.kind === "scene" ? "scene" : c.kind === "item" ? "item" : "character";
        if (cards.some((x) => x.name === c.name && x.kind === kind)) continue;
        cards.push({
          id: uuidv7(),
          workId: work.id,
          kind,
          name: c.name,
          aliases: c.aliases ?? [],
          attributes: c.attributes ?? {},
          status: "draft",
          portraitBlobId: null,
          createdAt: Date.now(),
        });
      }
    } catch (err) {
      console.warn("提取批次失败", err);
    }
  }
  return cards;
}

/** 插图 prompt 拼接（research/003 最佳实践：参考图编号显式指代 + 人物卡文字描述） */
export function buildIllustrationPrompt(sceneDescription: string, cards: { name: string; attributes: Record<string, string> }[], withReferences: boolean): string {
  const cardDescs = cards
    .map((c, i) => {
      const attrs = Object.entries(c.attributes)
        .filter(([, v]) => v)
        .map(([k, v]) => `${k}：${v}`)
        .join("，");
      return withReferences ? `图${i + 1} 是「${c.name}」的形象参考。${c.name}：${attrs}。` : `${c.name}：${attrs}。`;
    })
    .join("\n");
  const refs = cards.length && withReferences ? `严格保持各参考图中角色的长相、发型、服饰特征一致。` : "";
  return `为小说场景绘制一幅插图，中文网文插画风格，画面完整构图。\n${cardDescs}\n场景：${sceneDescription}\n${refs}`;
}
