---
id: 003
title: v2 Agent 运行时细节与实现拆分
labels: [wayfinder:decision]
status: closed
assignee: Aiden
blocked-by: [2]
---

## Question

Agent 会话状态机、确认 UI 粒度、工具治理、供应商能力探测、流式输出与 vertical slice 实现拆分如何定？

## Resolution

grilling 第三轮（2026-09-11），用户逐题采纳推荐：

1. **状态机**：running/awaiting-approval → completed/failed/cancelled/budget-exceeded。取消、失败、超预算时已批准提案保留生效，未决提案过期丢弃；每轮工具调用后 checkpoint 落库（H5 冻结可安全恢复）；会话不可复活续跑——恢复语义 = 查看历史 + 基于历史新起会话。
2. **确认粒度**：逐条 diff 确认为主（章节边界预览、正文前后对比、实体卡字段）；同类型连续提案提供"本批剩余全部批准"（二次确认）；覆盖正文与删除类提案永不享受批量豁免。
3. **工具治理**：JSON Schema 声明输入并强制校验；注册表为唯一工具来源，未注册名称拒绝；risk: read|write 标注；工具名与 schema 版本写入工具调用记录；校验失败报错给模型重试、不入审计；首版工具 ≤10 个。
4. **能力探测**：手动声明 + 一键探测混合；默认保守能力（JSON action 模式）即可工作；探测结果写回配置，失败不阻塞，运行时按能力位自动降级。
5. **Demo Provider**：保留；作为第一个 Transport 实现验证抽象正确性，服务 e2e 与零配置体验。
6. **流式输出**：首版不要求 SSE 流式；工具调用事件流即进度反馈；列为 v2.x 增强。
7. **实现拆分**：八个实现工单 004–011（编号较轮次草图整体 +1，依赖结构不变）；阅读器与 Agent 双泳道并行；011 为唯一验收关，通过后触发旧实现删除与 H5 替换（002 工单第 8、10 条）。

frontier 清空，grilling 结束；实现 frontier 已转入 004–011，等待用户对共识摘要的最终确认后进入实现。
