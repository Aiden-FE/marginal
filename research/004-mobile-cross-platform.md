---
title: 移动端跨端方案研究与 Marginal 建议
date: 2026-09-11
assignee: Aiden
status: research
---

# 移动端跨端方案研究与 Marginal 建议

> 调研日期：2026-09-11。本文是技术选型研究，不实施迁移，也不替代在目标设备、真实书籍和发布账号上的验证。版本/平台能力以本次查阅到的官方资料为准；没有统一、可比的实测基准时，不给包体、帧率或工期打分。

## 0. 执行摘要

Marginal 的核心约束不是“能不能把页面装进 App”，而是：已有 Web 阅读器和 DOM/CSS 排版是否仍是第一实现、文本偏移锚点和图文混排能否稳定、离线书库/数据库/文件导入分享是否可用，以及在 iOS/Android 商店规则下是否成为有独立价值的应用。

**通用结论**：跨端不是一个维度。应先选择复用范式：

1. **WebView/网页优先**：PWA、Capacitor、Tauri 2 Mobile。HTML/CSS/JS 阅读器可高度复用，原生能力经插件或自定义桥接补齐；UI 的视觉和交互仍主要由 Web 渲染。
2. **原生 UI**：React Native/Expo、Flutter，以及 KMP + 原生 SwiftUI/Android UI（或 KMP + Compose Multiplatform）。它们适合移动原生体验和设备能力，但不能假设现有 DOM 阅读器、CSS 多栏分页、Range 锚点直接复用。
3. **共享逻辑而非共享 UI**：KMP 的强项是共享数据/业务逻辑并保留平台 UI；RN 也可共享 JS 业务逻辑，但其默认 UI 不是 DOM。uni-app/uni-app x、Taro 以多平台/小程序覆盖为重要卖点，必须逐平台核对组件/API；小程序目标、H5、原生 App、鸿蒙不是同一个无条件等价的编译产物。

**对 Marginal 的条件性建议**（结合 §1 代码证据）：

- 若目标是“现有 Web 阅读器尽可能复用 + iOS/Android 可发布”：**Capacitor 与 Tauri 2 Mobile 并列作为第一梯队候选，同场薄切片验证、不预判胜负**。代码证据支持两者低摩擦：`packages/app/src/App.tsx:1-70` 已按 coarse pointer/宽度切出独立 `mobile/*` DOM 页面树；`packages/data` 已有 Web（SQLite WASM/OPFS Worker，失败降级 IndexedDB）与 Tauri（plugin-sql）双驱动（`packages/data/src/open.ts:1-50`、`packages/data/src/tauri-driver.ts:1-47`）；桌面 Tauri 壳仅注册 SQL 插件、无自定义 commands（`src-tauri/src/lib.rs:1-15`），移动化附加负担小。Capacitor 官方定位是把现代 Web 应用放入 iOS/Android 原生 runtime 并以插件访问原生 SDK。[C1]
- 若目标变成“移动端原生阅读体验优先、复杂手势/系统导航/无障碍和滚动表现优先”：评估 **React Native/Expo** 或 Flutter。RN 可直接复用纯 TS `packages/core`（仅依赖 fflate）与业务算法，但 app 层 actions/store 目前直接使用 Web API（DOM 下载、WebShare、canvas、localStorage、visibilitychange），需先抽 ports；`ReaderView.tsx` 的 DOM 多栏分页在 RN 原生组件中不可复用，应明确“嵌 WebView 复用”还是“原生重写”，不要把 `react-native-web` 当作现有 DOM 阅读器的无成本迁移。Flutter 则只能复用协议/规格（`.mabk` 格式、schema、锚点规则），不能声称直接复用 TS 代码。
- **PWA** 是最低摩擦的发布/验证层，适合离线阅读和分享能力可接受、无需深度原生 API 的用户；不能把它当作完整替代商店 App 的承诺。
- **KMP** 适合已有 Kotlin/Swift 原生团队、希望共享同步/数据库/领域逻辑但接受两套 UI 的组织；不是复用现有 React/DOM UI 的捷径。
- **Tauri 2 Mobile** 能复用 Web 前端，但移动插件必须逐项看 Android/iOS 支持矩阵和备注；它适合已有 Tauri/Rust 投资、并愿意承担较年轻移动生态的团队，不应仅凭桌面 Tauri 经验推断移动可用性。[T1][T2]
- **uni-app/uni-app x、Taro** 只有在小程序、国内多端投放或鸿蒙覆盖本身是一级目标时才进入候选。它们不是“把现有 React DOM 阅读器原样编译成高质量原生 App”的证明。

