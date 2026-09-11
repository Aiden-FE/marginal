---
id: 010
title: .mabk 导入与旧数据迁移
labels: [wayfinder:build]
status: closed
blocked-by: [5]
---

## Question

实现 v1 `.mabk` 全书包导入（含 Agent 新实体的 schema 版本升级）与旧数据迁移通道（002 工单第 7 条）。

## Scope

- .mabk ZIP 解析（v1 格式兼容：章节、正文、修订、实体卡、插图、锚点、blob）。
- 导入二选一：覆盖/副本（沿用 v1 语义）；schema 版本 bump 与校验。
- 导出（新 schema，向后注明差异）；迁移文档：旧应用逐本导出 → 新应用导入。

## Acceptance

- 用 v1 真实数据导出的 .mabk 可完整导入并阅读；导入损坏文件有明确错误与恢复提示。

依赖：005。

## Resolution

实现完成。v1 bundle.json/chapterTexts 兼容、ZIP blobs、format version 校验、copy re-id、blobData 完整导入与覆盖/副本语义已实现；round-trip、copy 与迁移测试通过。
