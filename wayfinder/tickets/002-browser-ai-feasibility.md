---
id: 002
title: 浏览器端 AI 任务可行性
labels: [wayfinder:research]
status: closed
assignee: Aiden
blocked-by: []
---

## Question

web 端要在浏览器内直接调用用户自定义的 OpenAI-compatible 供应商（文本模型做修复/提取，图像模型做插图，图像含参考图上传）。逐项调研并给结论：

1. CORS 现实：主流厂商与常见网关（OpenAI、Anthropic 兼容网关、国内主流、OpenRouter、SiliconFlow 等）是否允许浏览器直呼？大概格局如何。
2. 对不允许直呼的供应商，个人工具场景下最轻的缓解方案（用户本地一键小代理、Cloudflare Worker 自部署脚本等）及各自成本。
3. 长任务生命周期：批量几百次生成调用的任务在后台标签页/锁屏下的存活问题；Service Worker / Wake Lock / 分块断点续跑的可行组合。
4. 浏览器本地存储容量（IndexedDB/OPFS）对"整本网文 + 数百张插图"的容量上限与注意事项。

产出：结论"web 全功能是否成立"；若成立附缓解方案清单；若不成立给出降级形态建议。

## Resolution

**web 全功能成立**，附三个设计条件：① 供应商层内置连通性诊断（CORS 实测：OpenRouter/硅基流动/DeepSeek/Kimi/DashScope/智谱全部放行，OpenAI/Anthropic/Gemini 官方端点需代理或被地区封锁，"可直连"不可假设）；② 任务队列按"可中断、可恢复"设计——浏览器后台 5 分钟冻结、内存压力 discard，必须每项完成即 checkpoint 并处理 freeze/resume/wasDiscarded；③ 存储充足（Chrome 单源 ~60% 磁盘、Safari ~20%、Firefox min(10%,10GiB)，数百张插图无压力）。缓解方案：应用内诊断 + 本地一键小代理进 v1，Cloudflare Worker 作为文档方案。详见 [../research/002-browser-ai-feasibility.md](../research/002-browser-ai-feasibility.md)。
