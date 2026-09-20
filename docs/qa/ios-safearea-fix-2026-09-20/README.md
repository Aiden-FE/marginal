# iOS SafeArea 修复验收（2026-09-20）

## 复现
修复前 iOS Mobile Safari 中 Reader 顶栏会陷入状态栏/Dynamic Island；上一轮验收图 [03-reader-chrome.png](../safari-production-2026-09-17/03-reader-chrome.png) 中可看到书签/主题按钮与 iOS 时间/信号重叠。

## 修复
- 提交：`a095080 fix: keep Reader and Library chrome below iOS safe area`
- Reader 顶栏 `SafeArea(top: true, bottom: false, minimum: topSafeMinimum)`，Web 端 `MediaQuery.viewPaddingOf(context).top == 0` 时按 44px 兜底；
- Reader 底栏 `SafeArea(top: false, bottom: true, minimum: 24)` 避开 home indicator；
- LibraryPage 隐藏 AppBar 时显式 `SafeArea(top: true, bottom: false)`；
- AI / 我的 / 其它页已用 `AppBar`，由 Material 处理 iOS 顶部 inset。

## 复验

- 生产入口：<https://marginal-app-sandy.vercel.app>
- 设备：iPhone 17 Pro Simulator，iOS 26.5（23F77）
- 工具链：`flutter analyze` 无问题；`flutter test` 155/155；`flutter build web --release` 成功；`flutter build ios --release` 成功（未提交 Xcode 自动改动的 `project.pbxproj`/`Main.storyboard`）。
- `main.dart.js` SHA-256：本地与生产均匹配（修复后 web 仍同步生效，避免 MediaQuery padding 不可知时与 native shell 行为差异）。

## 验收结果

| # | 验收点 | 结果 | 证据 |
|---|---|---|---|
| 1 | 修复前 Reader 顶栏与 iOS 状态栏重叠 | （基线） | [03-reader-chrome.png](../safari-production-2026-09-17/03-reader-chrome.png) |
| 2 | 修复后 Reader 顶栏整体下移至 iOS 状态栏下方，返回/书名/章节/书签/主题按钮完整可见，底栏/工具栏无重叠 | PASS | [12-reader-top-chrome-after-fix.png](12-reader-top-chrome-after-fix.png) |

视觉 gate 综合评价：iOS 状态栏与 Reader 顶栏已分离，顶栏各控件完整可读，底部 Reader 工具栏与 Safari 工具栏无重叠。
