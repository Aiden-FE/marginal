# iOS 原生导入路径修复验收（2026-09-20）

## 用户问题

iOS 应用导入小说失败：

```text
导入失败: PathAccessException: Creation failed, path = '.marginal' (OS Error: Operation not permitted, errno = 1)
```

## 根因

`lib/app/repository_boot.dart` 在非 Web 平台硬编码相对路径 `.marginal/library.json`。iOS App 进程的当前工作目录不是可写用户数据目录，首次 JSON 原子写入需要创建 `.marginal`，因此触发 `Operation not permitted`。

## 修复

- Web 继续使用 IndexedDB，不改变 H5 持久化路径。
- iOS/Android/macOS/Linux/Windows 通过 `path_provider.getApplicationSupportDirectory()` 获取系统应用支持目录。
- 原生库路径变为：

```text
<Application Support>/marginal/library.json
```

- `Application Support` 在 iOS 映射到 `NSApplicationSupportDirectory`，系统保证该目录可供当前 App 使用。
- 保留 `repository_path_stub.dart` 条件导入，避免 Web 编译引入 `dart:io`。
- 增加 `repository_path_test.dart`，断言原生路径不再以 `.marginal` 相对目录开头。

## 真实 iOS 验证

- Bundle ID：`com.aiden.marginal`
- 设备：iPhone 17 Pro Simulator / iOS 26.5（23F77）
- `flutter build ios --release --no-codesign`：成功
- 安装并启动真实 Runner：成功，无 `PathAccessException`
- 直接检查 App 沙箱：

```text
<APP>/Library/Application Support/marginal/library.json
```

文件成功创建并可重开读取；随后通过应用真实删除书稿操作再次触发 JSON 原子写入，文件仍存在（211 bytes），未回到 `.marginal` 工作目录。

证据截图：[10-ios-appsupport-write-result.png](10-ios-appsupport-write-result.png)

截图显示真实 iOS Runner 的书稿删除 SnackBar「已删除书稿」，说明应用已经完成写回操作；同一模拟器沙箱检查确认 `Application Support/marginal/library.json` 存在。

## 代码与回归

- `repository_boot.dart`：原生仓库改为 `await path.defaultJsonPath()`。
- `repository_path_io.dart`：使用 `getApplicationSupportDirectory()`。
- `repository_path_stub.dart`：Web 条件导入 stub。
- `flutter analyze`：无问题。
- `flutter test`：**156/156 通过**。
- `flutter build ios --release --no-codesign`：成功。
- `flutter build web --release --no-wasm-dry-run`：成功。
