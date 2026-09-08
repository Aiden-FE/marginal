---
id: 002
title: 小程序本地存储与核心复用边界
labels: [wayfinder:research]
status: closed
assignee: Aiden
blocked-by: []
---

## Question

v1 的存储层是 SQLite（web: sqlite-wasm/OPFS；桌面: tauri-plugin-sql），小程序两端都没有。要钉死：

1. 小程序存储原语的真实容量与语义：`wx.setStorageSync`/`wx.getStorage`（单 key 与总量上限）、`FileSystemManager`（用户目录/代码包/缓存目录的区别、200MB 传闻属实与否）、真机与开发者工具的差异。
2. WASM 在小程序的可用性（基础库版本门槛、iOS/Android 差异）——若可用，sqlite-wasm 有无机会跑在自定义 FS 上；不可用则定论「重写驱动而非移植」。
3. `packages/core`（零平台依赖的领域逻辑：切分/修复/实体/插图/锚点/队列/全书包）在小程序 npm 构建下的复用路径（小程序 npm 构建、tree-shaking、ESM/CJS 互操作坑）。
4. 二进制资产（插图、定妆照、blob）在小程序的存放方式：`FileSystemManager` 文件 vs storage base64 vs 云存储。
5. 由此给出 MiniProgramRepository 驱动的形态建议（schema 兼容 v1 的 12 张表模型，还是降级为 KV/文档模型 + 内存索引）。

产出：存储与复用边界清单 + 驱动方案建议，供 grilling 工单定稿。

## Resolution

（无人值守模式：推荐方案已采纳，可事后否决；见 research/weapp/002）

- **SQLite 不可移植**；存储 = 双层：wx.setStorage（10MB：配置/轻状态）+ USER_DATA_PATH 文件（与缓存合计 200MB：书稿/插图落点）。
- **core 复用**：`@marginal/core` 纯 TS 零平台依赖，经小程序 npm 构建直接复用（只有构建产物计入包体）。三处必须处理：ids 的 crypto.randomUUID 需 shim；TXT 的 GBK 解码需内嵌纯 JS iconv；fflate 可用但 zip 内 base64 有 4/3 膨胀。
- `packages/data` 两个 sqlite 驱动不进入小程序；**新增 WeappRepository 驱动**：表→目录、行→JSON/NDJSON 文件、启动扫目录建内存索引、写走临时文件+rename；bindata 直接存 USER_DATA_PATH 二进制文件且 image 组件直接用本地路径；.mabk 结构不变，weapp 侧用 FileSystemManager 解 zip。
- 需在书架 UI 配「容量占用 + 清插图」入口（200MB 约束）。