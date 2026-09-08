import {
  BUNDLE_EXT,
  buildBundle,
  buildIllustrationPrompt,
  extractEntityCards,
  makeContentRevision,
  makeStructureRevision,
  proposeCleanSuggestions,
  proposeStructure,
  refineLowConfidence,
  revertPatches,
  applyPatches,
  sha256Hex,
  sliceChapterText,
  splitParagraphs,
  uuidv7,
  type Anchor,
  type ContentPatch,
  type EntityCard,
  type Illustration,
  type ProposedChapter,
  type Revision,
  type Work,
} from "@marginal/core";
import { store, type ProviderEntry } from "./store";

export interface IllustrationCandidate {
  chapterKey: string;
  paraIndex: number;
}

export async function confirmImport(
  title: string,
  filename: string,
  text: string,
  chapters: ProposedChapter[],
): Promise<Work> {
  const chapterData = chapters.map((chapter) => ({
    title: chapter.title,
    text: sliceChapterText(text, chapter.startLine, chapter.endLine),
  }));
  const work = await store.createWorkFromText(
    title.trim() || filename.replace(/\.txt$/i, ""),
    filename,
    text,
    chapterData,
  );
  store.notify(`已导入 ${chapterData.length} 章`);
  store.navigate({ name: "work", workId: work.id, tab: "reader" });
  return work;
}

function taskClient(work: Work, kind: "repair" | "extract" | "illustration") {
  const config = work.settings.taskConfigs[kind] ?? store.defaultTaskConfig(kind);
  return { client: store.getClient(config.providerId), model: config.model, providerId: config.providerId };
}

export async function restructure(work: Work): Promise<number> {
  const chapters = await store.repo.listChapters(work.id);
  const fullText = (await Promise.all(chapters.map((chapter) => store.repo.getChapterText(chapter.id)))).join("\n\n");
  let proposed = proposeStructure(fullText);
  const { client, model, providerId } = taskClient(work, "repair");
  const runId = uuidv7();
  const startedAt = Date.now();
  const running = { id: runId, workId: work.id, kind: "structure" as const, providerId, model, startedAt, finishedAt: null, status: "running" as const };
  await store.repo.putRun(running);
  try {
    if (client.constructor?.name !== "DemoProvider") proposed = await refineLowConfidence(client, model, fullText, proposed);
    const before = chapters.map((chapter) => ({ idx: chapter.idx, title: chapter.title }));
    const texts = proposed.map((chapter) => sliceChapterText(fullText, chapter.startLine, chapter.endLine));
    const replacements = await Promise.all(proposed.map(async (chapter, index) => ({
      chapter: {
        id: uuidv7(), workId: work.id, idx: index, title: chapter.title,
        wordCount: texts[index].length,
        contentHash: await sha256Hex(new TextEncoder().encode(texts[index])),
      },
      text: texts[index],
    })));
    await store.repo.replaceChapters(work.id, replacements);
    await store.repo.putRevision(makeStructureRevision(work.id, runId, before, proposed.map((chapter, index) => ({ idx: index, title: chapter.title }))));
    await store.repo.putRun({ ...running, finishedAt: Date.now(), status: "done" });
    await store.updateWork(work);
    store.notify(`已重切为 ${proposed.length} 章`);
    return proposed.length;
  } catch (error) {
    await store.repo.putRun({ ...running, finishedAt: Date.now(), status: "failed" });
    throw error;
  }
}

export async function genCleanSuggestions(work: Work, chapterId: string): Promise<ContentPatch[]> {
  const text = await store.repo.getChapterText(chapterId);
  const { client, model, providerId } = taskClient(work, "repair");
  const runId = uuidv7();
  const startedAt = Date.now();
  const running = { id: runId, workId: work.id, kind: "content" as const, providerId, model, startedAt, finishedAt: null, status: "running" as const };
  await store.repo.putRun(running);
  try {
    const patches = await proposeCleanSuggestions(client, model, text);
    await store.repo.putRevision(makeContentRevision(work, chapterId, runId, patches));
    await store.repo.putRun({ ...running, finishedAt: Date.now(), status: "done" });
    store.notify(patches.length ? `AI 给出 ${patches.length} 条建议，请审核` : "未发现可清洗项");
    return patches;
  } catch (error) {
    await store.repo.putRun({ ...running, finishedAt: Date.now(), status: "failed" });
    throw error;
  }
}

export async function applySuggestions(work: Work, chapterId: string, suggestions: ContentPatch[]): Promise<void> {
  const text = await store.repo.getChapterText(chapterId);
  const newText = applyPatches(text, suggestions);
  const chapter = (await store.repo.listChapters(work.id)).find((candidate) => candidate.id === chapterId);
  if (!chapter) throw new Error("章节不存在");
  await store.repo.putChapter(work.id, { ...chapter, wordCount: newText.length, contentHash: await sha256Hex(new TextEncoder().encode(newText)) }, newText);
  await store.updateWork(work);
  store.notify("已应用接受的修改");
}

