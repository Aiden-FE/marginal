---
id: 001
title: 小程序渲染模型与样式能力边界
labels: [wayfinder:research]
status: closed
assignee: Aiden
blocked-by: []
---

## Question

微信小程序「非 DOM、非完整 WebView」的渲染模型决定了移动端能/不能用什么。要钉死的事实层：

1. 渲染模型：小程序的 WXML/WXSS 与 DOM/CSS、以及 Skyline/WebView 两种 renderer 的关系；节点渲染、样式系统（层叠/flex/grid/自定义属性/媒体查询）能力边界。
2. **分页排版**：CSS 多栏（column-count）在 WXSS 里是否可用；小程序里实现「仿真阅读器分页/图文混排」的可行路径（scroll-view 分页？rich-text？measureText + 手动分页？Skyline 组件？）。这直接决定移动阅读器是「分页仿真」还是「连续滚动」。
3. 文本测量与排版：如何量文本（`measureText` / canvas）、换行、中文标点挤压、图片 inline 混排能力。
4. 运行时能力：WASM 可用性（决定 sqlite-wasm 是否可移植）、Worker、文件系统 API、`wx.request` 流式（chunked）支持。
5. 尺寸与物理限制：主包/分包体积上限、单页渲染性能、safe-area 与 iPhone 刘海/灵动岛适配机制。

产出：小程序渲染与样式能力清单，去掉「web 假设」，圈出移动阅读器的可行实现区间。

## Resolution

（无人值守模式：以下为推荐事实与建议，已采纳，可事后否决；见 research/weapp/001）

- **渲染器**：v1 用 WebView 渲染器起步；性能热点页再评估 Skyline。Skyline 明确不支持 columns/grid（display 仅 none/flex/block），WebView 只承诺「CSS 大部分特性」——**web 的 CSS 多栏分页方案不可移植**。
- **阅读器形态**：按「连续滚动 + 按需注入」为主设计；分页仿真仅作可选增强（swiper + canvas measureText 预分页），其定稿落在 weapp/006。
- 文本测量：canvas 2d measureText；图文混排降级为「段落间插图」（段落索引即锚点），弃用 web 端字符偏移锚点。
- WASM：官方专页未检索到（多 URL 404），支持未证实；即便可用也无 OPFS，sqlite-wasm 不作依赖。
- 流式：wx.request 存在 RequestTask.onChunkReceived（分块接收），具体版本 prototype 实测。
- 样式/适配：flex 布局、vh/vw/calc、env(safe-area-inset-*)、CSS variables（高版本）可用；滚动一律 scroll-view；@font-face 仅 ttf；media query 仅 DarkMode。
- 包体：主包 ≤2MB、全分包合计 ≤30MB、tabBar 必须在主包。将写入此节；采纳的推荐项逐一列明。