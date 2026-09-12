import 'dart:async';

import 'package:share_plus/share_plus.dart';

/// 分享能力接口 —— 隔离 share_plus，便于注入 fake 做测试。
///
/// 返回 `true` 表示系统分享流程已完成；`false` 表示当前环境不支持
/// 或用户取消了分享，调用方据此降级（复制 / 长按图片存储 + SnackBar 提示）。
abstract class ShareService {
  Future<bool> shareText(String text);
  Future<bool> shareImage(XFile file);
}

/// 生产实现：封装 share_plus v12 的 `SharePlus.instance.share`。
///
/// [timeout] 兜底：iOS Safari 上 navigator.share 被拒绝时 promise 可能
/// 永不返回，超时后按“不支持”处理，UI 不会卡在 loading。
class SharePlusService implements ShareService {
  const SharePlusService({this.timeout = const Duration(seconds: 10)});

  final Duration timeout;

  @override
  Future<bool> shareText(String text) async {
    if (text.trim().isEmpty) return false;
    try {
      final result = await SharePlus.instance
          .share(ShareParams(text: text))
          .timeout(timeout);
      return result.status == ShareResultStatus.success;
    } on TimeoutException {
      return false;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> shareImage(XFile file) async {
    try {
      // iOS Safari 支持 Web Share Level 2（带文件），失败再由调用方降级。
      final result = await SharePlus.instance
          .share(ShareParams(files: [file]))
          .timeout(timeout);
      return result.status == ShareResultStatus.success;
    } on TimeoutException {
      return false;
    } on Object {
      return false;
    }
  }
}

/// 测试 fake：记录调用，可控制成功与否。
class FakeShareService implements ShareService {
  FakeShareService({this.succeed = true});

  bool succeed;
  final List<String> texts = [];
  final List<XFile> files = [];

  @override
  Future<bool> shareText(String text) async {
    texts.add(text);
    return succeed;
  }

  @override
  Future<bool> shareImage(XFile file) async {
    files.add(file);
    return succeed;
  }
}
