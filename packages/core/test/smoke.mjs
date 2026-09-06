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
