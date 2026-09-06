---
ticket: 002
title: 浏览器端 AI 任务可行性
date: 2026-09-06
assignee: Aiden
---

# 浏览器端 AI 任务可行性（research/002）

## 0. 结论速览

**web 全功能成立，附三个设计条件**：

1. 供应商层必须内置**连通性诊断**（预检探测 + 明确报错指引），因为 CORS 放行格局因供应商而异；
2. 任务队列必须按**可中断、可恢复**设计（每项完成即 checkpoint 持久化 + freeze/resume/wasDiscarded 处理），不要试图对抗浏览器生命周期；
3. 存储容量完全充足（数百张插图 + 整本网文在所有现代浏览器配额内），SQLite WASM 的 exportDb/importDb 恰好支撑"全书包"。

## 1. CORS 实测格局（2026-09-06，OPTIONS 预检，Origin: http://localhost:5173）

| 供应商 | 预检结果 | access-control-allow-origin |
| --- | --- | --- |
| OpenRouter | ✅ 204 放行 | `*` |
| 硅基流动 SiliconFlow | ✅ 204 放行 | `*`（allow-headers: `*`） |
| DeepSeek | ✅ 200 放行 | 回显 origin |
| Moonshot / Kimi | ✅ 204 放行 | 回显 origin |
| 阿里 DashScope compatible-mode | ✅ 200 放行 | `*` |
| 智谱 bigmodel | ✅ 200 放行 | 回显 origin |
| OpenAI 官方 | ❌ 直连超时（本网络无代理不可达） | — |
| Anthropic | ❌ 边缘 403（Cloudflare HKG）；官方文档提供 `anthropic-dangerous-direct-browser-access: true` 头支持浏览器直呼，实测本网络边缘仍拦截，疑似地区封锁 | — |
| Gemini generativelanguage | ❌ 本网络直连不通 | — |

**解读**：个人工具实际会配的"自定义供应商"——国产厂商、OpenRouter 类网关、自建 one-api/new-api 中转——大概率放行 CORS（自建网关取决于其配置，需逐个探测）；OpenAI/Anthropic/Gemini 官方端点要么需要代理、要么地区封锁。因此"浏览器直连"是**大概率可用但不可假设**，诊断是必须品。

## 2. 缓解方案（按轻到重）

1. **应用内连通性诊断（v1 必做）**：对每个供应商配置跑一次预检/轻量 GET，UI 上明确标注"浏览器可直连 / 需代理"，失败时给出可操作指引。
2. **本地一键小代理（v1 内置）**：~50 行的 Node/Bun/Deno 脚本，监听 `127.0.0.1:<port>` 转发任意上游并注入 CORS 头；桌面端在运行时还可由 Tauri Rust 侧直接充当代理。
3. **Cloudflare Worker 自部署（文档方案）**：wrangler 一键部署，免费额度足够个人；代价是 CF 账号 + 一次性部署步骤。

## 3. 长任务生命周期

- Chrome（尤其移动端）后台约 5 分钟**冻结**页面任务队列；内存压力下后台 tab 可被 **discard**（进程被杀，重访时整页重载，`document.wasDiscarded` 可检测）。来源：[Page Lifecycle API](https://developer.chrome.com/docs/web-platform/page-lifecycle-api)、[Chromium freezing intent](https://groups.google.com/a/chromium.org/g/blink-dev/c/NKtuFxLsKgo)、[discarded 状态解析](https://dev.to/frehner/the-discarded-page-lifecycle-state-4lo6)。
- 页面活着时 in-flight fetch（含 SSE 流）继续跑；**frozen/discarded 即断**，无 JS 执行机会。
- Service Worker 不能延长页面寿命；[Background Fetch API](https://developer.mozilla.org/en-US/docs/Web/API/Background_Fetch_API) 只适合纯下载，不适合"生成→解析→写库"的交互式任务流。
- **可行组合（v1 采纳）**：
  - 任务队列状态全量持久化（IndexedDB/SQLite），**每完成一项即 checkpoint**；
  - 监听 `freeze`/`resume` 做持久化与恢复；载入时检查 `wasDiscarded` 从断点续跑；
  - 任务粒度切小（一张图 / 一章），并发 1–2；
  - Wake Lock 仅用于"用户盯着进度条"的场景防系统休眠，不作为任务存活手段。
- 设计立场：**中断是常态**，把断点续跑做成一等公民。

## 4. 浏览器存储容量

- Chrome/Edge：总配额约 80% 磁盘、**单源约 60% 磁盘**；Firefox：min(10% 磁盘, **10 GiB**)；Safari（macOS 14 / iOS 17+）：单源约 **20% 磁盘**（主屏 web app 约 60%），旧版约 1 GiB 后弹窗请求。来源：[web.dev Storage for the web](https://web.dev/articles/storage-for-the-web)、[MDN Storage quotas](https://developer.mozilla.org/en-US/docs/Web/API/Storage_API/Storage_quotas_and_eviction_criteria)、[Safari 配额分析](https://lapcatsoftware.com/articles/2026/5/5.html)、[RxDB 归纳](https://rxdb.info/articles/indexeddb-max-storage-limit.html)。
- [OPFS 与 IndexedDB 共享同一配额池](https://developer.mozilla.org/en-US/docs/Web/API/File_System_API/Origin_private_file_system)，无独立上限；`navigator.storage.estimate()` 运行时可查，`persist()` 申请持久化降低驱逐风险。
- **量级评估**：300 章网文纯文本 ≈ 10–30 MB；插图 500 张 × 1–2 MB ≈ 0.5–1 GB —— 全部在现代浏览器配额内轻松容纳。SQLite WASM 的 `exportDb`/`importDb`（opfs-sahpool VFS）与"全书包"导出/导入天然契合（与 research/001 结论互证）。

## 5. 决议

web 全功能成立。对 spec 的约束：① 供应商抽象带诊断与"需代理"状态；② 本地小代理脚本进 v1 交付物；③ 任务队列以 checkpoint 续跑为第一设计原则；④ 数据层采用 SQLite WASM/OPFS（Worker 内），并在 UI 暴露 `storage.estimate()`。
