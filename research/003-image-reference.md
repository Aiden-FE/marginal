---
ticket: 003
title: 文生图参考图能力与人物一致性调研
date: 2026-09-06
assignee: Aiden
---

# 文生图参考图能力与人物一致性调研（research/003）

## 0. 结论速览

**参考图（img2img/reference）已是 2026 年主流图像 API 的标配能力**，"确认后链路必带参考图"的既定设计完全可行。但**协议层结论有修正**：参考图输入在 OpenAI-compatible 协议里没有统一形状——OpenAI 走 `/images/edits` 的 multipart `image[]` 数组，火山方舟走类 OpenAI images API 加自有扩展参数，Gemini 走 chat 式 `generateContent`。**建议：协议抽象保留 OpenAI-compatible 一条主线，但为图像任务预留"provider 级 adapter 扩展点"**（这修正了"仅 OpenAI-compatible"立场的绝对化表述）。

## 1. 候选供应商参考图能力对照

| 供应商 / 模型 | 参考图输入 | 数量上限 | 协议形状 | 成本量级 |
| --- | --- | --- | --- | --- |
| OpenAI gpt-image-1 / gpt-image-2 | ✅ `/v1/images/edits`，`image` 参数传数组 | gpt-image-1 至 16 张（每张 <25MB，PNG/WEBP/JPG） | OpenAI 原生 multipart | 官方端点需代理 |
| Google Gemini（Nano Banana / gemini-2.5-flash-image） | ✅ `generateContent` 内联图片 | 官方建议最多 3 张效果最佳；gemini-3-pro-image 支持 5 张（部分配置至 14） | Gemini 原生 chat 式，非 OpenAI images 形状 | 官方端点需代理 |
| BFL FLUX.1 Kontext（pro/max/dev） | ✅ 指令式编辑 + 参考图，多轮迭代漂移小 | 社区实测 3 张以上开始失效 | BFL 原生 REST（非 OpenAI 形状）；经 Replicate/fal/硅基流动等可中转 | pro 约 $0.04/张级 |
| 字节 Seedream 4.0+（火山方舟，即梦同源） | ✅ 原生多图融合 + 主体一致性 + 组图 | 最多 **10 张**参考图（`sequential_image_generation=disabled` 仍可用参考图）；prompt 里用"图1/图2"指代 | **类 OpenAI images API + 自有扩展参数**（`sequential_image_generation` 等） | 官方 ¥0.12–0.50/张（按分辨率） |
| 通义万相 / 其他国内厂商 | 各有原生参考图/编辑能力 | — | 协议各异，多数**无** OpenAI 兼容图像端点 | — |
| 硅基流动 / OpenRouter / new-api 类中转 | 部分模型支持 image 参数或 chat modalities 出图 | 随底座模型 | OpenAI-compatible 为主 | 低，聚合计费 |

## 2. 一致性效果口碑与失败模式

- FLUX.1 Kontext 的 [arXiv 论文](https://arxiv.org/html/2506.15742v2)自报角色一致性优于 GPT-Image，社区公认其多轮编辑漂移最小；但 3+ 参考图时一致性开始崩（[社区实测](https://www.reddit.com/r/StableDiffusion/comments/1mpgjds/pushing_flux_kontext_beyond_its_limits_multiimage/)）。
- OpenAI 官方社区确认：纯文字 prompt 不足以维持同一角色，参考图是必要手段（[community.openai.com](https://community.openai.com/t/creating-multiple-images-in-a-single-api-call-with-gpt-image-1/1330450)）。
- Seedream 对亚洲人脸还原度高，但多张自拍参考下偶有偏差（smzdm 实测口碑）。
- **通用最佳实践**：给参考图**编号并在 prompt 里显式指代**（"图1 是角色参考，图2 是场景底图，把图1 的角色放进图2"）——OpenAI、Gemini、Seedream 三家文档/指南一致推荐。
- **对本项目的含义**：每个正典实体卡生成/指定**一张**高质量"定妆照"作为唯一参考图，比塞多张更稳；多实体场景图 = 角色定妆照 + 场景参考各一张（≤3 张是各家共同舒适区）。

## 3. 协议抽象建议

1. **文本任务**（修复/提取）：OpenAI-compatible 单协议，维持既定立场，无变化。
2. **图像任务**：OpenAI-compatible `/images/generations` 作为无参考图的兜底路径；参考图路径抽象为 `generate({ prompt, references[], model })` 能力接口，由 per-provider adapter 落地（OpenAI edits 形状、火山类 OpenAI 扩展形状、Gemini chat 形状各写一个小 adapter，每个 ~百行）。
3. UI 上按 adapter 声明的**能力位**渲染（支持参考图张数、是否支持组图），不支持参考图的供应商只开放"草稿质量"生成——与"确认 = 参考图资格"的立场天然咬合。
4. v1 内置 adapter 优先级：**OpenAI edits 形状**（覆盖官方 + 多数中转）→ **火山方舟形状**（国内首选，参考图能力最强）→ Gemini（可选）。

## 来源

- [OpenAI 图像生成官方指南](https://developers.openai.com/api/docs/guides/image-generation)、[new-api 文档：image 数组参数](https://github.com/QuantumNous/new-api-docs/blob/main/docs/en/api/openai-image.md)、[Replicate gpt-image-2 编辑指南](https://replicate.com/openai/gpt-image-2)
- [Gemini 图像生成官方文档（3/5/14 张参考图）](https://ai.google.dev/gemini-api/docs/image-generation)、[Gemini 2.5 Flash Image 发布公告](https://developers.googleblog.com/introducing-gemini-2-5-flash-image/)
- [FLUX.1 Kontext 官方页](https://bfl.ai/models/flux-kontext)、[arXiv 2506.15742](https://arxiv.org/html/2506.15742v2)、[Reddit 多图实测](https://www.reddit.com/r/StableDiffusion/comments/1mpgjds/pushing_flux_kontext_beyond_its_limits_multiimage/)
- [火山方舟图片生成 API](https://docs.volcengine.com/docs/82379/1541523)、[图片生成教程（多图融合/组图）](https://docs.volcengine.com/docs/82379/1824121)、[模型列表/计费](https://www.volcengine.com/docs/82379/1593702)
