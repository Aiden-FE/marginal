# Marginal v1 产品与技术规格

> 2026-09-06 由 wayfinder 地图走完汇成。每条决策的来龙去脉见 [wayfinder/map.md](../wayfinder/map.md) 的 Decisions so far 及其指向的工单。领域词汇见 [CONTEXT.md](../CONTEXT.md)。

## 1. 概述

个人向的跨端 AI 电子书应用：导入本地 TXT 小说，用 AI 修复章节结构与正文内容，从文本提取人物/场景**实体卡**，确认**正典**后为段落生成风格一致的**插图**。无账号、无云、无内容合规问题。v1 = 桌面端 + web 端双端全功能；数据纯本地，双端流动靠**全书包**手动导出/导入。

## 2. 平台与架构（决策：[跨端技术选型评估](../wayfinder/tickets/001-cross-platform-stack.md)）

TypeScript monorepo（pnpm workspaces），**web 核心为第一公民**，桌面用 Tauri 2 壳复用同一前端：

| 层 | 内容 | 共享范围 |
| --- | --- | --- |
| `core/`（纯 TS，零平台依赖） | 领域模型、修复流水线编排、provider 抽象与 OpenAI-compatible 客户端、分页/锚点纯逻辑、repository 接口 + SQL schema/migrations、全书包序列化 | 桌面 + web + 未来移动，100% |
| `data-sqlite/` | SQLite driver adapter：桌面 tauri-plugin-sql（sqlx），web sqlite-wasm（OPFS-sahpool，Worker 内） | 接口共享，实现按端 |
| `ui/reader`（React + DOM/CSS） | 阅读器、分页渲染器、实体卡/插图面板 | 桌面 + web 100%；移动复用 |
| 平台壳 | Tauri Rust commands（文件读写、代理）、打包；web 为 Vite 静态站 | 不共享 |

- 备选：Electron（需 Node 生态时切换，只换 adapter）。否决：Flutter（CanvasKit 自绘无 DOM）、RN/Expo（分页器写两遍、expo-sqlite web 实验性）。
- 未来移动端 = Tauri 2 iOS/Android 只读复用。
- 存储：SQLite everywhere，同一份 schema + migrations 双端跑；图片/正文 blob 走文件系统（桌面 app data）/ OPFS（web）。

## 3. 领域模型（决策：[数据模型与全书包格式设计](../wayfinder/tickets/005-data-model-bundle.md)）

主键一律 UUIDv7；所有表带 `created_at/updated_at`；历史只追加。

- **works**: id, title, author, import_source, settings_json（每任务类型的 provider/model、信任等级、预算上限）
- **chapters**: id, work_id, idx, title, word_count, content_hash；正文按章存 blob
- **repair_runs**: id, work_id, kind, provider_id, model, 起止时间, status
- **revisions**: id, work_id, run_id?, chapter_id, kind(structure|content), payload_json（结构=边界快照；内容=补丁列表，补丁含锚点/原文/建议/类目/理由/状态）
- **entity_cards**: id, work_id, kind(character|scene|item), name, aliases, attributes_json, status(draft|canon), portrait_blob_id（定妆照）
- **illustrations**: id, work_id, prompt, provider_id, model, blob_id, status(draft|accepted), gen_meta, entity_card_ids
- **anchors**: id, work_id, chapter_id, para_index, char_offset, target_id, state(active|orphaned)
- **blobs**: id, work_id, kind, byte_size, mime, sha256, storage_key（二进制不进 SQLite 行）

**锚点**：相对位置 `{chapter_id, para_index, char_offset}`；修复重跑时用该批次内容补丁重映射，段落删除/合并则标 `orphaned` 并提供重新锚定入口。

**全书包**：`.mabk` = ZIP（manifest.json + work.json + blobs/）；v1 全量导出；导入语义 = work_id 不存在则导入 / 哈希一致则跳过或覆盖 / 不一致则覆盖或副本导入，不做字段级合并。

## 4. 功能规格

### 4.1 导入
v1 仅 TXT（UTF-8/GBK 自动检测）。导入即触发章节切分预览。

