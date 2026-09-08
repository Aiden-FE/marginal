---
id: 009
title: 小程序端技术栈与工程边界
labels: [wayfinder:research]
status: closed
assignee: Aiden
blocked-by: []
---

## Question

UI 层选型决定整个工程边界，必须在建图期钉死，不能漏到实现期。

## Resolution

（无人值守模式：推荐方案已采纳，可事后否决；facts 来自 research + 官方文档）

**选型：Taro（React + TypeScript，编译到微信小程序）on top of 现有 pnpm monorepo。**

1. **Taro 而非原生 WXML/WXSS**：
   - 现有 app 是 React（React 18/Vite），Taro 的 React 语法与 hooks（useState/useEffect）可**直接复用**，且 Taro 提供页面生命周期 hooks（useDidShow/useReady/usePageScroll 等）与小程序一阶对齐。
   - Taro 官方示例内置 React 虚拟列表组件（VirtualList）——对应移动长章节渲染需要。
   - 否决 native 原生小程序：它意味着把现有 React 心智分支成 WXML/组件化 DSL，`packages/core` 虽可复用但 UI 层要从零写两套不同范式，且无组件复用收益、开发效率低。
   - 备注：跨端框架引入 Runtime/编译层，Vented 真机在某些原生能力边界会碰到坑（尤其未来若上 Skyline）；但对单端微信 v1 是投资产出比最优，且未来要 H5/APP 时能平迁——符合「移动主战场」的长期方向。
2. **构建链**：`@tarojs/cli`（webpack5 编译weapp；Taro v4 可切 vite）。在 pnpm workspace 中新增 `packages/weapp`，依赖 `@tarojs/react`、`@tarojs/components`、`@tarojs/runtime`、`@tarojs/taro`；`packages/core` 通过 npm 构建进入 `miniprogram_npm`（Taro 自身处理依赖打包，`packages/data` 的 weapp 驱动以源码/内部依赖形式被打包，不 export 进 npm）。
3. **状态/数据**：沿用 web 端自研 store 模式（store.ts 的 hooks 风格）+ WeappRepository；小程序端不强上额外状态库。
4. **组件库**：不使用 Taro UI 或 Vant——移动端要自定的视觉体系，用轻量基础组件自绘（按钮/卡片/列表/tabbar 均为自定义），与 spec「移动专属视觉」呼应；Taro 仅提供基础 View/Text/Image/ScrollView。
5. **开发者工具**：微信开发者工具在 macOS；`@tarojs/cli build --type weapp --watch` 产出后由工具加载 `packages/weapp/dist` 预览/真机调试。
6. 工程边界：`packages/weapp`（UI+管道编排+weapp 驱动）依赖 `packages/core`；`packages/app`（web/React）与 `packages/weapp` 不共享组件源码（仅各端自用），避免两端 UI 互相拖累；共享层只有 core 领域逻辑与概念（CONTEXT.md 不变）。

来源：Taro 文档（GETTING-STARTED / codebase-overview / hooks / virtual-list，访问 2026-09-08）。