## 1. Marginal 代码现状证据与决策边界

以下证据来自 2026-09-11 的代码探索（相对仓库根路径的文件与行号），与外部框架事实分开表述：

- **技术栈**：`packages/app` 为 React 18 + ReactDOM + Vite（`packages/app/package.json:1-29`）；`packages/core` 为纯 TS，仅依赖 fflate（`packages/core/package.json:1-18`），并定义 repository 抽象（`packages/core/src/repository.ts:19-68`）。
- **移动 UI 已是独立 DOM 页面树**：`packages/app/src/App.tsx:1-70` 根据 coarse pointer/宽度选择 `mobile/*` 页面，而非复用桌面布局。这意味着“移动体验”已有专门设计，但实现仍是 DOM。
- **桌面壳极薄**：Tauri 2 仅注册 SQL 插件、无自定义 Rust commands（`src-tauri/src/lib.rs:1-15`）。
- **存储已双轨且接缝成熟**：Web 优先 SQLite WASM + OPFS Worker、失败降级 IndexedDB；Tauri 走原生 plugin-sql（`packages/data/src/open.ts:1-50`）；共享数据语义由 `SqliteRepositoryBase` 保证，`packages/data/src/tauri-driver.ts:1-47` 动态加载 plugin-sql。“换一个原生壳 = 再写一个 data driver”的接缝已经存在。
- **导入/分享范围窄且偏 Web API**：当前仅支持 TXT、不支持 EPUB（`MobileImport.tsx:31-53,127-135`）；书包为自定义 `.mabk` ZIP（`packages/core/src/bundle.ts:9-68`）；导出走 DOM `<a>` 下载（`actions.ts:287-310`）；分享为 WebShare/canvas PNG/下载/复制（`MobileReader.tsx:381-400,490-500,739-756`）。系统“打开方式”导入、文件提供器、系统分享 sheet 均需原生桥。
- **阅读器强 DOM 依赖**：DOM 多栏 + ResizeObserver + CSS transform 分页（`ReaderView.tsx:25-83,94-149`）；IntersectionObserver/visibilitychange/localStorage 生命周期管理（`MobileReader.tsx:58-88,154-236,333-345`）。
- **锚点是可移植数据，交互是段落点击**：`Anchor = paragraph + charOffset`；没有基于 Selection/Range 的划线批注实现。锚点数据层不锁死 DOM，但分页与渲染层锁死 DOM。
- **沉浸适配用 CSS**（safe-area/dvh），无原生能力依赖。
- **测试现状**：core smoke、`actions.test.ts`、`mobile/logic.test.ts`、`e2e/import-and-reader.spec.ts`；没有原生宿主/真机文件分享与存储合同覆盖。历史绿灯不能当作移动壳的实测结论。

**决策边界**：core/repository/data 三层是可移植资产；平台差异集中在四类 Web API 使用点——文件导入导出、分享/剪贴板、海报渲染（canvas）、生命周期/偏好。由此得到四个必须实测的维度（排版、文件、离线、沉浸交互）；预期是：**WebView 范式最贴近现状，原生范式必须先做 ports 改造再谈 UI 重写**。建议的 ports：`FileSource/FileStore`、`Share/Clipboard`、`PosterRenderer`、`Lifecycle/Preferences`（repository 接缝可作模板）。

## 2. 六种主流方案全景

### 2.1 Capacitor：Web-first 原生容器

**范式**：现有 Web UI 在 iOS WKWebView/Android WebView 中运行；JS 通过 Capacitor bridge 调用原生插件，可写自定义插件。官方示例是构建 Web 项目、添加 iOS/Android 平台并 `cap sync`。[C1]

**复用与能力**：对 Marginal 最直接的价值是复用 React/DOM/CSS 阅读器和 TypeScript 领域逻辑。现有 `mobile/*` 页面树及 CSS safe-area/dvh 可原样进入 WebView。官方插件覆盖 Share 等常见能力；Share 插件安装后由原生平台提供分享入口。[C2] 目前 `MobileReader.tsx` 的 WebShare/canvas PNG/下载/复制（`MobileReader.tsx:381-400,490-500,739-756`）和 `actions.ts` 的 DOM `<a>` 下载（`actions.ts:287-310`）应改为经 `Share/Clipboard/FileSource/FileStore` ports 的 Capacitor 实现。文件、SQLite、文档选择器、通知、状态栏等应逐项选择官方/可信社区插件并验证平台差异；缺口需要 Swift/Kotlin 插件。存储侧需增加 Capacitor SQLite 驱动或明确采用 WebView 存储，复用 `SqliteRepositoryBase` 的数据语义。

