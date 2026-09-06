---
id: 005
title: 数据模型与全书包格式设计
labels: [wayfinder:grilling]
status: closed
assignee: Aiden
blocked-by: [004]
---

## Question

设计领域模型落地与双端数据流动格式，受既定约束：v1 纯本地、模型可同步、插图锚点必须是相对位置（为未来 EPUB 导出留路）、双端靠"全书包"手动导出/导入。

需要钉定的决策：

1. 书稿 / 章节 / 修订 / 实体卡 / 插图 / 锚点 的字段级模型与关系（含正典状态、参考图引用）。
2. 锚点的相对位置表示法（段落索引 + 字符偏移？）及其对修订重排的稳定性策略。
3. 存储分层：文本/图片/blob 与结构化元数据各自怎么存（存储引擎选型在雾区，本工单产出对引擎的要求清单即可）。
4. 全书包：单文件自包含的打包格式、版本字段、全量还是增量、导入合并语义。

产出：数据模型规格章节 + 对存储引擎的需求清单（喂给雾区毕业）。

## Resolution

（无人值守模式：推荐答案经授权采纳，可事后否决。）

**1. 字段级模型**（主键一律 UUIDv7——时间有序、无自增身份依赖，为未来同步/合并留路；所有表带 `created_at`/`updated_at`）：

- **works**: id, title, author, import_source(文件名/哈希), settings_json(每任务类型的 provider/model 配置、信任等级、预算上限)
- **chapters**: id, work_id, idx, title, word_count, content_hash; 正文按章存 blob 表（增量友好）
- **repair_runs**: id, work_id, kind(结构/内容), provider_id, model, started_at, finished_at, status
- **revisions**: id, work_id, run_id nullable(手动改动无批次), chapter_id, kind(structure|content), payload_json——结构修订存切分前后边界快照；内容修订存补丁列表 `[{anchor:{para,offset}, original, replacement, category, reason, status(accepted|rejected|undone)}]`；可逆（逆补丁/快照恢复），历史只追加
- **entity_cards**: id, work_id, kind(character|scene|item), name, aliases_json, attributes_json(外貌/性格/氛围等结构化描述), status(draft|canon), portrait_blob_id nullable(定妆照)
- **illustrations**: id, work_id, prompt, provider_id, model, blob_id, status(draft|accepted), gen_meta_json(seed/成本/参考图 blob ids), entity_card_ids_json
- **anchors**: id, work_id, chapter_id, para_index, char_offset, target_type(illustration), target_id, state(active|orphaned)——重映射规则见工单 006 决议
- **blobs**: id, work_id, kind(image|text), byte_size, mime, sha256, storage_key（图片二进制不进 SQLite 行，走文件/OPFS，行里只存元数据）

**2. 锚点表示**：`{chapter_id, para_index, char_offset}` 相对位置；稳定性策略 = 004/006 已定的补丁重映射 + orphaned 兜底。

**3. 存储分层与引擎要求清单**（喂给已定的 SQLite everywhere 选型，research/001）：
- 结构化元数据 → SQLite（桌面 sqlx / web sqlite-wasm OPFS-sahpool，Worker 内）
- 图片与章正文 blob → 文件系统（桌面 app data 目录）/ OPFS（web）
- 引擎要求：① 支持 WAL 与单写者 ② 可靠的事务（修订追加 + 锚点重映射须原子）③ web 侧支持 exportDb/importDb ④ FTS5 可选（全文搜索，非 v1 必需）

**4. 全书包（Book Bundle）**：
- 格式：`.mabk` = ZIP：`manifest.json`（format_version、app_version、exported_at、work_id、content_hash）、`work.json`（上述全部表的 JSON 导出）、`blobs/`（按 storage_key 存图片与正文）
- v1 **全量导出**（不做增量——个人工具单本体积可控，增量复杂度不值）；版本字段从 1 开始
- 导入语义：work_id 不存在 → 直接导入；已存在且 content_hash 一致 → 提示跳过/覆盖；不一致 → **二选一：覆盖 或 作为副本导入（新 work_id）**，v1 不做字段级合并（双端并发编辑同一本的合并是已知缺口，留 fog）
