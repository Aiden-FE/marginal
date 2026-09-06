---
labels: [wayfinder:map]
title: 跨端 AI 电子书应用 v1 规格
---

# 跨端 AI 电子书应用 v1 规格

## Destination

一份可直接交给实现会话执行的 v1 产品+技术规格书：覆盖个人向跨端（桌面全功能 + web 全功能）AI 电子书应用的功能范围、领域模型、AI 流水线、供应商抽象与数据格式。走完的标志：前沿工单清空、雾区排空、spec 成文。

## Notes

- 领域词汇见根目录 [CONTEXT.md](../CONTEXT.md)；处理工单时默认先调 Skill "grilling" + "domain-modeling"（research 工单调 "research"，prototype 工单调 "prototype"）。
- 本地 Markdown 追踪器约定：地图在本文件；工单在 `wayfinder/tickets/NNN-slug.md`，frontmatter 含 `status: open|closed`、`labels`、`assignee`、`blocked-by: [NNN]`；决议以工单内 `## Resolution` 节记录；前沿 = open、blocked-by 全部 closed 且未 assign 的工单。

**建图时已锁定的立场（源自目的地 grilling，2026-09-06）**：

- 个人工具；无账号、无云、无内容合规问题。
- v1 = 桌面端 + web 端，双端全功能；AI 任务在 web 端于浏览器内跑；移动端后置（见 Out of scope）。
- v1 核心体验：AI 修复导入的 TXT 小说（章节切分 + 内容清洗）；插图链路其次。
- 供应商抽象：协议层仅 OpenAI-compatible；按任务类型（修复 / 实体提取 / 插图生成）独立配置供应商与模型；插图任务必须支持参考图输入。
- 修复边界：章节结构自动 + 可重跑；正文改动一律 diff 审核制。
- 实体卡确认 = 正典 = 参考图资格：确认前插图是草稿质量，确认后链路必带参考图。
- 阅读器 v1 即需分页引擎 + 图文混排（仿真阅读器，非滚动简版）。
- 数据 v1 纯本地（桌面与 web 各自本地），模型须设计成可同步；双端流动靠"全书包"手动导出/导入。
- 导入格式 v1 仅 TXT。

## Decisions so far

<!-- 每行一个已关闭工单：[工单名](链接): 一句话决议 -->

## Not yet specified

- 各端本地存储引擎的具体选型（等跨端与浏览器可行性研究出结论后才能提问）
- 排版/分页引擎的具体选型与实现路径（等跨端选型与阅读器原型）
- 人物卡 schema 与插图 prompt 模板细节（等参考图调研与插图链路设计）
- 修复质量评估方法与回归样例集（等修复流水线设计）
- spec 汇总成文的形态与组织（等前沿清空）

## Out of scope

- 移动端 v1 实现与形态：目的地是 v1（桌面+web）spec；移动端仅以"核心逻辑可复用"的约束进入 spec。
- EPUB 导入/导出：v1 仅 TXT 导入、无导出；EPUB 支持后置于 v1 之后（建图时用户曾称"进 fog"，按雾的定义它越过目的地，归于此）。
- 云同步 / 账号体系 / 多租户：个人工具定位排除。
- 多协议 AI 适配器（Anthropic/Gemini 原生协议等）：仅 OpenAI-compatible；除非实战证伪，再立新图。