**离线与文件**：Web 端可继续使用 IndexedDB/SQLite WASM 等实现；原生端应选 SQLite 或文件插件并设计 adapter。不要假设 Web 数据库文件可直接当作 iOS/Android 数据库文件共享；导入导出格式应是明确的“书包”协议，带 schema 版本、校验和恢复策略。

**阅读器**：保留 DOM 是其最大优势；但 WKWebView 与 Android WebView 是不同实现，CSS 分页、文本选择、字体、文件 URL、滚动和内存必须做设备矩阵测试。沉浸模式通常需少量原生系统 UI 配置，不必重写页面。

**发布/更新**：每个原生插件、权限、原生配置变化都需要生成并提交新二进制。Web 资源更新仍受 Apple/Google 关于下载/执行改变功能的政策约束；不能把“可替换 Web 资源”理解为任意绕过审核的热更新。Apple 2.5.2 要求 App 自包含，禁止下载、安装或执行引入/改变功能的代码；4.2 要求超越重新包装网站的功能、内容和 UI。[P1] Google 规则同样需在发布前核对，本文未将网络失败时无法复核的细节写成绝对结论。[P2]

**适用**：已有成熟 Web 应用，主要交互可由 WebView 高质量承载，原生能力是文件/分享/系统外观等有限桥接。

**不适用**：依赖原生复杂动画、后台任务、系统级编辑器或需要所有 UI 均为原生控件；除非愿意维护较多插件代码。

### 2.2 React Native / Expo：原生控件 + JS 业务

**范式**：RN 的 `View`、`Text`、`ScrollView` 等映射到平台原生组件；React Native 官方资料也展示了把原生 WebView 作为组件集成的方式。[R1] `react-native-web` 是另一层把 RN 组件映射为 Web 语义 HTML 的方案，不等于把任意 React DOM/CSS 页面变成 RN 原生组件。

**复用与能力**：对 Marginal，`packages/core`（纯 TS、仅 fflate）与业务算法可直接在 RN 复用；但 app 层 actions/store 直接使用 Web API（DOM 下载、WebShare、canvas、localStorage、visibilitychange，见 §1 证据），需先抽成 ports。`ReaderView.tsx` 的 DOM 多栏/ResizeObserver/CSS transform 分页与 `mobile/*` DOM 页面树不能在 RN 原生组件中复用。可选两条路：

- RN 原生壳 + WebView 阅读器：复用阅读器，但形成 RN 外层与 WebView 内层的消息桥、文件/选择/锚点协议。
- RN 原生阅读器：获得原生滚动/手势和生态，但需重新实现文本测量、分页、图文锚点、选择和无障碍。

Expo 提供跨 iOS/Android/Web 的 React Native 工具和 EAS 服务。EAS Update 官方边界是更新“非原生部分”（JS、样式、图片）；原生代码、原生依赖、权限或 Expo SDK 变化需要新构建，并以 runtime version 将更新发送给兼容原生代码的构建。[E1] 因此它不是任意原生代码热更新方案。

**离线与文件**：`expo-sqlite` 可提供原生 SQLite，但 Web 支持涉及 WASM、Metro 资源以及 COOP/COEP 等配置，不能无条件视为与原生一致；仓库既有研究已记录其 Web 支持和问题风险。文件选择、分享等 Expo 模块生态较强，但仍要核查 iOS/Android 权限、URI 生命周期和大文件行为。

**适用**：移动原生 UI、导航、手势、系统集成是首要目标，愿意重做阅读器或把阅读器隔离在 WebView；团队已有 RN/Expo 经验。

**不适用**：首要目标是把 CSS/DOM 阅读器和 Web 端一份代码原样带到移动端。

### 2.3 Flutter：自绘 UI + Dart

**范式**：Flutter 用 Dart 构建跨平台 UI，主要由 Flutter 渲染管线绘制；也能嵌入 iOS/Android platform views，但这会形成 Flutter 与原生视图的组合边界。[F1] 现有 Web UI 不能直接成为 Flutter widget。

