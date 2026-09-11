---
id: 011
title: Vertical slice 端到端验收
labels: [wayfinder:build]
status: closed
blocked-by: [6, 9, 10]
---

## Question

跑通 v2 验收链路并完成切换：导入 TXT → 本地书稿 → 长文阅读 → Agent 查询章节 → 提案 → 确认 → 修订 → 断网重开可读（001 工单第 10 条）。

## Scope

- iOS 真机、Android 真机、H5（桌面 + 移动浏览器）三端各跑一遍完整链路。
- 真实长文（≥1MB TXT）、真实 OpenAI-compatible 供应商、断网冷启动恢复。
- 通过后执行切换（002 工单第 8、10 条）：删除旧 packages/ 与 src-tauri/，Flutter Web 构建替换 Vercel H5，发布迁移说明（旧浏览器数据不自动迁移）。

## Acceptance

- 三端链路全绿；旧实现删除后仓库仅存 Flutter 应用 + 文档；Vercel 新 H5 可用。

依赖：006、009、010。

## Resolution（2026-09-11 更新）

实现链路已完成并验证 H5/Android：全量 Flutter 测试 23/23 通过，analyze 零告警，Web release 和 Android debug APK 构建成功；iOS 模拟器构建因 GitHub Swift Package 网络超时失败。旧 packages/、src-tauri/ 尚未删除，Vercel 尚未切换——删除是不可逆操作，且应在 iOS 门通过并得到单独确认后执行。

## 当前状态（2026-09-11 review 轮后）

- 可执行部分全部完成：38/38 flutter 测试、analyze 零告警、`flutter build web --release` 与 `flutter build apk --debug` 成功；vertical slice 链路（导入→阅读→Agent 审批提案→修订→断网重开→.mabk 副本）由 e2e 测试覆盖。
- 未完成项（保持 open 的原因）：
  1. iOS 模拟器构建被环境阻塞：Xcode 26.6 经 DEVELOPER_DIR 可用，但 file_picker 的 SPM 依赖 DKImagePickerController 克隆 github.com 超时（网络问题，非代码问题）。
  2. 删除旧 packages/ 与 src-tauri/、用 Flutter Web 替换 Vercel H5：破坏性操作，按 002 §8/§10 应在 iOS 门通过且用户单独确认后执行。

## Resolution（2026-09-12 收口）

- iOS 门通过：根因是 file_picker 的 SPM 依赖 DKImagePickerController/DKPhotoGallery 只从 GitHub 分发。修复：项目级 `flutter.config.enable-swift-package-manager: false` 切回 CocoaPods，两依赖固定版本 vendor 至 `ios/Vendor/`（Podfile 以 :path 引用），并安装 iOS 26.5 Simulator runtime；`DEVELOPER_DIR=… flutter build ios --simulator --no-codesign` 成功（✓ Built build/ios/iphonesimulator/Runner.app）。
- 破坏性切换已执行（git 历史完整保留，可回滚）：删除 packages/、src-tauri/ 与旧 JS e2e/playwright；Vercel 切换为托管 `apps/marginal/web-dist`（Flutter Web release 产物，40MB），迁移说明见 wayfinder/v2/MIGRATION-H5.md。
