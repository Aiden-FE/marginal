// core 逻辑冒烟测试：node test/smoke.mjs（先经 esbuild 打包）
// 运行：pnpm --filter @marginal/core test
import { buildSync } from "esbuild";
import { writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const outDir = mkdtempSync(join(tmpdir(), "marginal-test-"));
const outFile = join(outDir, "core.mjs");
buildSync({
  entryPoints: [new URL("../src/index.ts", import.meta.url).pathname],
  bundle: true,
  format: "esm",
  platform: "node",
  outfile: outFile,
  external: ["node:*"],
});

const core = await import(pathToFileURL(outFile).href);
let failed = 0;
function check(name, cond, detail = "") {
  if (cond) console.log(`  ✓ ${name}`);
  else {
    failed++;
    console.error(`  ✗ ${name} ${detail}`);
  }
}

// ---------- 切分 ----------
const sample = await (await import("node:fs/promises")).readFile(new URL("../../app/public/sample-novel.txt", import.meta.url), "utf8");
const proposed = core.proposeStructure(sample);
check("切分识别全部 8 章", proposed.length === 8, `实际 ${proposed.length}`);
check("标题无 undefined", proposed.every((c) => typeof c.title === "string" && c.title !== "undefined"));
check("超大章内部切分建议为纯函数", Array.isArray(core.proposeInnerChapterSplits("x".repeat(25000))));

// ---------- 切章防误切 ----------
{
  // 正文中独立成行的短句（曾因统计兜底被切成章）
  const noisy = Array.from({ length: 30 }, (_, i) => `这是第${i}段正文，足够长以至于不会被当成标题，句末有标点。`).join("\n");
  const statsTrap = [
    "第一章 起点",
    ...Array.from({ length: 8 }, () => "正文段落，句末标点，保持这一章有足够的内容长度。"),
    "夜色渐深",
    ...Array.from({ length: 8 }, () => "正文继续，句末标点，短句不能凭空制造新的章节。"),
    "第二章 归途",
    ...Array.from({ length: 8 }, () => "更多正文，句末标点，保持这一章有足够的内容长度。"),
  ].join("\n");
  const noisyProposed = core.proposeStructure(noisy);
  check("纯正文不产生章节切点", noisyProposed.length === 1, `实际 ${noisyProposed.length}`);
  const trapProposed = core.proposeStructure(statsTrap);
  check("正文短句不再被切成章", trapProposed.length === 2, `实际 ${trapProposed.length}: ${trapProposed.map((c) => c.title).join("|")}`);

  // 孤立短章（单张内容）应并入相邻章，序章例外
  const tiny = [
    "第一章", ...Array.from({ length: 12 }, () => "正常长度的正文段落，凑够行数与字符数。"),
    "第二章", "只有一行正文。",
    "第三章", ...Array.from({ length: 12 }, () => "正常长度的正文段落，凑够行数与字符数。"),
  ].join("\n");
  const tinyProposed = core.proposeStructure(tiny);
  check("孤立短章并入相邻章", tinyProposed.length === 2, `实际 ${tinyProposed.length}`);
  const preface = ["序章", "短短一句。", "第一章", ...Array.from({ length: 12 }, () => "正常长度的正文段落，凑够行数与字符数。")].join("\n");
  const prefaceProposed = core.proposeStructure(preface);
  check("序章等特殊短章保留", prefaceProposed.length === 2 && prefaceProposed[0].title === "序章", `实际 ${prefaceProposed.map((c) => c.title).join("|")}`);
}

// ---------- AI 切章（demo provider） ----------
{
  const demo = new core.DemoProvider();
  const aiChapters = await core.splitChaptersWithAi(demo, "demo", sample);
  check("demo AI 切章识别全部 8 章", aiChapters.length === 8, `实际 ${aiChapters.length}`);
  check("AI 切章边界覆盖全文", aiChapters[0].startLine === 0 && aiChapters[aiChapters.length - 1].endLine === sample.split(/\r\n|\r|\n/).length);
  // 行号幻觉防护：块外行号被丢弃
  const markerText = [
    "第一章", ...Array.from({ length: 10 }, () => "第一章正文足够长，避免被最小章节体量保护合并。"),
    "第二章", ...Array.from({ length: 10 }, () => "第二章正文足够长，验证 AI 边界校验。"),
  ].join("\n");
  const markers = core.assembleAiMarkers(markerText, [
    { line: 99, title: "幻觉章" },
    { line: 0, title: "第一章" },
    { line: 11, title: "第二章" },
  ]);
  check("AI 行号幻觉被过滤", markers.length === 2 && markers.every((c) => c.title !== "幻觉章"), JSON.stringify(markers.map((c) => c.title)));
}

// ---------- Agent 网关 ----------
{
  const seen = [];
  const transport = {
    async chat(messages) {
      seen.push(messages);
      return JSON.stringify({ ok: true, system: messages[0]?.content ?? "" });
    },
    async chatJson(messages, model, opts) {
      const text = await this.chat(messages, model, opts);
      return JSON.parse(text);
    },
  };
  const skill = { id: "restructure", description: "切章", systemPrompt: "切章技能说明" };
  const tool = {
    name: "lookup_character",
    description: "查询实体卡",
    inputSchema: { type: "object" },
    async execute(input) { return { echo: input }; },
  };
  const direct = core.createDirectAgentGateway(transport, { skills: [skill] });
  const agent = core.createToolAgentGateway(transport, { skills: [skill], tools: [tool] });
  const result = await agent.chatJson([{ role: "system", content: "原始 system" }, { role: "user", content: "hi" }], "m1");
  check("网关注入 skill 前缀", result.system.includes("【Skill: restructure】") && result.system.includes("原始 system"), result.system.slice(0, 60));
  check("direct/agent 网关类型可区分", direct.kind === "direct" && agent.kind === "agent");
  check("网关暴露 skills/tools 注册表", agent.skills.length === 1 && agent.tools.length === 1);
  const toolResult = await agent.invokeTool("lookup_character", { name: "主角" });
  check("Agent 工具可执行", toolResult?.echo?.name === "主角");
  let toolMissing = false;
  try { await agent.invokeTool("nope", {}); } catch { toolMissing = true; }
  check("未注册工具报错", toolMissing);
  await direct.chat([{ role: "user", content: "x" }], "m1");
  check("chat 与 chatJson 走同一 skill 注入", seen.length === 2 && seen[1][0]?.content.includes("【Skill: restructure】"));
}

// ---------- 清洗建议应用/回滚 ----------
const text = "第一段没有问题。\n\n第二段有乱码вД和错字他门。\n\n第三段正常。";
const patches = [
  { anchor: { paraIndex: 1, charOffset: 6 }, original: "вД", replacement: "", category: "乱码", reason: "t", status: "accepted" },
  { anchor: { paraIndex: 1, charOffset: 11 }, original: "他门", replacement: "他们", category: "错字", reason: "t", status: "accepted" },
];
const applied = core.applyPatches(text, patches);
check("补丁应用删除乱码", !applied.includes("вД"), applied);
check("补丁应用修正错字", applied.includes("他们"), applied);
const reverted = core.revertPatches(applied, patches);
check("逆补丁回滚恢复乱码", reverted.includes("вД"), reverted);

// ---------- 全书包往返 ----------
const work = { id: "w1", title: "测试书", author: "", importSource: "h1", createdAt: 1, updatedAt: 1, settings: { taskConfigs: {}, autoNormalize: false, budgetLimit: 0 } };
const chapter = { id: "c1", workId: "w1", idx: 0, title: "第一章", wordCount: 5, contentHash: "h" };
const blob = { id: "b1", workId: "w1", kind: "image", byteSize: 3, mime: "image/png", sha256: "x", storageKey: "w1/b1" };
const zip = core.buildBundle(
  { work, chapters: [chapter], chapterTexts: { c1: "正文" }, runs: [], revisions: [], entityCards: [], illustrations: [], anchors: [], blobs: [blob] },
  { "w1/b1": new Uint8Array([1, 2, 3]) },
);
const { payload, blobData } = core.readBundle(zip);
check("全书包往返保留书名", payload.work.title === "测试书");
check("全书包往返保留正文", payload.chapterTexts.c1 === "正文");
check("全书包往返保留插图二进制", blobData["w1/b1"]?.length === 3);
const copy = core.reidForCopy(payload);
check("副本导入更换 work_id", copy.work.id !== "w1" && copy.work.title.includes("副本"));
check("副本导入重映射章节 id", copy.chapters[0].id !== "c1" && copy.chapters[0].workId === copy.work.id);

// ---------- 任务队列 ----------
const queue = new core.TaskQueue(2, 2, {});
let done = 0;
const t1 = queue.add("ok", async () => { done++; });
const t2 = queue.add("fail", async () => { throw new Error("boom"); });
await new Promise((r) => setTimeout(r, 3500)); // 首次失败后指数退避 2s 再重试
check("队列成功任务完成", t1.state === "done" && done === 1);
check("队列失败任务重试后标记 failed", t2.state === "failed" && t2.attempts === 2);

// ---------- 锚点重映射 ----------
const remapped = core.remapAnchor({ paraIndex: 1, charOffset: 5 }, patches, ["a", "b"]);
check("锚点重映射存活", remapped !== "orphaned");
const orphaned = core.remapAnchor({ paraIndex: 9, charOffset: 0 }, [], ["a"]);
check("段落消失锚点标 orphaned", orphaned === "orphaned");

console.log(failed ? `\n${failed} 项失败` : "\n全部通过 ✓");
process.exit(failed ? 1 : 0);