**复用与阅读器**：对 Marginal，Flutter/Dart 不能直接复用 TS 代码，只能复用协议与规格——`.mabk` 书包 ZIP 格式（`packages/core/src/bundle.ts:9-68`）、SQL schema/迁移（`packages/core/src/repository.ts:19-68`）、`Anchor = paragraph + charOffset` 锚点规则——本质是“按规格重写 + 双实现一致性测试兜底”。DOM/CSS 分页（`ReaderView.tsx` 的多栏/ResizeObserver/CSS transform）、浏览器文本选择和网页无障碍不能直接继承。可在 Flutter 中嵌 WebView 复用阅读器，但将面临 Flutter↔WebView 通信和嵌入视图的手势/性能边界；也可重写为 Flutter 文本布局，代价与风险应以原型测量，不使用网上统一性能数字。

**离线与文件**：Dart/Flutter 有成熟的移动插件生态，SQLite、文件和分享可通过插件实现；但跨平台插件的实现质量和桌面/Web 支持仍需逐项看矩阵。包体、首帧、字体和渲染表现必须在目标构建中测量，不引用框架宣传或他人基准作 Marginal 指标。

**适用**：需要高度定制的原生感/自绘交互，接受 Dart 生态和重做 Web UI；移动优先。

**不适用**：Web 是第一公民，且阅读器排版严重依赖 DOM/CSS。

### 2.4 Tauri 2 Mobile：Web 前端 + Rust/原生插件

**范式**：与 Capacitor 同属 WebView/网页优先，但后端/命令和插件可使用 Rust，并在移动端扩展 Swift/Kotlin。Tauri 官方将 2.0 定位为加入 iOS/Android 支持；插件系统允许移动端原生代码。[T1]

**复用与能力**：Marginal 的 `src-tauri/src/lib.rs:1-15` 当前仅注册 SQL 插件、无自定义 Rust commands；`packages/data/src/tauri-driver.ts:1-47` 已动态加载 plugin-sql，且 `SqliteRepositoryBase` 保持跨驱动数据语义，因此桌面到移动的迁移面相对小。官方插件目录分别列出 Windows、Linux、macOS、iOS、Android，并要求按插件核对平台列和星号备注；桌面支持不能推断移动支持。[T2] Tauri SQL 页面列出 Android/iOS，并要求配置 capability 权限；写操作需要相应权限。[T3]

**离线与文件**：SQL plugin 可配置 SQLite，但移动路径、迁移、并发和升级恢复要在真机测试；文件系统权限遵循移动沙盒。书包导入导出应抽象为共享协议，平台只负责选择/读写数据。

**阅读器**：与 Capacitor 一样，DOM 复用很强；内核差异和插件成熟度是主要风险。移动端插件/生命周期/签名工程比桌面复杂。

**适用**：已重投 Tauri/Rust、希望尽可能复用 Web、且移动需求主要是文件/分享/本地数据库/只读阅读。

**不适用**：需要大量成熟移动插件、低风险团队交付，或需要把移动 UI 变成真正原生控件；应与 Capacitor 实做同一薄切片后比较，而不是凭宣传页选择。

### 2.5 PWA：浏览器安装能力

**范式**：标准 Web 应用 + manifest + service worker + Web 存储/缓存，运行在浏览器提供的安装和离线模型中。它不是 iOS/Android 原生二进制，原生能力受浏览器和操作系统支持矩阵限制。[W1]

**复用与离线**：对现有 Web 复用最高；service worker 可缓存应用资源，IndexedDB/SQLite WASM 可支持本地书库，但要设计存储配额、清理、隐私浏览、备份和浏览器升级异常。文件导入可使用 `<input type=file>`；分享可用 Web Share（支持情况需运行时检测），不能保证系统文件提供器与原生 App 同级体验。

**阅读器与发布**：DOM/CSS 阅读器无需迁移，迭代也不走商店二进制发布；但无 App Store 审核并不意味着可任意执行远程代码，网站仍受浏览器安全策略。iOS/Android 的安装、后台、文件和通知能力需逐设备版本验证。

**适用**：先验证阅读器、离线书包、响应式沉浸交互；面向链接分发或不需要商店存在感。

**不适用**：必须出现在两大商店、深度系统文件/分享/后台能力或稳定的系统级阅读体验。

### 2.6 Kotlin Multiplatform（KMP）：共享逻辑，UI 可选

**范式**：官方明确支持三种层次：只共享业务逻辑并保留原生 UI；用 Compose Multiplatform 共享 UI；或仅共享小模块。[K1] KMP 不是特定的 WebView 容器，也不是自动生成同一套 iOS/Android UI。

