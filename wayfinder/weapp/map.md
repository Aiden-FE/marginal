---
labels: [wayfinder:map]
title: 微信小程序版移动端 v1 规格
---

# 微信小程序版移动端 v1 规格

## Destination

一份可直接交给实现会话执行的微信小程序版规格书（`docs/SPEC-WEAPP.md`）：移动优先的信息架构、视觉体系与触控交互（**重新设计，绝不移植 web/桌面布局**），加小程序端架构（渲染、存储、AI 接入、合规路径）。走完的标志：前沿工单清空、雾区排空、spec 成文，且实现会话可照图开工。

## Notes

- **运作模式**：沿用 v1 地图的无人值守修订——所有 HITL 工单由代理按推荐答案直接定夺并记录，每个 Resolution 列明采纳的推荐项，供用户事后否决；真正影响产品方向且无法合理默认的事项（主体/资质/付费后端等）标记为「需用户定夺」上报。
- 领域词汇见根目录 [CONTEXT.md](../../CONTEXT.md)；处理工单时默认先调 Skill "grilling" + "domain-modeling"（research 调 "research"，prototype 调 "prototype"）。
- 本地 Markdown 追踪器约定（沿用 v1）：地图在本文件；工单在 `wayfinder/weapp/tickets/NNN-slug.md`，frontmatter 含 `status: open|closed`、`labels`、`assignee`、`blocked-by: [NNN]`；决议以工单内 `## Resolution` 节记录；前沿 = open、blocked-by 全部 closed 且未 assign 的工单。
- **本图硬约束（用户 2026-09-08 明确）**：移动端是高频主场景；UX/视觉/交互必须为小程序量身设计，**绝不能把 web 这套硬塞进移动侧**。

**建图时已锁定的立场**：

- v1 现有资产：TS monorepo（`packages/core` 纯 TS 零平台依赖；`packages/data` 存储驱动；`packages/app` Vite+React web；Tauri 2 桌面壳）。core 的修复流水线/实体卡/插图/锚点/队列/全书包领域逻辑是跨端资产，默认最大程度复用。
- 小程序端**重做**：渲染层（无 DOM/无 CSS 多栏分页）、存储驱动（无 sqlite-wasm/OPFS）、UI 层（web 的 React 组件不可用）。
- AI 能力在小程序端**不能假设浏览器式的自由直连**（域名白名单等平台约束），接入形态待 research 钉定。
- 领域语义不变：书稿/章节/修复/修订/修复批次/锚点/供应商/实体卡/正典/定妆照/全书包（见 CONTEXT.md）；移动端改的是交互与载体，不是领域模型。
- v1 的「个人工具、无账号、无云」立场在小程序平台会被部分打破（微信生态有登录/主体/合规的既定要求），冲突处以平台事实为准，并最小化偏离。

## Decisions so far

<!-- 每行一个已关闭工单：[工单名](tickets/xxx.md): 一句话决议 -->

- [小程序渲染模型与样式能力边界](tickets/001-miniprogram-platform-constraints.md): 阅读器不走 CSS 多栏（Skyline 无 columns/grid）；v1 WebView 渲染 + 连续滚动为主，图文混排降级为「段落间插图」（段落索引即锚点）；WASM 未证实、不作依赖。详见 research/weapp/001。
- [小程序本地存储与核心复用边界](tickets/002-storage-and-reuse.md): SQLite 不可移植；存储=wx.setStorage(10MB)+USER_DATA_PATH 文件(与缓存合计200MB)；新增 WeappRepository 驱动（表→目录/行→JSON·NDJSON、扫目录建索引）；core 领域逻辑经 npm 复用，三处要 shim。详见 research/weapp/002。
- [小程序网络与 AI 供应商接入路径](tickets/003-network-ai-access.md): 正式版不能任意直连（https+ICP 白名单）；默认=云函数代理(key 存环境变量)，备选自建中转；体验版勾「不校验域名」可直连。详见 research/weapp/003。
- [小程序合规与上线门槛](tickets/004-compliance-review.md): v1 落地形态=个人主体+工具类目+**体验版自用**（不发布，规避阅读类目/深度合成算法备案两堵墙）；AI 图仍接内容安全检测控号。详见 research/weapp/004。
- [小程序端技术栈与工程边界](tickets/009-weapp-tech-stack.md): Taro(React+TS)编译微信小程序；`packages/weapp` 复用 `packages/core` 但不复用 `packages/app` UI；原生 WXML/WXSS 否决；自绘视觉组件不复用 UI 库。详见 research/weapp/009。

## Not yet specified

<!-- 雾区：随前沿推进逐步成票；2026-09-08 首轮排图后 -->

- 「需用户定夺」硬分叉（来自 003/004）：①是否接受云开发（按量付费）作默认 AI 代理；②v1 是否坚持仅体验版自用、暂不正式上架；③若上架是否走第三方已备案模型+协议路径。——这些在 spec 汇编(012)前必须由用户确认，否则 spec 按「体验版自用+云函数代理」缺省值成文。
- 微信生态集成细节（分享卡片、胶囊按钮避让、onShareAppMessage、阅读进度的轻同步）——待 008 数据同步定形后毕业。
- 冷启动与包体预算的具体数字（core+Taro runtime+自绘组件的主包占用实测）——待 009 落地首个骨架工程后可测。

- 视觉体系细节（字体/字号阶梯、配色、WeUI vs 自定义组件、深浅色双主题）——待信息架构与阅读器交互定形后毕业。
- 分包（subpackage）拆法与主包 2MB 预算分配——待复用边界与页面清单明确。
- 冷启动与长章节渲染性能预算（虚拟列表/按需注入章节文本）——待阅读器交互模型定形。
- 微信生态集成（分享卡片、胶囊按钮、阅读进度在微信内的轻同步）——待数据与同步方案定形。
- 上线节奏（体验版→审核→发布的验收清单）——待合规门槛钉定。

## Out of scope

- iOS/Android 原生 app（Tauri 2 mobile 壳）实施：本图目的地是小程序；原生壳若重启是另一张图。
- 桌面端/web 端 v1 行为变更：现有端保持现状（bug 修复除外），小程序是新增长不回改。
- EPUB 导入/导出（沿 v1 立场）。
- 多租户/团队协作/商业化（付费、会员）：个人工具定位不变。
- 字段级云同步与自动合并：v1 全书包「覆盖或副本」语义沿用，小程序端同步形态由数据工单钉定，但不做自动字段合并。
