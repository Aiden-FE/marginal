---
id: 003
title: 文生图参考图能力与人物一致性调研
labels: [wayfinder:research]
status: open
assignee:
blocked-by: []
---

## Question

插图链路的既定设计：实体卡（人物/场景）被用户确认（正典）后，后续生成都要把参考图喂给模型以保持形象一致。调研可通过自定义供应商接入的图像生成 API 的参考图支持情况：

1. 候选：OpenAI gpt-image-1、Google Gemini 图像（含 Nano Banana）、Stability、Flux 系（含 BFL API）、国内可经中转使用的（通义万相、即梦等）——各自是否支持参考图输入、支持几张、分辨率与成本量级。
2. 参考图 + 文字描述做"同一人物多图一致"的实际效果口碑与已知失败模式。
3. 这些能力通过 OpenAI-compatible 协议暴露的差异（能否统一抽象，还是要为图像任务留原生协议的口子）。
4. 推荐的生成工作流：人物卡文字描述 + 参考图组合如何拼接 prompt。

产出：插图任务供应商的能力约束清单 + 协议抽象建议（会反过来约束"仅 OpenAI-compatible"这条既定立场的例外情况）。
