import 'dart:async';

/// Web 等无 dart:io 平台：使用相对路径，web 端 Repository 不会真正落盘（IndexedDB 接管）。
Future<String> defaultJsonPath({
  Future<Object> Function()? applicationSupportDirectory,
}) async {
  return '.marginal/library.json';
}
