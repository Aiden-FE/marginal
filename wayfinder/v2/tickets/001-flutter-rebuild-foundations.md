---
id: 001
title: v2 重建基础决策（Flutter 主路线与 Agent Runtime 定位）
labels: [wayfinder:decision]
status: closed
assignee: Aiden
blocked-by: []
---

## Question

放弃现有 TS/React/Tauri 实现的历史包袱，以 Tauri 或 Flutter 重建 H5/iOS/Android 客户端，并具备真正的客户端 Agent Runtime（不依赖 Pi，使用用户配置的供应商）。技术路线与产品边界如何定？

## Resolution

grilling 第一轮（2026-09-11），用户逐题采纳推荐：

1. **首批平台**：H5、iOS、Android；桌面端保留为未来 Flutter Desktop 构建目标，不进第一阶段验收。
2. **技术路线**：Flutter 主路线；Tauri 不再评估——其核心收益（WebView 复用）已被"放弃历史包袱"的前提消解。**推翻 v1 图 [001](../../tickets/001-cross-platform-stack.md) 的 TS+Tauri 选型。**
3. **Agent 定义**：领域受限 Agent（查询书稿、读取章节、提案修改，经确认写入）；架构允许未来用户扩展工具；不做通用/非 coding agent；第一阶段工具只围绕书稿。
4. **模型调用位置**：客户端直连用户配置的供应商；Provider Transport 与 Agent Runtime 强制分离；预留可选 Gateway 模式（应对 CORS、审计、隐藏密钥）。凭据：移动端用系统安全存储，H5 明示浏览器存储风险。
5. **写操作策略**：一律"提案 → 用户确认 → 提交"；只读工具自动执行；高风险操作禁止静默批量。
6. **Provider 抽象**：多协议接口（type/endpoint/credential reference/model/capabilities/request limits），首个适配器 OpenAI-compatible。
7. **工具调用协议**：原生 tool_calls 与结构化 JSON action 双协议支持，内部统一为 Agent 事件模型。
8. **离线**：阅读器与书库离线可用；Agent 首版在线，不内置本地大模型。
9. **输入范围**：TXT + EPUB 纳入领域模型（BookSource → Work），TXT 先跑通全链路，EPUB 分阶段。
10. **验收链路**：vertical slice = 导入 TXT → 本地书稿 → 长文阅读 → Agent 查询章节 → 生成修复/结构提案 → 用户确认 → 写入修订 → 断网重开可读。

状态：open——第二轮（领域模型、提案实体、工具权限、存储、阅读器形态、迁移、仓库策略、预算审计）进行中。
