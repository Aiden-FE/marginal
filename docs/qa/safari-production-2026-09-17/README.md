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

先通过一次性同源 `/qa-seed.html` 建立 Reader 可达性夹具，用于验证最初的导入入口、书库、Reader chrome 与原版排版 UI；该临时页面部署后已立即恢复正式 `web-dist`，临时 deployment、失败 deployment 与误建项目均已删除，生产不存在测试入口。

随后补做了用户要求的真实端到端路径：在 iOS Files 的“我的 iPhone”中准备 `Safari-Real-Import-0405.epub`，通过真实 UIDocumentPicker 选择该文件，生产应用完成解析与 IndexedDB 持久化；书库出现全新卡片 `Safari-Real-Import-0405`（来源 `Safari-Real-Import-0405.epub`，进度 0%），与此前的 QA fixture 卡片独立存在。后续原版 CSS 与“语义版”退出验证均使用这本真实导入的 EPUB。

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

## 真实文件导入与语义版退出（补充验收）

| # | 验收点 | 结果 | 证据 |
|---|---|---|---|
| 6 | iOS Files 真实选择器中的 `Safari-Real-Import-0405.epub` Cell 被选中；XCUITest 使用精确 Cell identifier `Safari-Real-Import-0405.epub, epub` | PASS（AX 精确匹配；图标视图文件名视觉截断） | [06-real-files-cell.png](06-real-files-cell.png) |
| 7 | 文件经生产应用真实导入并入库：新书稿卡 `Safari-Real-Import-0405`、来源 `.epub`、进度 0%，与 QA fixture 卡片区分 | PASS | [07-real-imported-library.png](07-real-imported-library.png) |
| 8 | 真实导入书稿启用原版排版：浅蓝 CSS 背景、蓝色标题样式，顶栏“语义版”可见 | PASS | [08-real-original-css.png](08-real-original-css.png) |
| 9 | 点击顶栏“语义版”后退出原版 iframe，恢复默认语义阅读（米纸背景、黑色语义正文） | PASS | [10-real-semantic-restored.png](10-real-semantic-restored.png) |

完整 1fps 录像接触表：[29-exit-semantic-contact-sheet.png](29-exit-semantic-contact-sheet.png)；成功测试源码保存在 [RealImportExitXCUITest.swift.txt](RealImportExitXCUITest.swift.txt)。最终 XCUITest 硬断言通过：原版排版 Switch value=`1`、`buttons["语义版"]` 存在、点击后 `staticTexts["真实文件导入成功"]` 出现。
