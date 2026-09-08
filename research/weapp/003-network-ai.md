---
ticket: weapp/003
title: 小程序网络与 AI 供应商接入路径
date: 2026-09-08
assignee: Aiden
---

# 网络与 AI 接入路径（research/weapp/003）

## 0. 结论速览

**「用户自配任意 OpenAI-compatible 端点、小程序内直连」在正式版不可行：request 仅允许 https + 已配置 + ICP 备案域名。可行路径三条：A 自建中转（备案域名服务器）／B 微信云开发云函数代理（免域名白名单，客户端走 callFunction）／C 仅开发期用「不校验域名」真机调试。推荐 v1 以 B（云函数代理，按量付费可免费额度起步）为默认实现、A 为可替换部署，key 存云函数环境变量而非小程序本地。**

## 1. 域名白名单事实（来源：network 指南）

- `wx.request/uploadFile/downloadFile/connectSocket` 仅可访问**已配置的合法域名**；仅 https（socket 为 wss）；域名须 **ICP 备案**；不可用 IP（局域网 IP 除外，基础库 2.4.0+）、localhost；仅子域名粒度；不可配 api.weixin.qq.com。
- 开发者工具可开「不校验请求域名、TLS 版本及 HTTPS 证书」；**体验版/开发版**亦可在手机上开调试模式跳过校验——个人自用足够，正式发布强制校验。
- DNS 预解析域名上限 5 个。

## 2. 直连第三方大模型端点评估

- OpenRouter/SiliconFlow/DeepSeek 等均为 https 域名，但 a) 需逐一在后台配置且域名属第三方，配置合法但每个供应商域名都要加；b) key 必须放小程序代码/storage——**反编译可提取，等于公开 key**；c) 供应商未必给小程序备案场景兜底。结论：直连只适合「个人体验版自用」，不适合正式发布。

## 3. 中转路径对比

| 路线 | 门槛 | 成本 | key 安全 | 流式 |
| --- | --- | --- | --- | --- |
| A 自建中转（Node，如 tools/proxy.mjs 生产化） | 需服务器 + **备案域名** + https 证书 | 服务器费 | key 存服务端 ✅ | enableChunked/onChunkReceived 可用（版本待实测） |
| B 微信云开发云函数 | 无需域名/备案（callFunction 不走白名单） | 按量付费，有免费额度 | key 存云函数环境变量 ✅ | 云函数返回整体（文本任务可非流式；流式体验靠分段 loading） |
| C 仅本地调试（不校验域名） | 零 | 零 | key 本地 | 可用 |

- 云函数出网：云函数运行在服务端，调用第三方 https API **不受小程序域名白名单约束**（官方云开发模型，以实际配额/地域为准）。
- 图片链路：云函数/中转拉取图片二进制 → 返回 base64 → 小程序落 USER_DATA_PATH 文件；image 组件直接用本地路径。

## 4. 内容安全（联动 weapp/004）

- 平台提供内容安全检测（msgSecCheck/imgSecCheck/mediaCheckAsync 等）；AI 生成内容正式发布需按类目要求接入并标注「AI 生成」（见 004）。

## 5. 需用户定夺（无法替决）

1. **是否接受云开发（按量计费）**：默认 B 的免费额度对个人自用基本够；不想用则走 A（需备案域名服务器）。
2. **正式发布是否保留 AI 出网能力**：不发布（仅体验版自用）则免大部分合规与成本。

## 来源（访问于 2026-09-08）

- 网络能力/域名：https://developers.weixin.qq.com/miniprogram/dev/framework/ability/network.html
- wx.request/RequestTask.onChunkReceived（API 目录确认存在）：https://developers.weixin.qq.com/miniprogram/dev/api/network/request/wx.request.html
