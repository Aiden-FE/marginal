---
labels: [wayfinder:map]
title: 跨端 AI 电子书应用 v1 规格
---

# 跨端 AI 电子书应用 v1 规格

## Destination

一份可直接交给实现会话执行的 v1 产品+技术规格书：覆盖个人向跨端（桌面全功能 + web 全功能）AI 电子书应用的功能范围、领域模型、AI 流水线、供应商抽象与数据格式。走完的标志：前沿工单清空、雾区排空、spec 成文。

**✅ 已于 2026-09-06 到达：spec 成文于 [docs/SPEC.md](../docs/SPEC.md)，全部工单关闭，雾区排空。**

## Notes

- **运作模式修订（2026-09-06）**：用户已授权无人值守——所有 HITL 工单由代理按 grilling 轮次中给出的推荐答案直接定夺并记录；每个工单的 Resolution 中须列明采纳的推荐项，供用户事后否决。

- 领域词汇见根目录 [CONTEXT.md](../CONTEXT.md)；处理工单时默认先调 Skill "grilling" + "domain-modeling"（research 工单调 "research"，prototype 工单调 "prototype"）。
- 本地 Markdown 追踪器约定：地图在本文件；工单在 `wayfinder/tickets/NNN-slug.md`，frontmatter 含 `status: open|closed`、`labels`、`assignee`、`blocked-by: [NNN]`；决议以工单内 `## Resolution` 节记录；前沿 = open、blocked-by 全部 closed 且未 assign 的工单。

**建图时已锁定的立场（源自目的地 grilling，2026-09-06）**：

- 个人工具；无账号、无云、无内容合规问题。
- v1 = 桌面端 + web 端，双端全功能；AI 任务在 web 端于浏览器内跑；移动端后置（见 Out of scope）。
- v1 核心体验：AI 修复导入的 TXT 小说（章节切分 + 内容清洗）；插图链路其次。
- 供应商抽象：协议层仅 OpenAI-compatible（文本任务维持不变）；按任务类型（修复 / 实体提取 / 插图生成）独立配置供应商与模型；插图任务必须支持参考图输入。**修订（research/003）**：图像任务的参考图无统一兼容形状，预留 per-provider adapter 扩展点，UI 按能力位渲染。
- 修复边界：章节结构自动 + 可重跑；正文改动一律 diff 审核制。
- 实体卡确认 = 正典 = 参考图资格：确认前插图是草稿质量，确认后链路必带参考图。
- 阅读器 v1 即需分页引擎 + 图文混排（仿真阅读器，非滚动简版）。
- 数据 v1 纯本地（桌面与 web 各自本地），模型须设计成可同步；双端流动靠"全书包"手动导出/导入。
- 导入格式 v1 仅 TXT。

## Decisions so far

<!-- 每行一个已关闭工单：[工单名](链接): 一句话决议 -->

- [跨端技术选型评估](tickets/001-cross-platform-stack.md): TypeScript monorepo「web 核心为第一公民」+ Tauri 2 桌面壳；存储 SQLite everywhere（桌面 sqlx / web sqlite-wasm OPFS-sahpool in Worker）；否决 Flutter 与 RN/Expo；Electron 为备选（只换 adapter）。
- [浏览器端 AI 任务可行性](tickets/002-browser-ai-feasibility.md): web 全功能成立，附三条件——供应商连通性诊断必做、任务队列以 checkpoint 断点续跑为一等公民、存储容量充足；本地一键小代理进 v1。
- [文生图参考图能力与人物一致性调研](tickets/003-image-reference-research.md): 参考图是主流图像 API 标配；正典实体卡配"一张定妆照"作唯一参考、多实体 ≤3 张；图像协议走 per-provider adapter（v1 内置 OpenAI edits 形状 + 火山方舟形状）。
- [AI 修复流水线与修订模型设计](tickets/004-repair-pipeline.md): 切分 = 启发式先行 + LLM 兜底低置信区间 + 预览确认；正文清洗 = 结构化建议 + diff 审核制（规范化默认关闭）；修订按修复批次分组，支持单条与整批回滚；顺序队列逐章 checkpoint。
- [数据模型与全书包格式设计](tickets/005-data-model-bundle.md): UUIDv7 主键、revisions 只追加、锚点 = 章内段落索引+字符偏移（补丁重映射 + orphaned 兜底）；blob 出库；全书包 = .mabk ZIP 全量导出，导入二选一（覆盖/副本），不做字段级合并。
- [插图链路与确认机制设计](tickets/006-illustration-pipeline.md): 实体卡 draft→canon 状态机 + 定妆照（AI 生成/上传）；单段与批量配图共用插图记录；队列带预算上限与重试；锚点随修复补丁重映射。
- [阅读器分页与图文混排原型](tickets/007-reader-prototype.md): 原型实测可行——CSS 多栏分页零漂移、Range 锚点插图精确插入并重排、字号/视口重排正常；两个实现坑（栏距=视口宽−栏宽；插图 max-height 适配栏高）写入 spec。

## Not yet specified

<!-- 雾区已于 2026-09-06 排空：排版细节（007）、人物卡 schema 与 prompt 模板（005/006）、修复质量评估（spec §5）、小代理交付形态（spec §4.7）、spec 形态（docs/SPEC.md）均已落定。 -->

## Out of scope

- 移动端 v1 实现与形态：目的地是 v1（桌面+web）spec；移动端仅以"核心逻辑可复用"的约束进入 spec。 **后续已作为独立新图重启：[微信小程序版移动端 v1 规格](weapp/map.md)。**
- EPUB 导入/导出：v1 仅 TXT 导入、无导出；EPUB 支持后置于 v1 之后（建图时用户曾称"进 fog"，按雾的定义它越过目的地，归于此）。
- 云同步 / 账号体系 / 多租户：个人工具定位排除。
- 多协议 AI 适配器（Anthropic/Gemini 原生协议等）：仅 OpenAI-compatible；除非实战证伪，再立新图。
- 双端并发编辑同一本书的字段级合并：全书包 v1 的"覆盖或副本"语义已覆盖日常场景；自动合并留待未来新图（schema 已留 CRDT 口子）。
