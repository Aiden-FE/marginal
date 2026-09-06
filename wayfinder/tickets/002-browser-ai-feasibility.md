---
id: 002
title: 浏览器端 AI 任务可行性
labels: [wayfinder:research]
status: open
assignee:
blocked-by: []
---

## Question

web 端要在浏览器内直接调用用户自定义的 OpenAI-compatible 供应商（文本模型做修复/提取，图像模型做插图，图像含参考图上传）。逐项调研并给结论：

1. CORS 现实：主流厂商与常见网关（OpenAI、Anthropic 兼容网关、国内主流、OpenRouter、SiliconFlow 等）是否允许浏览器直呼？大概格局如何。
2. 对不允许直呼的供应商，个人工具场景下最轻的缓解方案（用户本地一键小代理、Cloudflare Worker 自部署脚本等）及各自成本。
3. 长任务生命周期：批量几百次生成调用的任务在后台标签页/锁屏下的存活问题；Service Worker / Wake Lock / 分块断点续跑的可行组合。
4. 浏览器本地存储容量（IndexedDB/OPFS）对"整本网文 + 数百张插图"的容量上限与注意事项。

产出：结论"web 全功能是否成立"；若成立附缓解方案清单；若不成立给出降级形态建议。