**复用与能力**：可共享领域模型、同步、数据库 repository、网络和解析；原生 SwiftUI/Android UI 仍需两端维护。官方文档示例把 database driver 作为平台注入共享 SDK，说明了可测试的边界。[K2] Compose Multiplatform 文档也明确设备/权限、文件、数据库等 API 不在其统一 UI 范围内，仍需平台代码或第三方库。[K3]

**阅读器**：要么两端各自原生重做排版，要么嵌 WebView；既有 TS/React UI 几乎不能直接复用。它适合把“阅读数据/修复流水线/同步”抽成 Kotlin，而不是保留当前 Web 第一实现。

**适用**：原生 UX 和平台一致性高于 UI 复用，组织已有 Kotlin/Swift 能力，长期愿意维护 native UI。

**不适用**：TypeScript/Web 是核心资产，目标是快速把同一阅读器带到移动端。

## 3. 国内多端：uni-app/uni-app x 与 Taro

### 3.1 uni-app 与 uni-app x

官方资料将 uni-app 定位为 Vue 语法的多端框架，覆盖 Web、Android、iOS、HarmonyOS 和多种小程序；uni-app x 是下一代引擎，UTS/组件可针对 Android、iOS、HarmonyOS 等生成更接近原生的实现。[U1] uni-app x 的官方示例展示 Android 原生组件、iOS UIKit 组件及 HarmonyOS ArkUI 混编，这恰好说明“跨端”包含平台实现差异，而不是所有 API 完全相同。[U2]

**重要边界**：uni-app（Vue/JS 运行模型）、uni-app x（UTS/原生编译模型）、Web、小程序、iOS/Android App、HarmonyOS NEXT App 不是互换目标。必须以目标平台的组件/API 支持表、插件实现和真机结果为准；小程序的受限运行时与高质量原生 App 的文件、数据库、后台、分享能力不可等同。uni-app x 对 Marginal 的现有 React/DOM/CSS 阅读器也不是直接迁移路径，除非接受重做 Vue/UTS UI 或嵌 WebView。

**适用**：国内小程序矩阵、国产系统/鸿蒙覆盖和 Vue 团队是一级目标，并能接受条件编译、平台插件和多套验证。

### 3.2 Taro

Taro 官方定位为多端编译框架，目标包括 H5、React Native 以及微信、支付宝、百度、抖音、QQ、京东等小程序。[T1a] 平台 API/组件存在明确差异：官方文档示例中，文件系统管理器只支持若干小程序而不支持 H5、RN、Harmony；某些媒体 API 也只支持微信小程序。[T1b] 这提供了一个直接的风险证据：同名 Taro API 不代表所有产物具备同一能力。

Taro 适合以小程序获客/分发、H5 与部分 RN App 共享业务和组件的产品。对 Marginal，现有 React DOM 阅读器仍需按 Taro 组件/平台约束重构，CSS 多栏分页和文件导入分享不能从小程序目标自动获得；若选 Taro RN，仍然是 RN 原生 UI/桥接路线。鸿蒙目标也应单独核对版本和组件矩阵，不能把“支持小程序”表述成“同一编译产物完整支持鸿蒙原生 App”。

## 4. 横向能力比较（定性，不是评分）

| 范式 | 代表方案 | Web/DOM 复用 | 原生 UI/能力 | 离线数据库与文件 | 阅读器沉浸交互 | 主要维护面 |
|---|---|---|---|---|---|---|
| WebView/网页优先 | PWA、Capacitor、Tauri 2 | 最高 | 插件/自定义桥 | Web 与原生 adapter 分开验证 | DOM 复用强，内核差异需测 | Web + 插件 + OS/WebView 差异 |
| JS 驱动原生 UI | RN/Expo | 逻辑高，DOM UI 低；可嵌 WebView | 原生生态强 | 原生库较强，Web 另配 | 原生 UI 强；DOM 阅读器需嵌入或重写 | JS/native 版本、桥、平台模块 |
| 自绘 UI | Flutter | 低；可嵌 WebView | 插件生态强 | 插件/平台实现需核对 | 自绘可控但文本/选择/排版需验证 | Dart + Flutter + platform views |
| 共享逻辑 | KMP | 逻辑可共享，Web UI 不共享 | 原生 UI 最强 | driver/平台实现注入 | 两套 native 或 WebView | Kotlin shared + Swift/Kotlin UI |
| 国内多端编译 | uni-app/uni-app x、Taro | 取决于目标与组件；不是任意 DOM | App/鸿蒙/小程序各有边界 | 平台 API 差异明显 | 需按产物重测 | 条件编译、平台插件、审核矩阵 |

