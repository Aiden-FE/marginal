---
labels: [wayfinder:map]
title: Marginal v2 重建：Flutter H5/iOS/Android + 客户端 Agent Runtime
---

# Marginal v2 重建

## Destination

放弃现有 TS/React/Tauri 实现的历史包袱，以 Flutter 重建 H5、iOS、Android 客户端，并内置真正的客户端 Agent Runtime（不依赖 Pi，使用用户配置的供应商）。走完标志：grilling 完成全部决策轮次、领域词汇与决策成文、形成可直接执行的实现工单。

## Notes

- 启动于 2026-09-11，源自用户指令：放弃历史包袱、在 Tauri 与 Flutter 中重新选择、实现真正 Agent runtime。
- 第一轮 grill 已由用户采纳所有推荐；决议记录在 [tickets/001-flutter-rebuild-foundations.md](tickets/001-flutter-rebuild-foundations.md)。
- 术语见根目录 [CONTEXT.md](../../CONTEXT.md)；本图的后续工单沿用 `tickets/NNN-*.md`。
- 前身决策：[../map.md](../map.md) 的 v1 图选择 TS+Tauri 并否决 Flutter；本图推翻该路线，原因是历史实现不再是约束。

## Decisions so far

- [v2 重建基础决策](tickets/001-flutter-rebuild-foundations.md)：Flutter 主路线；首批 H5/iOS/Android；领域受限 Agent；客户端直连供应商并预留 Gateway；写操作必须确认；多协议 Provider 抽象、OpenAI-compatible 首适配器；tool_calls + JSON action；阅读/书库离线而 Agent 在线；TXT+EPUB；vertical slice 验收。
- [v2 领域延续与运行时语义](tickets/002-domain-runtime-semantics.md)：沿用 v1 领域语言；流水线工具化而非让 Agent 重发明；Proposal 统一写入确认；Agent Run 绑定单本书稿；Dart 数据层跨三端共享语义；竖滚默认、分页后置；.mabk 迁移；新目录并存至 slice 通过；预算与工具审计；Flutter Web 直接替换旧 H5。
- [v2 Agent 运行时细节与实现拆分](tickets/003-agent-runtime-details.md)：状态机不可复活、每轮 checkpoint、已批准提案保留；写入逐条 diff 确认并限制批量豁免；JSON Schema 工具治理；Provider 手动声明+能力探测降级；保留 Demo Provider；首版不要求 SSE；实现拆为 004–011。

## Implementation frontier

- [004 Flutter 工程骨架](tickets/004-flutter-skeleton.md) → [005 数据层](tickets/005-dart-data-layer.md) → [006 阅读器](tickets/006-reader-scroll.md)
- [004 Flutter 工程骨架](tickets/004-flutter-skeleton.md) → [007 Provider](tickets/007-provider-layer.md) → [008 Agent Runtime](tickets/008-agent-runtime.md)
- [005 数据层](tickets/005-dart-data-layer.md) + [008 Agent Runtime](tickets/008-agent-runtime.md) → [009 提案审批](tickets/009-proposal-approval.md)
- [005 数据层](tickets/005-dart-data-layer.md) → [010 .mabk 迁移](tickets/010-mabk-migration.md)
- [006 阅读器](tickets/006-reader-scroll.md) + [009 提案审批](tickets/009-proposal-approval.md) + [010 .mabk 迁移](tickets/010-mabk-migration.md) → [011 Vertical slice](tickets/011-vertical-slice-acceptance.md)

所有设计 frontier 已清空；当前 frontier 是可实施工单 004。

## Out of scope for first delivery

- Flutter Desktop 交付
- 微信小程序
- Pi agent 内置
- 本地大模型与离线 Agent
- 通用 coding agent、任意 shell、任意文件系统工具
