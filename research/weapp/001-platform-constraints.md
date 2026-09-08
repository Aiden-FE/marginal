---
ticket: weapp/001
title: 小程序渲染模型与样式能力边界
date: 2026-09-08
assignee: Aiden
---

# 渲染与样式能力（research/weapp/001）

## 0. 结论速览

**阅读器不能走「CSS 多栏分页」路线：Skyline 明确不支持 columns/grid（display 仅 none/flex/block）；WebView 渲染器文档只承诺「CSS 大部分特性」、未列多栏，且三端（iOS WKWebView/Android chromium/开发者工具）差异不可控。移动端阅读器应按「连续滚动 + 按需注入」为主形态设计，分页仿真为可选增强（swiper + canvas measureText 预分页），由 prototype 工单（weapp/006）定稿。**

## 1. 渲染模型

- 双线程：AppService（逻辑层，JSCore/V8）+ 渲染层（WebView 或 Skyline）；无 DOM API，逻辑层不可操作节点（来源：Skyline 介绍页，架构描述）。
- Skyline：独立渲染线程接管 Layout/Composite/Paint，更接近原生；适合长列表滚动。既有 WebView 代码可平迁，但 WXSS 有额外限制。
- 结论：v1 小程序端默认 WebView 渲染器起步（兼容面最大），性能热点页（书架/章节列表）再评估 Skyline。

## 2. 样式能力（关键差异，来源：Skyline WXSS 差异页）

| 能力 | Skyline | 备注 |
| --- | --- | --- |
| columns/column-count | ❌ 未列出（不支持） | **web 分页方案不可移植** |
| grid | ❌ display 仅 none/flex/block | 布局用 flex |
| flex | ✅ 完整 | 默认 flex-direction: column |
| position | ✅ relative/absolute/fixed（fixed 需 8.0.43+，仅相对 viewport） | sticky ❌（用 sticky-header 组件） |
| CSS variables | ✅（安卓 8.0.35+/iOS 8.0.38+） | 主题系统可用 |
| vh/vw、calc、rpx | ✅ | 官方现推荐 vw 优先 |
| env(safe-area-inset-*) | ✅（仅该系列） | 刘海/底部安全区可适配 |
| overflow: scroll | ❌ | 滚动一律用 scroll-view |
| @font-face | 仅 ttf | 内嵌字体要转 ttf 且算包体 |
| Media query | 仅 DarkMode | 深浅色可用 |

- WebView 渲染器：WXSS「具有 CSS 大部分特性」，选择器个别例外（属性选择器、带参伪类）；未承诺多栏——不可作为依赖。

## 3. 文本测量与图文混排

- 测量：canvas 2d `measureText`（按宽度逐字/逐词累积断行）是官方可行路径；rich-text 组件可渲染节点树（含 img），但无法从内部拿到精确布局位置。
- inline 图混排：靠 rich-text + 自定义节点，或段落级拆分渲染；「锚点插图」建议降级为**段落间插图**（段落索引即锚点，弃用字符偏移），交互上更符合移动阅读。
- WASM：官方文档站内未检索到 WebAssembly 专页（多 URL 404），支持情况**未证实**；即使可用也无 OPFS，sqlite-wasm 不可行——不作为依赖（见 weapp/002）。

## 4. 运行时与网络原语

- `wx.request`：存在 `RequestTask.onChunkReceived`（分块接收，流式可用；版本号待 prototype 实测核对）。
- Worker：小程序支持 Worker（受限），长任务可后置。
- 网络：仅 https/wss + 已配置的合法域名（需 ICP 备案），不可 IP/localhost（局域网 IP 除外，基础库 2.4.0+）；开发者工具可勾选「不校验域名」调试（详见 weapp/003）。

## 5. 包体与设备适配

- 主包 ≤ 2MB；全小程序所有分包合计 ≤ 30MB（服务商代开发 20MB）；tabBar 页面必须在主包。
- safe-area：`env(safe-area-inset-*)` 可用；胶囊按钮（右上角）区域需避让。
- rpx 取整精度问题：官方建议优先 vw。

## 来源（访问于 2026-09-08）

- WXSS：https://developers.weixin.qq.com/miniprogram/dev/framework/view/wxss.html
- Skyline 介绍：https://developers.weixin.qq.com/miniprogram/dev/framework/runtime/skyline/introduction.html
- Skyline WXSS 差异：https://developers.weixin.qq.com/miniprogram/dev/framework/runtime/skyline/wxss.html
- 分包上限：https://developers.weixin.qq.com/miniprogram/dev/framework/subpackages.html
- 网络域名：https://developers.weixin.qq.com/miniprogram/dev/framework/ability/network.html
- WASM：官方专页未检索到（wasm.html / webassembly.html 均 404）→ 标记未证实