### 包体、性能与“原生感”

不能用框架官网的“轻量/高性能”宣传或互联网上不一致的设备测试，替 Marginal 形成统一基准。包体应分别测：最小 release 包、加入 SQLite/字体/阅读器后的包、首装下载、解压后占用和更新包；性能应测真实长文档分页、翻页/滚动帧稳定性、输入响应、内存峰值、耗电和后台恢复。WebView 方案不自动等于慢，原生方案也不自动等于阅读器排版更快；工作量取决于是否保留 DOM、字体、图片和分页策略。

## 5. 发布、更新和合规边界

### iOS

Apple Guideline 4.2 要求 App 在功能、内容和 UI 上超越“重新包装的网站”；4.2.2 限制主要是网页剪辑、内容聚合或链接集合；2.5.2 要求 App 自包含，禁止下载、安装或执行会引入/改变功能的代码；2.5.6 对浏览网页的 App 要求使用适当的 WebKit 框架和 WebKit JavaScript。[P1]

因此，Capacitor/Tauri/PWA 壳并非天然不能上架，但 Marginal 应提供独立的离线书库、导入/导出、阅读器排版、锚点/实体卡、沉浸交互等产品价值，不能只是远程站点套壳。Web 资源更新要限制在不改变已审核功能的内容/修复范围；涉及原生能力、权限或功能边界的变更走新二进制和审核。最终以 Apple 当期指南、App Review 实际反馈和账号政策为准。

### Android / Google Play

Android 原生二进制和 WebView 资源同样需要按 Google Play 当期政策与 Data safety、权限、目标 SDK、内容和用户数据要求核对。原生代码、权限和插件变化应走新包；Web 资源更新不可作为任意下载/执行新功能的机制。由于本次官方 Google 页面请求超时，没有把未核验的动态代码条款写成逐字断言；发布前必须由负责人重新查看官方政策并在目标 API/商店轨道验证。[P2]

### OTA 的谨慎定义

- PWA/网站：资源由 Web 部署系统更新，但仍受浏览器安全模型和商店壳政策约束。
- Capacitor/Tauri：原生 shell/插件/权限必须重新构建；是否允许更新 Web 资源取决于不改变审核功能的范围和商店政策，不能承诺“热更新”。
- Expo EAS Update：官方边界明确为与已安装原生二进制兼容的 JS/样式/图片更新；native library、权限、SDK 或其他原生变更需要 EAS Build 新二进制，并通过 runtime version 匹配兼容构建。[E1]
- Flutter/KMP/uni-app/Taro：各自的商店发布和资源更新机制不能概括为任意 OTA；以其官方发行工具和 Apple/Google/国内平台政策逐项核对。

## 6. 推荐矩阵：何时选、何时不选

### 首选验证：Capacitor 与 Tauri 2 Mobile 并列薄切片（不预判胜负）

选择条件：Web/DOM 阅读器继续作为第一实现（`mobile/*` 页面树 + `ReaderView.tsx` DOM 分页）；移动端 v1 主要是离线只读、TXT/.mabk 文件导入导出、系统分享和沉浸阅读；团队接受少量 Swift/Kotlin 插件或少量 Rust/Swift/Kotlin 移动插件维护。

Capacitor 的优势是移动 Web-first 定位与更成熟的移动插件心智，对现有 DOM 资产迁移成本最低；Tauri 的优势是 Marginal 已有 Tauri 桌面壳（`src-tauri/src/lib.rs:1-15`，仅 SQL 插件、无自定义 commands）和 `tauri-driver` 数据驱动，可沿用同一权限/插件模型。两者谁胜出应由同一薄切片实测决定：书包导入→SQLite 写入→打开长文→分页/锚点→分享导出→锁屏/前后台恢复→iOS/Android release 构建。

### 条件性选择：RN/Expo

选它的前提是移动原生导航、手势、系统交互成为核心差异化，并接受 WebView 阅读器或重写阅读器；`packages/core`（纯 TS）可直接复用，但 app 层 actions/store 需先按 ports 去 Web API（DOM 下载、WebShare、canvas、localStorage、visibilitychange）；EAS Update 只用于兼容原生 runtime 的非原生更新。不要选它来“无改动复用 CSS 分页”。

### 条件性选择：Flutter

选它的前提是愿意使用 Dart、自绘/原生混合 UI，并把文本排版和选择交互当作独立产品工程；它只能复用 `.mabk`/schema/锚点等协议规格，不能声称复用 TS 代码。若只为复用 Web 阅读器，不应优先。