export async function rollback(work: Work, revision: Revision): Promise<void> {
  if (revision.kind !== "content") throw new Error("结构修订请通过重新切分生成新修订");
  const patches = (revision.payload as { patches: ContentPatch[] }).patches;
  const text = await store.repo.getChapterText(revision.chapterId);
  const newText = revertPatches(text, patches);
  const chapter = (await store.repo.listChapters(work.id)).find((candidate) => candidate.id === revision.chapterId);
  if (!chapter) throw new Error("章节不存在");
  await store.repo.putChapter(work.id, { ...chapter, wordCount: newText.length, contentHash: await sha256Hex(new TextEncoder().encode(newText)) }, newText);
  await store.repo.updateRevision({ ...revision, payload: { patches: patches.map((patch) => ({ ...patch, status: "undone" as const })) } });
  await store.updateWork(work);
  store.notify("修订已回滚");
}

export async function extractEntities(work: Work): Promise<EntityCard[]> {
  const { client, model } = taskClient(work, "extract");
  const chapters = await store.repo.listChapters(work.id);
  const texts: Record<string, string> = {};
  for (const chapter of chapters) texts[chapter.id] = await store.repo.getChapterText(chapter.id);
  const found = await extractEntityCards(client, model, work, texts);
  const existing = await store.repo.listEntityCards(work.id);
  for (const card of found) {
    if (!existing.some((item) => item.name === card.name && item.kind === card.kind)) await store.repo.putEntityCard(card);
  }
  store.notify(`提取到 ${found.length} 张实体卡（草稿）`);
  return found;
}

export async function toggleCanon(card: EntityCard): Promise<EntityCard> {
  const updated: EntityCard = { ...card, status: card.status === "draft" ? "canon" : "draft" };
  await store.repo.putEntityCard(updated);
  if (updated.status === "canon") store.notify(`「${updated.name}」已正典——插图链路将携带其定妆照作参考图`);
  return updated;
}

async function storeGeneratedImage(workId: string, mime: string, dataBase64: string): Promise<string> {
  const bytes = Uint8Array.from(atob(dataBase64), (character) => character.charCodeAt(0));
  const blobId = uuidv7();
  const storageKey = `${workId}/${blobId}`;
  await store.repo.putBlob({ id: blobId, workId, kind: "image", byteSize: bytes.length, mime, sha256: await sha256Hex(bytes), storageKey }, bytes);
  return blobId;
}

export async function uploadPortrait(work: Work, card: EntityCard, file: File): Promise<void> {
  const bytes = new Uint8Array(await file.arrayBuffer());
  const blobId = uuidv7();
  const storageKey = `${work.id}/${blobId}`;
  await store.repo.putBlob({
    id: blobId, workId: work.id, kind: "image", byteSize: bytes.length,
    mime: file.type || "image/png", sha256: await sha256Hex(bytes), storageKey,
  }, bytes);
  await store.repo.putEntityCard({ ...card, portraitBlobId: blobId });
  store.notify("定妆照已上传");
}

export function genPortrait(work: Work, card: EntityCard): void {
  const { client, model } = taskClient(work, "illustration");
  const prompt = buildIllustrationPrompt(`「${card.name}」的单人标准像，纯色背景，上半身，设定集风格`, [card], false);
  store.queue.add(`定妆照：${card.name}`, async () => {
    const result = await client.generateImage({ prompt, references: [], model });
    const blobId = await storeGeneratedImage(work.id, result.mime, result.dataBase64);
    await store.repo.putEntityCard({ ...card, portraitBlobId: blobId });
    store.notify(`「${card.name}」定妆照已生成`);
  });
  store.emit();
}

async function illustrationContext(work: Work) {
  const { client, model, providerId } = taskClient(work, "illustration");
  const cards = (await store.repo.listEntityCards(work.id)).filter((card) => card.status === "canon").slice(0, 3);
  const blobs = await store.repo.listBlobs(work.id);
  const references: { blobId: string; mime: string; dataBase64: string }[] = [];
  for (const card of cards) {
    if (!card.portraitBlobId) continue;
    const blob = blobs.find((candidate) => candidate.id === card.portraitBlobId);
    if (!blob) continue;
    const data = await store.repo.getBlobData(blob.storageKey);
    if (!data) continue;
    let binary = "";
    for (let index = 0; index < data.length; index += 0x8000) binary += String.fromCharCode(...data.subarray(index, index + 0x8000));
    references.push({ blobId: blob.id, mime: blob.mime, dataBase64: btoa(binary) });
  }
  return { client, model, providerId, cards, references };
}

