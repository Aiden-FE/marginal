# Mobile Safari 生产验收（2026-09-17）

## 环境与交付指纹

- 设备：iPhone 17 Pro Simulator，iOS 26.5（23F77）
- 浏览器：系统 Mobile Safari / WebKit
- 生产入口：<https://marginal-app-sandy.vercel.app>
- 运行时代码提交：`a942397`（`fix: integrate EPUB exit into reader chrome`）；后续仅追加验收证据文档，不改变运行时产物
- 验收时 Vercel 代码部署：`dpl_8CKToNrmfGcVjuwTetkXagV4YJxY`，`READY / Production`，deployment metadata 的 Git SHA 与 `a942397` 一致
- `main.dart.js` SHA-256：本地 `web-dist` 与生产均为 `3cc0bf45159a82c372a6f26284fc1adbce8b94a8e1d2867e8da0dabe6af6d094`
- 自动门禁：`flutter analyze` 无问题；`flutter test` 155/155 通过；`flutter build web --release --no-wasm-dry-run` 成功

## 环境准备说明

Mobile Safari 的系统 Files remote view 可通过 XCUITest 打开，且真实 framebuffer 已确认 `Marginal-CSS-验收.epub` 位于“我的 iPhone”；但该 remote view 的 AX 文件选择动作在自动化进程间不稳定。为使 Reader 路径可重复验收，临时向同一生产 origin 部署一次性 `/qa-seed.html`，写入与 EPUB 导入产物一致的 Work/Chapter/XHTML/CSS/Blob/Anchor 快照。写入后立即把正式 `web-dist` 重新部署到生产别名并完成 SHA-256 精确匹配；临时 deployment、失败 deployment 与误建项目已删除，生产不存在测试入口。

## 验收结果

| # | 验收点 | 结果 | 证据 |
|---|---|---|---|
| 1 | 首页导入入口；书库 / AI / 我的三枚矢量图标；Safari 工具栏不遮挡导航 | PASS | [01-library-tabs-import.png](01-library-tabs-import.png) |
| 2 | 正式生产书库可读取 EPUB 等价数据并显示可点击书稿卡、来源与进度 | PASS | [02-library-epub-work.png](02-library-epub-work.png) |
| 3 | Reader 沉浸 chrome 唤醒后：返回、书签、主题、目录、摘录、自动阅读、AI、排版均可见 | PASS | [03-reader-chrome.png](03-reader-chrome.png) |
| 4 | 阅读设置完整显示“原版排版”开关，未被 Safari 工具栏裁切 | PASS | [04-layout-original-toggle.png](04-layout-original-toggle.png) |
| 5 | 原版排版开关值为 1；EPUB CSS（淡黄背景、深红标题/下划线、红色斜体圆角边框）生效；顶栏“语义版”可见 | PASS | [05-original-css-semantic-exit.png](05-original-css-semantic-exit.png) |

## 交互断言

最终 XCUITest `testFinalProductionOriginalLayout()` 在生产版硬断言通过：

1. 刷新生产页面后同源书稿仍存在；
2. 书库卡进入 Reader；
3. “排版”打开设置面板；
4. “原版排版” Switch 的 value 为 `1`；
5. 关闭设置后顶栏 `buttons["语义版"]` 存在；
6. 最终 framebuffer 经独立视觉 gate 判定为 PASS。
