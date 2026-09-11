---
id: 002
title: v2 领域延续与运行时语义
labels: [wayfinder:decision]
status: closed
assignee: Aiden
blocked-by: [1]
---

## Question

v2 的领域对象是否延续 v1 术语与语义？Agent 运行时实体（会话、工具调用、提案）如何建模？存储、阅读器、迁移、仓库与发布策略如何定？

## Resolution

grilling 第二轮（2026-09-11），用户逐题采纳推荐：

1. **领域语言延续**：沿用 v1 全部术语与语义（书稿、章节、修订、修复批次、锚点、实体卡、正典、定妆照、全书包）；放弃的是技术实现，不是领域模型。新增实体：Agent 会话、工具调用记录、提案。
2. **流水线与 Agent 关系**：四类任务类型保留为确定性流水线并工具化，Agent 负责编排与多轮交互；不让模型在自由循环里重新发明切章/修复算法。
3. **提案（Proposal）**：所有写操作统一为 Proposal 实体（pending → approved/rejected）；批准后落地为修订/实体卡/插图记录；同一 Agent 会话的全部已批准变更挂同一批次号，整批回滚沿用修复批次语义。
4. **Agent 作用域**：会话绑定单本书稿；书库级只读工具（跨书搜索）允许，跨书写操作禁止。
5. **存储架构**：一套 Dart 数据层为单一事实来源（schema/迁移/Repository 语义三端共享）；原生 SQLite、H5 浏览器持久化；契约测试锁引擎差异；具体库由实现 spike 决定。沿用 v1 已验证结论：供应商 CORS 差异大需诊断、H5 后台冻结需 checkpoint 断点续跑。
6. **阅读器形态**：默认竖向滚动；横向分页后置为 v2.x 模式；锚点图文混排语义两种形态通用。推翻 v1"分页引擎优先"立场（该立场由 DOM/CSS 多栏低成本倒逼，Flutter 下成本结构不同）。
7. **旧数据迁移**：仅走 .mabk 导出/导入；不做 IndexedDB/SQLite 直连迁移。
8. **仓库策略**：Flutter 应用放同仓库新目录（apps/marginal/）；旧 packages/ 与 src-tauri/ 保留至 vertical slice 通过后删除归档。
9. **预算与审计**：Agent 会话必须记录 token 用量与完整工具调用日志（输入摘要、结果摘要、批准/拒绝），计入书稿级预算上限；沿用队列可取消、断点续跑语义。
10. **H5 发布切换**：vertical slice 通过后 Flutter Web 构建直接替换 Vercel 现有 React H5，不长期并行；迁移期说明旧浏览器数据不自动迁移。