### 条件性选择：KMP

选它的前提是有 Kotlin/Swift 原生团队，愿意共享数据/同步/领域逻辑并维护两套 UI；它可作为未来数据层战略，不是当前 Web UI 的移动壳。

### 国内多端选择：uni-app/uni-app x 或 Taro

选它的前提是小程序矩阵、国内渠道或鸿蒙原生覆盖是一级业务目标，并接受每个产物有独立 API/插件/审核验证。Taro 更贴近 React/小程序/H5/RN 组合；uni-app 更贴近 Vue，多端生态和 uni-app x 的原生/鸿蒙方向。两者都不应在没有目标平台样例验证时承诺“全端一次编译、能力一致”。

### PWA

无论最终选哪一套，都建议作为 Web 第一阶段和离线能力基线。若测试证明文件/分享/通知等能力足够，PWA 可直接服务一部分用户；否则将其作为商店 App 的降级/预览入口，而不是强行承担完整原生职责。

## 7. 分阶段验证方案（不迁移、不预估工期）

1. **冻结跨端契约并抽 ports**：定义 `.mabk` 书包格式、schema/migration 版本、`Anchor = paragraph + charOffset`、图片引用、导入校验、分享导出格式；以现有 `packages/data` 双驱动和 `SqliteRepositoryBase` 为模板抽四类 ports：`FileSource/FileStore`（TXT/.mabk 导入导出、系统打开方式）、`Share/Clipboard`、`PosterRenderer`（canvas PNG→平台实现）、`Lifecycle/Preferences`（visibilitychange/localStorage→原生事件/存储）。UI 与平台 adapter 只通过契约交互；不要为了新壳重写已经成熟的 repository seam。
2. **PWA 基线**：在至少一台 iOS Safari、Android Chrome 和桌面浏览器测试离线启动、长文分页、字体、选择、导入导出、Web Share（若存在）和存储恢复；记录“不支持”降级。
3. **WebView 薄切片**：用同一 Web 构建分别做 Capacitor 与 Tauri 2 Mobile 最小应用（同一验收清单，不预判胜负）；只接文件选择、SQLite、分享、状态栏/沉浸、前后台恢复。逐项记录插件版本、平台标记、权限、错误和 native bridge 消息。现有 e2e（`e2e/import-and-reader.spec.ts`）与单元测试只覆盖 Web 宿主，移动壳需另建设备/模拟器验收。
4. **阅读器验收集**：使用真实长文、图片锚点、超长段落、不同字体/动态字号、横竖屏、深色模式、系统返回手势；测分页正确性、锚点稳定、选择复制、内存峰值和恢复，不与未同设备测试的框架宣传比较。
5. **原生路线决策门**：若 WebView 方案在关键体验上失败，再做 RN/Expo 或 Flutter 的二选一原型；原型必须明确是“嵌 WebView 复用”还是“原生重写”，否则结果不可比较。若组织已决定共享 Kotlin 逻辑，再单独评估 KMP 数据层，不把它误当 UI 迁移。
6. **国内渠道门**：只有在需求确认小程序/鸿蒙时，分别以 uni-app/uni-app x、Taro 做目标产物 spike，核对目标平台组件、文件、SQLite、分享、登录/审核和构建链；不能用 H5 或微信小程序成功替代鸿蒙/iOS/Android 证据。
7. **发布合规门**：用真实商店账号提交内部/测试轨道，核查 Apple 4.2/2.5.2/2.5.6、Google Play 当期动态代码/数据安全/权限规则及国内渠道规则。OTA 只发布不改变已审核功能的兼容资源，并保留回滚和版本匹配。

## 8. 风险登记

- **WebView 内核差异**：分页、字体、选择和手势不是一次开发后自然一致；需真实设备矩阵。
- **插件矩阵错配**：Tauri、Capacitor、Expo、uni-app/Taro 的“支持”都是 API/平台逐项属性；桌面或小程序支持不能外推到移动原生。
- **离线数据迁移**：多驱动/多 OS 路径和事务语义不同；导入损坏与升级回滚必须是产品功能。
- **桥接与生命周期**：WebView 与原生/JS runtime 可能重建，不能假定内存对象持续存在；操作必须可重试、可幂等。
- **阅读器自研成本隐藏**：RN/Flutter/KMP 原生方案看似原生性能更直接，却把分页、锚点、文本选择、无障碍和字体问题变成新工程；WebView 方案则把风险转移到内核差异和桥接。
- **商店与 OTA**：商店政策是动态的；“热更新”不能作为绕过审核的商业承诺。每次涉及原生功能、权限、SDK 或功能边界都应准备新二进制。
- **鸿蒙/小程序边界**：不同目标可能共享部分业务代码，但平台 API、组件、包格式和审核链不同；必须逐平台实证。