export async function generateIllustration(work: Work, chapterId: string, paraIndex: number, sceneDescription: string): Promise<void> {
  const context = await illustrationContext(work);
  const prompt = buildIllustrationPrompt(sceneDescription, context.cards, context.references.length > 0);
  store.queue.add(`插图：${sceneDescription.slice(0, 18)}`, async () => {
    const result = await context.client.generateImage({ prompt, references: context.references.map(({ mime, dataBase64 }) => ({ mime, dataBase64 })), model: context.model });
    const blobId = await storeGeneratedImage(work.id, result.mime, result.dataBase64);
    const illustration: Illustration = {
      id: uuidv7(), workId: work.id, prompt, providerId: context.providerId, model: context.model,
      blobId, status: "accepted", genMeta: { referenceBlobIds: context.references.map((reference) => reference.blobId) },
      entityCardIds: context.cards.map((card) => card.id), createdAt: Date.now(),
    };
    await store.repo.putIllustration(illustration);
    const anchor: Anchor = {
      id: uuidv7(), workId: work.id, chapterId, paraIndex, charOffset: 0,
      targetType: "illustration", targetId: illustration.id, state: "active",
    };
    await store.repo.putAnchor(anchor);
    store.notify("插图已插入锚点");
  });
  store.notify("插图已加入队列…");
  store.emit();
}

export async function enqueueIllustrations(work: Work, candidates: IllustrationCandidate[]): Promise<number> {
  const chapters = await store.repo.listChapters(work.id);
  const context = await illustrationContext(work);
  if (work.settings.budgetLimit > 0) store.queue.setBudgetLimit(work.settings.budgetLimit);
  let enqueued = 0;
  for (const candidate of candidates) {
    const chapter = chapters.find((item) => item.id === candidate.chapterKey);
    if (!chapter) continue;
    const text = await store.repo.getChapterText(chapter.id);
    const scene = splitParagraphs(text)[candidate.paraIndex] ?? "";
    const prompt = buildIllustrationPrompt(scene.slice(0, 200), context.cards, context.references.length > 0);
    enqueued++;
    store.queue.add(`插图：${chapter.title}·段${candidate.paraIndex + 1}`, async () => {
      const result = await context.client.generateImage({ prompt, references: context.references.map(({ mime, dataBase64 }) => ({ mime, dataBase64 })), model: context.model });
      const blobId = await storeGeneratedImage(work.id, result.mime, result.dataBase64);
      await store.repo.putIllustration({
        id: uuidv7(), workId: work.id, prompt, providerId: context.providerId, model: context.model,
        blobId, status: "draft", genMeta: { referenceBlobIds: context.references.map((reference) => reference.blobId) },
        entityCardIds: context.cards.map((card) => card.id), createdAt: Date.now(),
      });
    });
  }
  store.notify(`已入队 ${enqueued} 个插图任务${work.settings.budgetLimit > 0 ? `（预算上限 ${work.settings.budgetLimit} 次）` : ""}`);
  store.emit();
  return enqueued;
}

export async function setBudgetLimit(work: Work, value: number): Promise<void> {
  work.settings = { ...work.settings, budgetLimit: Math.max(0, Math.floor(value)) };
  await store.updateWork(work);
  store.queue.setBudgetLimit(work.settings.budgetLimit || null);
  store.notify(work.settings.budgetLimit ? `预算上限已设为 ${work.settings.budgetLimit} 次` : "已取消预算上限");
}

export function saveProvider(provider: ProviderEntry): void {
  const index = store.providers.findIndex((candidate) => candidate.id === provider.id);
  if (index >= 0) store.providers[index] = provider;
  else store.providers.push(provider);
  store.saveProviders();
  store.emit();
}

export function deleteProvider(id: string): void {
  store.providers = store.providers.filter((provider) => provider.id !== id || provider.kind === "demo");
  store.saveProviders();
  store.emit();
}

export async function diagnose(provider: ProviderEntry): Promise<"direct" | "needs-proxy"> {
  saveProvider({ ...provider, diagnostic: "checking" });
  const result = provider.kind === "demo" ? "direct" : await store.getClient(provider.id).diagnose();
  saveProvider({ ...provider, diagnostic: result });
  store.notify(result === "direct" ? `「${provider.name}」浏览器可直连` : `「${provider.name}」浏览器无法直连——请走本地代理`);
  return result;
}

export async function exportBundle(workId: string): Promise<void> {
  const work = await store.repo.getWork(workId);
  if (!work) throw new Error("书稿不存在");
  const chapters = await store.repo.listChapters(workId);
  const chapterTexts: Record<string, string> = {};
  for (const chapter of chapters) chapterTexts[chapter.id] = await store.repo.getChapterText(chapter.id);
  const blobs = await store.repo.listBlobs(workId);
  const blobData: Record<string, Uint8Array> = {};
  for (const blob of blobs) {
    const data = await store.repo.getBlobData(blob.storageKey);
    if (data) blobData[blob.storageKey] = data;
  }
  const zip = buildBundle({
    work, chapters, chapterTexts, runs: await store.repo.listRuns(workId),
    revisions: await store.repo.listRevisions(workId), entityCards: await store.repo.listEntityCards(workId),
    illustrations: await store.repo.listIllustrations(workId), anchors: await store.repo.listAnchors(workId), blobs,
  }, blobData);
  const url = URL.createObjectURL(new Blob([zip as BlobPart], { type: "application/octet-stream" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = `${work.title}${BUNDLE_EXT}`;
  link.click();
  URL.revokeObjectURL(url);
  store.notify("全书包已导出");
}

