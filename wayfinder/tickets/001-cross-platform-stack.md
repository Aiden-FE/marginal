---
id: 001
title: 跨端技术选型评估
labels: [wayfinder:research]
status: closed
assignee: Aiden
blocked-by: []
---

## Question

为该 AI 电子书应用选择跨端技术路线。目标形态：一套核心逻辑（领域模型、AI 流水线、数据层）+ 桌面端全功能（本地文件导入、长驻 AI 任务、富阅读器）+ web 端全功能（浏览器内跑 AI 任务、同一阅读器）；移动端未来仅做阅读，但要求核心可复用。

评估候选至少包括：Tauri（桌面）+ 共享 web 核心、Electron、React Native/Expo（+Web）、Flutter；也可提出更优组合。

硬性评估标准：

1. 桌面端全功能（文件系统访问、长任务、SQLite 级存储）
2. web 端全功能且核心逻辑与桌面共享（不是两套代码）
3. 自研分页引擎 + 图文混排（插图插在段落锚点处）在该路线下的实现难度
4. 未来移动端复用核心的路径
5. 本地优先、可同步的数据模型落地难度

产出：带权衡的推荐路线与备选，明确"共享核心"的边界（哪些层共享、哪些端独有）。

## Resolution

推荐 **TypeScript monorepo「web 核心 = 第一公民」+ Tauri 2 桌面壳**：纯 TS 零平台依赖的 core 包（领域模型、AI 流水线、分页核心、SQLite schema）+ React/DOM 阅读器双端 100% 共享；web 端为 Vite 静态站（sqlite-wasm + OPFS-sahpool，Worker 内），桌面端经 Tauri 2 复用同一前端（tauri-plugin-sql + Rust fs），未来移动端走 Tauri 2 iOS/Android 只读复用。关键依据：自研分页引擎 + 段落锚点图文混排在 DOM/CSS（CSS 多栏 + Range，先例 foliate-js）成本最低，Flutter（CanvasKit 自绘）与 RN（分页器需写两遍、expo-sqlite web 实验性）均否决；Electron 保留为备选（需 Node 生态时只换 adapter 不伤核心）。详见 [../research/001-cross-platform-stack.md](../research/001-cross-platform-stack.md)。
