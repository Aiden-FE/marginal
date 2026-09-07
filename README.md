# Marginal

个人向的跨端 AI 电子书应用：导入本地 TXT 小说 → AI 修复章节结构与正文 → 提取人物/场景实体卡 → 正典后为段落生成风格一致的插图。

产品与技术规格见 [docs/SPEC.md](docs/SPEC.md)；决策过程见 [wayfinder/map.md](wayfinder/map.md)；领域词汇见 [CONTEXT.md](CONTEXT.md)。

## 快速开始

```bash
pnpm install
pnpm dev            # web 应用（http://localhost:5199）
pnpm test           # core 逻辑冒烟测试（15 项）
pnpm build          # 生产构建
node tools/gen-sample.mjs   # 生成一本"脏"样本网文（含广告/乱码/错字）
node tools/proxy.mjs <上游 base URL> [端口]   # 需代理的供应商用
pnpm tauri build    # 桌面端（需 Rust：curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal）
open src-tauri/target/release/bundle/macos/Marginal.app
```

书架上的 **🧪 导入示例书** 可一键载入样本，配合内置**演示模式供应商**（无需 API key）即可端到端体验修复/提取/插图全流程。

## 架构（spec §2）

```
packages/
  core/    纯 TS 零平台依赖：领域模型、章节切分、修复流水线、供应商抽象
           （OpenAI-compatible + 图像 adapter：OpenAI edits 形状 / 火山方舟形状）、
           任务队列、全书包(.mabk) 序列化、Repository 接口
  data/    存储引擎：SQLite WASM(OPFS-sahpool, Worker) 优先，IndexedDB 同接口降级
  app/     Vite + React web 应用（阅读器/导入/修复审核/实体卡/插图/设置/队列）
tools/     本地 CORS 代理、样本生成
src-tauri/ 桌面壳脚手架（见下）
```

## 实现状态（v0.1，对应 spec v1 的实现进度）

| 功能 | 状态 |
| --- | --- |
| TXT 导入（UTF-8/GBK 检测）+ 切分预览（合并/拆分） | ✅ 已验证 |
| 章节切分启发式（4 类标题模式 + 统计兜底 + 置信度） | ✅ 单测通过 |
| LLM 低置信边界复核 / 超大章内部再切分 | ✅ 已实现（真实供应商下生效） |
| 正文清洗建议 + diff 审核（逐条/按类目批量） | ✅ 已验证 |
| 修订只追加 + 内容修订回滚（逆补丁） | ✅ 单测通过 |
| 阅读器：CSS 多栏分页/翻页/字号/主题/段落锚点插图 | ✅ 已验证 |
| 实体卡：AI 提取 → 正典 → 定妆照（生成/上传） | ✅ 已验证 |
| 段落配图 + 批量预扫入队（并发/暂停/重试/预算） | ✅ 已验证 |
| 供应商连通性诊断 + 本地 CORS 代理脚本 | ✅ 已实现 |
| 全书包 .mabk 导出/导入（覆盖或副本） | ✅ 单测往返通过 |
| 存储引擎 | ✅ IndexedDB 已验证；SQLite WASM/OPFS 已实现，在不支持的 WebView 中自动降级（代码保留，`?engine=sqlite` 可诊断）。桌面 WKWebView 不支持 OPFS，原生 SQLite 需后续接 tauri-plugin-sql |
| 桌面端（Tauri 2 壳） | ✅ 已实现并编译：`pnpm tauri build` 产出 [Marginal.app](src-tauri/target/release/bundle/macos/)，真机启动验证通过（导入/切分/阅读全流程）；DMG 打包需 AppleScript 权限，`bundle.targets` 暂为 `["app"]` |
| 移动端 / EPUB / 云同步 / 字段级合并 | ❌ spec 划为 Out of scope |

> 已知缺口：结构修订的 UI 回滚（以重跑替代，见工单 004）；结构修订回滚模型已支持快照恢复。
