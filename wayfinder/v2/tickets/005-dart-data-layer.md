---
id: 005
title: Dart 数据层与契约测试
labels: [wayfinder:build]
status: closed
blocked-by: [4]
---

## Question

建立三端共享语义的 Dart 数据层：Repository 接口沿用 v1 语义（书稿/章节/修订/批次/锚点/实体卡/插图/blob/全书包），原生 SQLite、H5 浏览器持久化，契约测试锁住引擎差异。

## Scope

- Repository 接口 + 领域模型（沿用 v1 术语，见 CONTEXT.md）。
- schema 与迁移（UUIDv7 主键、revisions 只追加、锚点 = 章内段落索引+字符偏移）。
- 原生 SQLite 与 H5 存储两个驱动；具体库由 spike 决定（002 工单第 5 条）。
- 契约测试：CRUD、章节正文、blob、修订、锚点重映射、全书包导入导出（覆盖/副本）、wipe。
- 新增实体表：Agent 会话、工具调用记录、提案。

## Acceptance

- 同一套契约测试在两个驱动上全绿。

依赖：004。

## Resolution

实现完成。Dart 领域模型、Repository 契约、memory/IndexedDB/JSON/SQLite 驱动、schema 语义、Proposal/AgentRun/ToolCall/blob 与 .mabk 数据通路已实现。统一契约测试覆盖四种驱动（含 JSON 重启恢复、IndexedDB memory factory、copy 导入与 blob），全量测试通过。
