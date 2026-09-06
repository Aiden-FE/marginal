// 演示供应商：无需 API key 的内置 Mock，覆盖修复/提取/插图三类任务，
// 让整条流水线在没有供应商密钥时也能端到端跑通（测试与演示用途）。

import type { ChatMessage, ImageResult } from "./types.js";
import { parseJsonLoose, type ChatOptions } from "./provider.js";

export class DemoProvider {
  readonly id = "demo";
  readonly name = "演示模式";
  readonly baseUrl = "demo://local";
  readonly apiKey = "";
  readonly diagnostic = "direct" as const;

  async diagnose(): Promise<"direct"> {
    return "direct";
  }

  async chat(messages: ChatMessage[], _model: string, _opts: ChatOptions = {}): Promise<string> {
    void _model;
    void _opts;
    const system = messages.find((m) => m.role === "system")?.content ?? "";
    const user = messages.find((m) => m.role === "user")?.content ?? "";
    if (system.includes("文本清洗")) return this.clean(user);
    if (system.includes("设定提取")) return this.extract(user);
    if (system.includes("章节边界")) return JSON.stringify({ titleLines: [] });
    return "{}";
  }

  async chatJson<T>(messages: ChatMessage[], model: string, opts: ChatOptions = {}): Promise<T> {
    return parseJsonLoose<T>(await this.chat(messages, model, opts));
  }

  /** 找正文里的可清洗点：混入的全角乱码、广告行、常见错字 */
  private clean(user: string): string {
    const suggestions: Record<string, unknown>[] = [];
    const paraRe = /\[段(\d+)\]\s*([^\n]+)/g;
    let m: RegExpExecArray | null;
    while ((m = paraRe.exec(user))) {
      const paraIndex = parseInt(m[1], 10);
      const para = m[2];
      const adMatch = para.match(/(本书来自|最新章节|www\.\S+|\.com|笔趣阁|请记住本站)/i);
      if (adMatch) {
        suggestions.push({
          anchor: { paraIndex, charOffset: Math.max(0, para.indexOf(adMatch[1]) - 4) },
          original: para.slice(Math.max(0, para.indexOf(adMatch[1]) - 4)),
          replacement: "",
          category: "广告",
          reason: `推广/水印文本（${adMatch[1]}）`,
        });
      }
      if (/[ﬄﬅﬀвДφω✓◆□]/.test(para)) {
        const bad = para.match(/[ﬄﬅﬀвДφω✓◆□]+/)!;
        suggestions.push({
          anchor: { paraIndex, charOffset: para.indexOf(bad[0]) },
          original: bad[0],
          replacement: "",
          category: "乱码",
          reason: "乱码字符",
        });
      }
      const typo = para.match(/地说的|他门|的的/);
      if (typo) {
        suggestions.push({
          anchor: { paraIndex, charOffset: para.indexOf(typo[0]) },
          original: typo[0],
          replacement: typo[0] === "他门" ? "他们" : typo[0] === "地说的" ? "地说道" : "的",
          category: "错字",
          reason: "常见错字",
        });
      }
    }
    return JSON.stringify({ suggestions: suggestions.slice(0, 30) });
  }

  private extract(user: string): string {
    const names = [...new Set((user.match(/[「『]?([林萧叶陈王苏李]...\b|[A-Za-z]{3,})/g) ?? []).slice(0, 4))];
    const cards = [
      { kind: "character", name: names[0]?.slice(0, 4) || "主角", aliases: [], attributes: { 外貌: "青衫长身，眉目冷峻", 性别年龄: "男，二十上下" } },
      { kind: "character", name: names[1]?.slice(0, 4) || "老者", aliases: [], attributes: { 外貌: "白发苍苍，浑浊瞳孔深处有精光", 性别年龄: "男，年逾六旬" } },
      { kind: "scene", name: "青石镇客栈", aliases: ["客栈"], attributes: { 氛围: "夜色中灯火明明灭灭，像困兽的呼吸", 环境: "木质柜台，擦杯的掌柜" } },
      { kind: "scene", name: "风雪山道", aliases: [], attributes: { 氛围: "漫天风雪，寒鸦惊起", 环境: "山风掠过檐角，铜铃轻响" } },
    ];
    return JSON.stringify({ cards });
  }

  async generateImage(_req: { prompt: string }): Promise<ImageResult> {
    void _req;
    // 合成的占位"插图"：把 prompt 摘要画进 SVG
    const seed = Math.random().toString(36).slice(2, 7);
    const label = (_req.prompt.match(/场景：[^\n]{0,24}/) ?? ["场景：小说插图"])[0];
    const hue = Math.floor(Math.random() * 360);
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360">
      <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="hsl(${hue},40%,70%)"/><stop offset="1" stop-color="hsl(${(hue + 60) % 360},45%,45%)"/>
      </linearGradient></defs>
      <rect width="640" height="360" fill="url(#g)"/>
      <text x="320" y="170" font-size="24" text-anchor="middle" fill="#fff" font-family="serif">${escapeXml(label)}</text>
      <text x="320" y="210" font-size="14" text-anchor="middle" fill="#ffffffaa" font-family="monospace">demo · ${seed}</text>
    </svg>`;
    const b64 = btoa(unescape(encodeURIComponent(svg)));
    return { mime: "image/svg+xml", dataBase64: b64 };
  }
}

function escapeXml(s: string): string {
  return s.replace(/[<>&"]/g, (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;", '"': "&quot;" })[c]!);
}
