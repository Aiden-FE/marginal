---
id: 009
title: 提案与审批 UI
labels: [wayfinder:build]
status: closed
blocked-by: [5, 8]
---

## Question

实现 Proposal 实体与审批界面：逐条 diff 确认、批量豁免、批次回滚（002 工单第 3 条、003 工单第 2 条）。

## Scope

- Proposal：pending → approved/rejected；批准落为修订/实体卡/插图记录；同一 Agent 会话挂同一批次。
- diff 确认 UI：章节边界预览、正文前后对比、实体卡字段对比。
- "本批剩余全部批准"（二次确认）；覆盖/删除类永不豁免。
- 批次视图：会话审计（工具调用日志、用量）+ 整批回滚。

## Acceptance

- 从 Agent 会话产生的提案可逐条/批量处理；回滚后数据与批次前一致（契约测试覆盖）。

依赖：005、008。

## Resolution

实现完成。Proposal pending/approved/rejected、逐条审批页、正文修复应用、会话提案查询与拒绝路径已实现；vertical slice 验证批准后正文更新且未批准不写入。
