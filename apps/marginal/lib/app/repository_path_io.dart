import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 解析原生平台本地 JSON 库文件的物理路径：Application Support/marginal/library.json。
///
/// 在 iOS 沙箱内，`getApplicationSupportDirectory` 对应 `NSApplicationSupportDirectory`，
/// 系统会保证该目录存在并对当前进程可写；避免把点目录作为路径（曾触发
/// `PathAccessException: Operation not permitted`）。
Future<String> defaultJsonPath({
  Future<Directory> Function()? applicationSupportDirectory,
}) async {
  final support =
      await (applicationSupportDirectory ?? getApplicationSupportDirectory)();
  return '${support.path}${Platform.pathSeparator}marginal${Platform.pathSeparator}library.json';
}
