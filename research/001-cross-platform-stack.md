---
ticket: 001
title: 跨端技术选型评估
date: 2026-09-06
assignee: Aiden
---

# 跨端技术选型评估（research/001）

## 0. 结论速览

**推荐路线：TypeScript 单体仓库「web 核心 = 第一公民」+ Tauri 2 作桌面壳；备选 Electron（若需要 Node 生态或多窗口/打印等桌面能力）；不推荐 Flutter 与 React Native/Expo 作为主路线。**

一句话理由：本项目最大的技术风险点是「自研分页引擎 + 图文混排（段落锚点插图）」。排版这件事在 DOM/CSS 里有一套现成的、被验证过的工程路径（CSS 多栏分页，foliate-js / Epub.js 均为成熟先例），而在 Flutter（Skia/CanvasKit 自绘）和 RN（非 DOM 约束）里都要走 TextPainter/自绘的困难路径，且无法与 web 端共享实现。因此**阅读器必须活在 DOM 里**，反推核心逻辑层必须是 TypeScript，桌面壳选 Tauri 2 或 Electron。

## 1. 候选逐项评估

### 1.1 Tauri 2（桌面壳）+ 共享 web 核心 —— 推荐主线

- **架构**：前端是纯静态 web 资产，跑在系统 WebView（macOS WKWebView / Windows WebView2 / Linux WebKitGTK）中，Rust 仅作后端/命令层；2.0 起稳定支持 iOS/Android（[Tauri 2.0 stable 发布公告](https://v2.tauri.app/blog/tauri-20/)）。
- **标准 1（桌面全功能）**：✅。文件系统经 Rust 侧访问（`tauri-plugin-fs` / 自写 command），长任务放 Rust 或前端 Web Worker，SQLite 有官方 `tauri-plugin-sql`（基于 sqlx，支持 SQLite/MySQL/Postgres，覆盖 Windows/macOS/Linux/iOS/Android，不含 web）（[SQL plugin 文档](https://v2.tauri.app/plugin/sql/)）。
- **标准 2（web 全功能 + 共享核心）**：✅ 且是本路线天然形态。Tauri 前端本来就是标准 Vite/React 应用，去掉 `@tauri-apps/api` 依赖直接部署即为 web 端；web 端的文件导入用 `<input type=file>`（全浏览器）或 File System Access API（Chromium）（[MDN: File System API](https://developer.mozilla.org/en-US/docs/Web/API/File_System_API)），SQLite 用官方 sqlite-wasm + OPFS（见 §3）。
- **标准 3（分页引擎）**：✅ 最优。分页器直接活在 DOM/CSS 中，桌面与 web 渲染容器同为浏览器内核（唯一注意：Linux WebKitGTK 与 Chromium 有差异，个人工具可不管 Linux）。
- **标准 4（移动复用）**：✅ 唯一能"一条路线到底"的候选——Tauri 2 的 iOS/Android 目标复用同一个前端 + 同一套插件接口；移动端只读，恰好避开 Tauri mobile 尚年轻的重功能场景（mobile 支持自 2022 alpha、2024 稳定，社区对 iOS 成熟度仍有保留，[GitHub discussion #10197](https://github.com/orgs/tauri-apps/discussions/10197)）。
- **标准 5（本地优先数据）**：✅ 桌面真 SQLite（sqlx），web SQLite-wasm/OPFS，同一套 schema+migration 双端跑（见 §3）。
- **代价/风险**：每端 WebView 内核不同（Safari/WebView2/WebKitGTK），CSS 分页引擎要在这三个内核上都测；浏览器内 AI 调用受 CORS 制约（见 §4 风险）。

### 1.2 Electron —— 强备选

- **架构**：Chromium + Node 主进程（[进程模型](https://www.electronjs.org/docs/latest/process-model/)），渲染进程就是 web 代码。
- **标准 1**：✅ 且最强：Node 全量生态（better-sqlite3、chokidar、sharp 等），无需经 Rust 桥。**标准 2**：✅ 渲染层与 web 端共享，但 Node IPC/原生模块需要在 web 端用 shim 替换（比 Tauri 的 command 层多一层适配噪声）。**标准 3**：✅ 与 Tauri 等同，且渲染内核统一为 Chromium（分页引擎只需对一种内核负责）。**标准 4**：❌ 无移动路径，未来移动端必须另起炉灶（RN 或 Capacitor 包 web）。**标准 5**：✅ better-sqlite3 成熟。
- **何时选它**：如果后面发现 AI 流水线需要大量 Node 生态库（PDF、字体子集化、图像处理 sharp）或者你觉得 Tauri 的 Rust 侧写 command 心智负担高，Electron 的开发摩擦更小；代价是包体（~100MB vs Tauri ~10MB 级）与放弃移动复用。

### 1.3 React Native/Expo（+ react-native-web）—— 不推荐为主线

- react-native-web 是把 RN 组件渲染成语义 HTML，成熟且被 Expo 采用（[react-native-web](https://necolas.github.io/react-native-web/)），核心 TS 逻辑也确实可共享。
- 但两个硬伤：① **分页引擎无法共享**——web 端可用 CSS 多栏分页，RN 端没有多栏分栏能力，得用 TextPainter 式的逐段二分测量重写一遍，等于自研分页引擎做两遍；② **web 端 SQLite 是"实验性"**——`expo-sqlite` web 支持需要 Metro 配 wasm 资产、COOP/COEP 头（SharedArrayBuffer），社区仍有建库失败等未清 issue（[Expo SQLite 文档](https://docs.expo.dev/versions/latest/sdk/sqlite/)、[issue #39903](https://github.com/expo/expo/issues/39903)）。桌面端 RN-windows/macOS 也远不如前两者成熟。它只在"移动端成为主战场"时才值得。

### 1.4 Flutter —— 不推荐

- Dart 核心与 TS 生态割裂：AI 流水线（OpenAI-compatible、SSE 流式、JSON schema 工具链）在 TS 里最顺；未来若要做网页嵌组件/DOM 混排也无路可走。
- **web 端是 CanvasKit 自绘**，没有 DOM：文本布局走 Skia paragraph，官方明确 web 缺乏直接文本排版引擎（[Going deeper with Flutter's web support](https://flutter.dev/blog/going-deeper-with-flutters-web-support)）；自绘文本有性能敏感、渲染回归、字体加载等已知问题（[flutter#74990](https://github.com/flutter/flutter/issues/74990)、[flutter#123484](https://github.com/flutter/flutter/issues/123484)）。自研分页引擎要在 Dart 侧用 TextPainter + 二分实现，长文档布局成本高（TextPainter.layout 占帧时间 16–35% 的社区实测，需只排可见页并缓存）。图文混排、文本选择、无障碍都要自己补。**标准 2/3 双双最差**，虽然标准 4（移动）和标准 1（桌面，drift+sqlite）不错，但与本项目重心南辕北辙。

### 1.5 组合建议（提出的"更优组合"）

不引入新框架，而是**把 Tauri 与 Electron 共同化**：核心包（领域模型、AI provider 抽象、分页引擎、repository 接口）不 import 任何平台 API；Tauri/Electron/web 三端的差异全部收进 adapter 层。这样桌面壳从 Tauri 换 Electron（或反之）只是换 adapter，不伤核心。见 §5 边界划分。

## 2. 五项硬性标准对照表

| 标准 | Tauri 2 + web 核心 | Electron | Expo/RN+Web | Flutter |
| --- | --- | --- | --- | --- |
| 1 桌面全功能 | ✅（Rust fs/命令、plugin-sql） | ✅✅（Node 生态最全） | ⚠️ RN-windows/macOS 弱 | ✅（drift/sqlite） |
| 2 web 全功能+共享核心 | ✅ 天然（前端即 web 应用） | ✅（需 Node→shim） | ⚠️ RN-web 可，但 sqlite web 实验性 | ❌ CanvasKit 自绘，无 DOM |
| 3 自研分页+图文混排 | ✅ CSS 多栏分页，先例充分 | ✅ 同左（单内核更稳） | ❌ 需另写 RN 版分页器 | ❌ TextPainter 自绘，成本最高 |
| 4 移动端复用路径 | ✅ Tauri 2 iOS/Android（年轻但可用） | ❌ 无 | ✅ RN 原生最强 | ✅ 移动最强 |
| 5 本地优先可同步数据 | ✅ sqlx ↔ sqlite-wasm 同 schema | ✅ better-sqlite3 | ⚠️ expo-sqlite web 生态尚浅 | ✅ drift（web 走 wasm） |

## 3. 数据模型落地（标准 5 细化）

**策略：SQLite everywhere，同一份 schema + migration 双端跑。**

- **桌面**：`tauri-plugin-sql`（sqlx）或自写 Rust command；Electron 则 better-sqlite3。
- **web**：官方 SQLite WASM。推荐 **opfs-sahpool VFS**：SQLite 3.43+ 内置，无需 COOP/COEP 头，Safari 16.4+ / 全主流浏览器可用，性能是各 OPFS 方案中最好的；代价是单连接（个人工具足够）且库文件导入导出有专门 API（`importDb`/`exportDb`，恰好和"全书包"导出/导入天然契合）（[SQLite WASM persistence 文档](https://sqlite.org/wasm/doc/trunk/persistence.md)、[Chrome 官方博客](https://developer.chrome.com/blog/sqlite-wasm-in-the-browser-backed-by-the-origin-private-file-system)）。注意 OPFS 仅在 Worker 中可用，数据层本来就该在 Worker 里跑（不阻塞 UI），顺理成章。
- **同步 v1**：按 map 已锁定立场，双端流动 = 全书包手动导出/导入。数据库级 `exportDb/importDb`（web 侧）+ 桌面侧直接打包 SQLite 文件/JSON，成本低。
- **未来演进位**：若"模型须可同步"升级为自动同步/多端合并，可引入 [cr-sqlite](https://github.com/vlcn-io/cr-sqlite)（把表升级为 CRR，经 `crsql_changes` 虚拟表做 changeset 合并，浏览器 WASM 与原生 SQLite 均可用；写放大约 2.5x）。v1 不建议上，但 schema 设计时避免依赖"单写者、不可合并"的假设（主键稳定、不用自增行号做身份、变更可追加）即可留好口子。

## 4. 浏览器内 AI 任务（与工单 002 的接口）

供应商是用户自配的 OpenAI-compatible 端点，双端同一 provider 抽象（fetch + SSE 解析器放核心包）。**风险：浏览器内跨域 fetch 受 CORS 约束**——桌面端可经 Rust/Node 侧转发绕开，web 端只能依赖供应商放行 CORS 或用户走中转。这不阻塞选型，但 web 端 UI 需要把"该供应商在浏览器不可直连"做成可诊断错误。此项与工单 002 的结论互为输入。

## 5. "共享核心"的边界

一个 monorepo（pnpm workspaces），自上而下：

| 层 | 内容 | 共享范围 |
| --- | --- | --- |
| `core/`（纯 TS，零平台依赖） | 领域模型（Work/Chapter/Revision/Anchor/EntityCard）、修复流水线编排、provider 抽象与 OpenAI-compatible 客户端、分页/锚点算法的纯逻辑部分（文本测量结果 → 页切分决策）、repository 接口 + SQL schema/migrations、全书包序列化 | 桌面 + web + 未来移动，100% 共享 |
| `data-sqlite/` | SQLite driver adapter：桌面走 tauri-plugin-sql / better-sqlite3，web 走 sqlite-wasm(OPFS-sahpool) in Worker | 接口共享，实现按端 |
| `ui/reader`（React + DOM/CSS） | 阅读器、分页渲染器（CSS 多栏 + Range 锚点）、实体卡/插图面板 | 桌面 + web 100% 共享；移动复用（Tauri 2 mobile 同为 WebView） |
| 平台壳（每端独有） | Tauri：Rust commands（文件读写、长任务守护）、打包/签名、菜单/托盘；web：无壳，部署静态站 + Worker；未来 mobile：Tauri iOS/Android 壳 | 不共享 |

**锚点实现提示**：插图锚点定义为「段落内文本偏移」（跨重排存活），渲染层把它翻成 DOM Range 插入 inline 图；分页器重排后按偏移重建。这是 core（偏移/数据）与 ui（Range/DOM）的正确切分线，也保证移动端只读复用时锚点逻辑零改动。

**分页引擎先例**：DOM 方案直接对标 [foliate-js](https://github.com/johnfactotum/foliate-js)（MIT，纯 JS，paginator 用 CSS 多栏 + 二分定位可见 Range，兼支持滚动/分页双模式；Foliate 桌面阅读器在用）与 Epub.js；已知 CSS 多栏的性能/样式边角问题两者文档均已记录，个人工具规模（单本 TXT）可控。自研仍建议自研（需段落锚点插图与自有实体卡 UI），但算法路径照此先例走，不做盲飞。

## 6. 决议

- **主线**：TypeScript monorepo，`core`（领域模型 + AI 流水线 + 分页核心 + schema）零平台依赖；web 端 = Vite 静态站（sqlite-wasm/OPFS + Worker）；桌面端 = Tauri 2 壳复用同一前端（tauri-plugin-sql + Rust fs）；未来移动端 = Tauri 2 iOS/Android 只读复用。
- **备选**：Electron，在需要 Node 生态或想统一渲染内核为 Chromium 时切换，核心包不受影响（只换 adapter）。
- **否决**：Flutter（分页/图文混排在自绘 web 上成本最高、Dart 割裂 TS 生态）、RN/Expo（分页器要写两遍、web SQLite 实验性；除非移动端升为主战场再重启评估）。

## 来源

- [Tauri 2.0 Stable Release（含 iOS/Android）](https://v2.tauri.app/blog/tauri-20/)
- [Tauri SQL plugin（sqlx，桌面+移动）](https://v2.tauri.app/plugin/sql/)
- [Tauri mobile iOS 成熟度社区讨论 #10197](https://github.com/orgs/tauri-apps/discussions/10197)
- [Electron 进程模型](https://www.electronjs.org/docs/latest/process-model/)
- [SQLite WASM 持久化（opfs-sahpool、COOP/COEP、Safari 支持）](https://sqlite.org/wasm/doc/trunk/persistence.md)
- [Chrome 博客：SQLite Wasm backed by OPFS](https://developer.chrome.com/blog/sqlite-wasm-in-the-browser-backed-by-the-origin-private-file-system)
- [MDN: File System API（浏览器兼容与降级）](https://developer.mozilla.org/en-US/docs/Web/API/File_System_API)
- [Expo SQLite 文档（web 需 wasm/COOP-COEP）](https://docs.expo.dev/versions/latest/sdk/sqlite/)、[expo#39903 web 建库问题](https://github.com/expo/expo/issues/39903)
- [react-native-web](https://necolas.github.io/react-native-web/)
- [Flutter 官方博客：web 文本排版引擎缺失](https://flutter.dev/blog/going-deeper-with-flutters-web-support)、[flutter#123484 CanvasKit 排版性能回归](https://github.com/flutter/flutter/issues/123484)、[flutter#74990 CanvasKit 文本不渲染](https://github.com/flutter/flutter/issues/74990)
- [foliate-js（CSS 多栏分页先例，MIT）](https://github.com/johnfactotum/foliate-js)
- [cr-sqlite（CRDT SQLite 同步，未来演进位）](https://github.com/vlcn-io/cr-sqlite)
