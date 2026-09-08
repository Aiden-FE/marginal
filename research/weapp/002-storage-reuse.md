---
ticket: weapp/002
title: 小程序本地存储与核心复用边界
date: 2026-09-08
assignee: Aiden
---

# 存储与复用边界（research/weapp/002）

## 0. 结论速览

**SQLite 不可移植（无 OPFS、无证实 WASM 通道）；小程序存储 = 双层：`wx.setStorage`（10MB，配置/轻状态）+ `USER_DATA_PATH` 文件（与缓存合计 200MB，书稿正文/插图的落点）。推荐为 core 增加第四个 Repository 驱动：`WeappRepository`——文件即记录（按表分目录 + 每行一 JSON 文件或每表一 NDJSON 追加文件），内存索引；schema 语义与 v1 十二表模型对齐但物理形态降级为 KV/文档。**

## 1. 官方存储事实

- `wx.setStorageSync`：总量上限 **10MB**（getStorageInfoSync 的 limitSize 官方口径）；单 key 上限官方页未标注（社区口径 1MB，prototype 实测）。
- 文件系统四类（来源：file-system 指南）：
  - 代码包文件：只读，改需发版。
  - 本地临时文件：运行期最多 4GB，退出清理性（>2GB 按最近使用清理）。
  - 本地缓存文件（saveFile）：不可自定义目录名，与用户文件**合计 200MB**。
  - **本地用户文件 `wx.env.USER_DATA_PATH`：唯一可自由读写目录，与缓存合计 200MB**。
- 隔离：按 小程序+用户 双维度隔离；真机路径协议 wxfile://，工具为 http://——不要硬编码完整路径。
- 容量判断：一本书 TXT 1–5MB、插图 JPEG 每张 100–500KB → 200MB 约可容纳 20–60 本书 + 数百插图，个人工具够用，但需配「容量占用展示 + 清理插图」入口。

## 2. core 复用边界（来源：npm 指南）

- npm 包须纯 JS、有 main 入口、无 node 内置依赖/window/Function 动态构造；`@marginal/core` 为纯 TS 零平台依赖，**领域逻辑（切分/修复建议/实体/插图/锚点/队列/全书包）可直接复用**，构建进 `miniprogram_npm`（只有构建产物计入包体）。
- 三个已知移植点（实现工单必须处理）：
  1. `ids.ts` 若用 crypto.randomUUID → 小程序无 crypto 全局，需 shim（Math.random+时间戳的 uuidv7 变体）。
  2. TXT 导入的 GBK 解码：小程序无 TextDecoder，需内嵌纯 JS iconv（如 iconv-lite 精简版）。
  3. fflate（.mabk ZIP）纯 JS 可用，但 zip 里 blob 以 base64 存储的体积膨胀（×4/3）要在导入导出时处理。
- `packages/data` 的 sqlite 两个驱动与 web/桌面强绑定，**不进入小程序**；新增 weapp 驱动。

## 3. WeappRepository 形态建议（供 grilling 定稿）

- 表 → 目录（`works/ chapters/ chapter_texts/ revisions/ entity_cards/ illustrations/ bindata/ …`）；行 → 单文件（JSON）或每表 NDJSON。
- 启动时扫目录建内存索引（列表页零等待）；写走「临时文件 + rename」防半写。
- bindata（插图/定妆照）直接存 USER_DATA_PATH 二进制文件，DB 记录只存路径——比 base64 进 storage 省 4/3 空间且 image 组件可直接用本地路径。
- .mabk 兼容：bundle 结构不变，读写在 weapp 侧用 FileSystemManager 解 zip。

## 来源（访问于 2026-09-08）

- 文件系统指南：https://developers.weixin.qq.com/miniprogram/dev/framework/ability/file-system.html
- Storage：https://developers.weixin.qq.com/miniprogram/dev/api/storage/wx.getStorageInfoSync.html
- npm 构建：https://developers.weixin.qq.com/miniprogram/dev/devtools/npm.html
