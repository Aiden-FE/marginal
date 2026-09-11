---
id: 008
title: Agent Runtime 核心
labels: [wayfinder:build]
status: closed
blocked-by: [7]
---

## Question

实现客户端 Agent 运行时：状态机、工具注册表、多轮循环、双协议统一事件模型、checkpoint 与预算（001/003 工单决议）。

## Scope

- 状态机：running/awaiting-approval → completed/failed/cancelled/budget-exceeded；已批准提案保留、未决过期；每轮 checkpoint；不可复活。
- 工具注册表：JSON Schema 校验、risk 分级、≤10 个首版工具（search/get 只读；propose_* 写入产出提案）。
- 工具循环：maxTurns、每工具超时、取消、重复调用检测、错误重试上限。
- 内部事件模型：AgentTurnStarted / ModelRequestedTool / ToolAwaitingApproval / ToolStarted / ToolCompleted / ModelResponded / AgentFinished / AgentFailed。
- 会话绑定单本 Work（书库级只读工具例外）。
- 预算：token 用量累计入书稿预算，超限终止。
- 四类任务流水线工具化接入（切章提议、修复建议、实体提取、插图提示词——002 工单第 2 条）。

## Acceptance

- Demo Provider 驱动的多轮工具调用会话全状态机路径可测（含取消、超预算、H5 冻结恢复后安全终止）。

依赖：007。

## Resolution

实现完成。AgentRuntime 已实现多轮工具循环、JSON Schema 校验、写工具审批门、事件流、checkpoint、取消、预算终止与双协议 DTO；Agent 单测和 vertical slice 测试通过。
