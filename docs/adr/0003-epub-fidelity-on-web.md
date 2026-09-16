# ADR 0003: H5 使用沙箱 iframe 保留 EPUB 原版排版

- 状态：Accepted
- 日期：2026-09-17

## 背景

EPUB 的 XHTML、CSS、字体、SVG 与固定版式 viewport 在抽取为纯文本后不可恢复。Flutter 的 Text/ListView 阅读器能提供稳定的窗口化语义阅读，但不能解释完整的浏览器 CSS，也不能复现 fixed-layout EPUB。

目标平台包含 H5、iOS 和 Android。当前项目没有跨三端一致的 EPUB 排版引擎；把 WebView 作为唯一阅读器会破坏 H5，也会绕开现有的段落收藏、窗口化 I/O 和进度语义。

## 决策

1. 导入 EPUB 时，spine 中的每个 XHTML 文档以及 CSS、图片、SVG、字体资源按压缩包内部路径原字节保存为 Blob；章节通过 `epub-source` Anchor 指向对应 XHTML。
2. 语义正文继续作为默认阅读模式，保留窗口化 I/O、段落交互、收藏、自动阅读和跨平台一致性。
3. H5 在“原版排版”模式中，用 `HtmlElementView.fromTagName` 创建 sandbox iframe，并通过 `srcdoc` 渲染原 XHTML/CSS。资源引用和 CSS `url(...)` 在本地递归改写为 data URI，因此不依赖外部网络。
4. iframe 不授予任何 sandbox 权限；`srcdoc` 注入 CSP：禁止脚本和外部资源，只允许 data URI 图片/字体/CSS 与内联样式。
5. 原版排版模式暂停自动阅读、段落摘录和进度拖动，并始终提供“语义版”退出按钮。
6. 非 Web 目标明确降级为语义正文；没有文本的 fixed-layout spine 页显示“请在 Web 版查看”提示，但原始资源仍完整保留，不静默丢页。

## 结果

- H5 可使用浏览器排版引擎解释 EPUB 的 CSS 和 fixed-layout viewport，并离线加载包内资源。
- 原版模式与语义模式的能力边界对用户可见；不宣称 iOS/Android 像素级保真。
- 每个章节只在用户进入原版模式时加载原始资源；普通切章只做轻量 Anchor/Blob 可用性检查。
- EPUB 脚本、远程请求和宿主页面访问被 sandbox + CSP 阻断。

## 验证

- 导入契约测试覆盖 XHTML/CSS 资源与 `epub-source` Anchor。
- srcdoc 测试覆盖 fixed-layout viewport、CSS、背景图和字体的递归 data URI 改写。
- VM widget test 覆盖非 Web 语义正文、插图与隐藏原版开关的降级行为。
- Flutter Web release 构建验证浏览器条件导入与 `HtmlElementView` API。