### 4.2 AI 修复（决策：[AI 修复流水线与修订模型设计](../wayfinder/tickets/004-repair-pipeline.md)）
- **章节切分**：启发式先行（正则标题模式 + 空行密度/长度统计），每个切点带置信度；仅低置信区间交 LLM 提议边界。**切分预览界面**（树状列表 + 拖拽合并/拆分）是应用前的必经环节。重跑产生新结构修订。超大单章（>2 万字）内部再切走同一流程。
- **正文清洗**：AI 输出结构化建议 `{锚点, 原文, 建议, 类目(乱码/广告/错字/其他), 理由}`，不直接改文。审核粒度 = 按类目批量 + 逐条 diff + 整章审校模式。唯一可自动应用的是无语义变化的规范化（空白/编码），默认关闭。
- **修订**：单条回滚 = 逆补丁/快照恢复；整批回滚 = 按修复批次撤销。

### 4.3 阅读器（决策：[阅读器分页与图文混排原型](../wayfinder/tickets/007-reader-prototype.md)）
CSS 多栏分页 + translateX 整页步进翻页 + Range 锚点 inline 插图。原型已浏览器实测：分页零漂移、锚点插图精确插入并重排、字号/视口变化重排正常。**实现必记的两个坑**：
1. 栏距 = 视口宽 − 栏宽，否则翻页步进漂移；
2. 插图必须 max-height 自适应栏高，否则 break-inside: avoid 溢出破坏分栏。
边角留给实现：跨栏选择、WebkitGTK 与 Chromium 渲染差异。

### 4.4 实体卡与插图链路（决策：[插图链路与确认机制设计](../wayfinder/tickets/006-illustration-pipeline.md)）
- 实体卡状态机 `draft → canon`（可降级，降级警告参考图资格失效）。正典化同时落实**定妆照**：默认 AI 生成，可上传替换。
- 单段配图：选中段落 → 提取任务判断涉及实体 → 场景描述草稿 → 生成/复用插图预览 → 插入锚点。
- 批量配图：预扫候选段落（新实体登场/场景切换/情绪高点）→ 可编辑任务清单 → 入队 → 按章节画廊接受/重生成。
- 参考图规则（对齐 research/003）：非正典不提供参考图（草稿质量）；正典场景图 = 定妆照 + 场景参考 ≤3 张，prompt 按"图1/图2"显式指代。

### 4.5 供应商与 AI 任务（决策：[文生图参考图能力调研](../wayfinder/tickets/003-image-reference-research.md) + 立场修订）
- 按任务类型（修复/提取/插图）独立配置供应商与模型；便宜模型够用的任务不用贵模型。
- 文本任务：仅 OpenAI-compatible。图像任务：OpenAI-compatible `/images/generations` 为兜底；参考图路径抽象为 `generate({prompt, references[]})` 能力接口，per-provider adapter 落地——v1 内置 **OpenAI edits 形状**与**火山方舟形状**两个 adapter。
- UI 按 adapter 声明的能力位渲染（参考图张数、组图）；不支持参考图的供应商只开放草稿质量生成。

### 4.6 任务队列
每本书一个队列；修复最小形态顺序执行；插图队列并发可配（默认 2）、暂停/恢复/取消、单项重试 ≤3 次指数退避、每本书预算上限（触顶暂停并提示）。**每完成一项即 checkpoint**，断点续跑是一等公民（见 4.7）。

### 4.7 浏览器端约束与缓解（决策：[浏览器端 AI 任务可行性](../wayfinder/tickets/002-browser-ai-feasibility.md)）
- 供应商配置必须带**连通性诊断**（预检探测，标注"浏览器可直连/需代理"）。实测：OpenRouter/硅基流动/DeepSeek/Kimi/DashScope/智谱放行；OpenAI/Anthropic/Gemini 官方端点需代理。
- **本地一键小代理**进 v1 交付：单文件 Node/Bun 脚本（~50 行，注入 CORS 头转发任意上游）；桌面端在运行时可由 Tauri Rust 侧充当代理；Cloudflare Worker 自部署作为文档方案。
- 后台 5 分钟冻结/内存压力 discard → freeze/resume 持久化、wasDiscarded 续跑、任务粒度切小。

## 5. 实现注意事项
- 修复质量评估：维护 3–5 本不同格式损坏形态的样例 TXT 回归集，切分/清洗结果快照对比。
- 存储引擎要求：WAL、事务原子（修订追加 + 锚点重映射）、web 侧 exportDb/importDb、FTS5 可选。
- 未来若做自动同步，评估 cr-sqlite（schema 现已避免单写者假设：UUID 主键、无自增身份）。

## 6. Out of scope（v1 边界）
移动端实现；EPUB 导入/导出；云同步/账号；多协议 AI 适配器；双端并发编辑的字段级合并（全书包二选一语义覆盖，自动合并留待未来新图）。
