---
ticket: weapp/009
title: 小程序端技术栈与工程边界
date: 2026-09-08
assignee: Aiden
---

# 技术栈与工程边界（research/weapp/009）

## 结论

选 Taro（React + TypeScript）编译微信小程序。现有项目是 React + TypeScript monorepo，Taro 支持标准 React hooks、微信页面生命周期 hooks、`taro build --type weapp --watch`、微信组件与 API 类型；并提供 React VirtualList。原生 WXML/WXSS会形成第二套组件范式，不能带来跨端 UI 复用收益，否决。

关键边界：`packages/weapp` 只复用 `packages/core` 的领域逻辑，不复用 `packages/app` 的 UI；Taro 是开发/编译框架，不是把 Web DOM 打包进小程序。视觉组件全部针对移动重新实现。

## 来源（访问于 2026-09-08）

- Taro Getting Started：https://github.com/nervjs/taro-docs/blob/master/docs/GETTING-STARTED.md
- Taro Hooks：https://github.com/nervjs/taro-docs/blob/master/docs/hooks.md
- Taro codebase overview：https://github.com/nervjs/taro-docs/blob/master/docs/codebase-overview.md
- Taro VirtualList：https://github.com/nervjs/taro-docs/blob/master/docs/virtual-list.mdx