## 9. 来源（官方一手资料）

### 跨端框架与能力

- [C1] Capacitor 官方首页/安装平台：https://capacitorjs.com/docs/next 、https://capacitorjs.com/docs/basics/workflow
- [C2] Capacitor Share API：https://capacitorjs.com/docs/apis/share
- [R1] React Native 官方架构与原生组件/WebView 示例：https://reactnative.dev/docs/the-new-architecture/landing-page 、https://reactnative.dev/docs/fabric-native-components
- [E1] Expo EAS Update：https://docs.expo.dev/eas-update/introduction/ 、https://docs.expo.dev/eas-update/runtime-versions/
- [F1] Flutter 官方平台视图：https://docs.flutter.dev/platform-integration/ios/platform-views 、https://docs.flutter.dev/platform-integration/android/platform-views
- [T1] Tauri 2 官方移动/插件说明：https://v2.tauri.app/blog/tauri-20/ 、https://v2.tauri.app/plugin/
- [T2] Tauri 官方插件目录与平台矩阵：https://v2.tauri.app/plugin/
- [T3] Tauri SQL plugin：https://v2.tauri.app/plugin/sql/
- [K1] Kotlin Multiplatform 共享层级：https://www.jetbrains.com/help/kotlin-multiplatform-dev/multiplatform-intro.html
- [K2] KMP 共享业务逻辑与注入数据库 driver：https://www.jetbrains.com/help/kotlin-multiplatform-dev/ktor-sqldelight.html
- [K3] Compose Multiplatform 平台 API 边界：https://www.jetbrains.com/help/kotlin-multiplatform-dev/compose-multiplatform-and-compose.html
- [W1] web.dev PWA 学习材料：https://web.dev/learn/pwa
- [U1] uni-app 官方文档/平台介绍：https://uniapp.dcloud.net.cn/ 、https://doc.dcloud.net.cn/uni-app-x/
- [U2] uni-app x 原生组件与平台混编：https://doc.dcloud.net.cn/uni-app-x/plugin/uts-component-vue.html 、https://doc.dcloud.net.cn/uni-app-x/component/native-view.html
- [T1a] Taro 官方平台介绍：https://docs.taro.zone/docs/ 、https://docs.taro.zone/docs/README
- [T1b] Taro 官方 API 平台支持矩阵（文件、媒体、Canvas 示例）：https://docs.taro.zone/docs/apis/files/getFileSystemManager 、https://docs.taro.zone/docs/apis/media/audio/setInnerAudioOption

### 商店与更新政策

- [P1] Apple App Review Guidelines（2.5.2、2.5.6、4.2、4.2.2）：https://developer.apple.com/app-store/review/guidelines/
- [P2] Google Play Device and Network Abuse policy：https://support.google.com/googleplay/android-developer/answer/9888077
- [P3] Google Play policy center：https://play.google.com/about/developer-content-policy/

## 10. 来源局限与待补证

- Context7 已按官方库索引查阅上述框架；本次能够确认 Expo runtime/OTA、Tauri 插件矩阵/SQL、RN、Flutter、KMP、uni-app/Taro 的官方文档要点。文档索引可能落后于实际发布版本，本文未把索引中的分支号当作 Marginal 的锁定版本。
- 本次 WebFetch 对 Apple 指南、Tauri 插件/SQL、Expo EAS Update成功；PWA页面、Google Play政策请求存在网络超时或连接失败。Apple 要点已由官方页面提取；Google 相关段落保守表述并要求发布前复核，没有冒称逐条核验。
- 没有在本研究中运行 iOS/Android 真机、比较包体/帧率/内存、提交商店或验证某个插件的生产质量；因此没有量化评分、统一基准或工期承诺。
- Marginal 定制结论基于 2026-09-11 代码探索快照（React 18/Vite app、纯 TS core、双存储驱动、`mobile/*` DOM 页面树、DOM 分页阅读器、TXT/.mabk 导入导出、段落+charOffset 锚点）；若阅读器日后不再是 DOM/CSS 第一实现、出现 Selection/Range 批注、或移动端需求从只读升级为编辑/后台同步/EPUB，应重新打开方案决策。
