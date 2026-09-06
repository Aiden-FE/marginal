// 锚点与补丁：相对位置 {paraIndex, charOffset}；补丁重映射（spec §3、工单 004/006）。

import type { AnchorPoint, ContentPatch } from "./types.js";

/**
 * 把「对段落文本应用补丁」后的新位置算出来（spec：修订补丁天然携带新旧偏移映射）。
 * 返回 null 表示该锚点所在段落被删除/合并，应标 orphaned。
 */
export function remapAnchor(anchor: AnchorPoint, patches: ContentPatch[], paragraphsAfter: string[] | null): AnchorPoint | "orphaned" {
  let { paraIndex, charOffset } = anchor;
  for (const p of patches) {
    const a = p.anchor;
    if (a.paraIndex === paraIndex) {
      if (a.charOffset < charOffset) {
        charOffset += p.replacement.length - p.original.length;
      }
    } else if (a.paraIndex < paraIndex) {
      // 段落合并/删除导致的整体位移由调用方按段落结构变化处理
    }
  }
  if (paragraphsAfter && (paraIndex < 0 || paraIndex >= paragraphsAfter.length)) return "orphaned";
  if (charOffset < 0) charOffset = 0;
  return { paraIndex, charOffset };
}

/** 段落切分：与阅读器渲染保持一致（空行分段） */
export function splitParagraphs(text: string): string[] {
  return text.split(/\n\s*\n/).map((s) => s.trim()).filter(Boolean);
}
