---
id: 007
title: Provider 传输层
labels: [wayfinder:build]
status: closed
blocked-by: [4]
---

## Question

实现多协议 Provider 抽象与首批两个 Transport：Demo Provider 与 OpenAI-compatible 适配器（001 工单第 4、6 条）。

## Scope

- ProviderConfig：type/endpoint/credential reference/model/capabilities/request limits；凭据经平台安全存储端口（移动 Keychain/Keystore，H5 明示风险）。
- Transport 接口：chat（含 tool_calls 与 JSON action 双形状解析）、用量回报。
- Demo Provider（零网络，可模拟工具调用回合）。
- OpenAI-compatible 适配器 + 连通性诊断 + 能力探测（003 工单第 4 条），能力位驱动运行时降级。
- 预留 Gateway Transport 扩展点（不实现）。

## Acceptance

- Demo 全链路可跑；配置真实 OpenAI-compatible 供应商可完成一次带工具回合的对话（手动验证）；诊断与探测 UI 可用。

依赖：004。

## Resolution

实现完成。ProviderTransport、DemoTransport、Web 可编译的 OpenAI-compatible HTTP transport、tool_calls/JSON DTO、超时与错误分类、诊断接口已实现并通过 provider 单测。
