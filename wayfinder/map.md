---
labels: [wayfinder:map]
title: 跨端 AI 电子书应用 v1 规格
---

# 跨端 AI 电子书应用 v1 规格

## Destination

一份可直接交给实现会话执行的 v1 产品+技术规格书：覆盖个人向跨端（桌面全功能 + web 全功能）AI 电子书应用的功能范围、领域模型、AI 流水线、供应商抽象与数据格式。走完的标志：前沿工单清空、雾区排空、spec 成文。

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

## Not yet specified

- 排版/分页引擎的具体实现细节（research/001 已定向 CSS 多栏 + Range 锚点、对标 foliate-js，细节等阅读器原型验证）
- 人物卡 schema 与插图 prompt 模板细节（等插图链路设计）
- 修复质量评估方法与回归样例集（等修复流水线设计）
- 本地一键小代理的交付形态（脚本 vs 桌面端内置代理，spec 阶段随实现细节一并定）
- spec 汇总成文的形态与组织（等前沿清空）

## Out of scope

- 移动端 v1 实现与形态：目的地是 v1（桌面+web）spec；移动端仅以"核心逻辑可复用"的约束进入 spec。
- EPUB 导入/导出：v1 仅 TXT 导入、无导出；EPUB 支持后置于 v1 之后（建图时用户曾称"进 fog"，按雾的定义它越过目的地，归于此）。
- 云同步 / 账号体系 / 多租户：个人工具定位排除。
- 多协议 AI 适配器（Anthropic/Gemini 原生协议等）：仅 OpenAI-compatible；除非实战证伪，再立新图。
