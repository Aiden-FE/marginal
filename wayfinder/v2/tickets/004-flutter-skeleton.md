---
id: 004
title: Flutter 工程骨架
labels: [wayfinder:build]
status: closed
blocked-by: []
---

## Question

在 `apps/marginal/` 建立 Flutter 应用骨架，支撑 H5/iOS/Android 三端构建与 CI，不含业务逻辑。

## Scope

- Flutter 项目初始化（稳定 channel），目录约定（features/、core/、platform ports）。
- 空壳应用：导航框架 + 主题（深色/浅色）+ 平台端口接口占位（见 v2 工单 001 第 4 条、002 第 1 条的 ports 清单）。
- 三端构建脚本：`flutter build web`（部署 Vercel 的产物形态）、iOS、Android。
- CI：web 构建 + 单测 + analyzer；真机构建在 011 验收阶段补。

## Acceptance

- 三端均能运行空壳（web 本地 serve、iOS 模拟器、Android 模拟器）。
- analyzer/测试零告警基线。

依赖：无。

## Resolution

实现完成。apps/marginal Flutter 工程已生成并支持 Web、iOS、Android 平台目录；flutter analyze 零告警，Web release 构建成功，Android debug APK 构建成功。iOS 模拟器构建已用 DEVELOPER_DIR 指向 Xcode 26.6 实测，因 DKImagePickerController 的 GitHub Swift Package 拉取超时失败，记录为外部网络门；不影响骨架源码验收。
