import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// 分享能力接口 —— 隔离 share_plus，便于注入 fake 做测试。
///
/// 返回 `true` 表示系统分享流程已完成；`false` 表示当前环境不支持
/// （如 Web）或用户取消了分享，调用方据此降级（复制 + SnackBar 提示）。
abstract class ShareService {
  Future<bool> shareText(String text);
  Future<bool> shareImage(XFile file);
}

/// 生产实现：封装 share_plus v12 的 `SharePlus.instance.share`。
class SharePlusService implements ShareService {
  const SharePlusService();

  @override
  Future<bool> shareText(String text) async {
    if (kIsWeb || text.trim().isEmpty) return false;
    final result = await SharePlus.instance.share(ShareParams(text: text));
    return result.status == ShareResultStatus.success;
  }

  @override
  Future<bool> shareImage(XFile file) async {
    // Web 无法走系统分享面板分享本地文件：降级为调用方展示预览 + 提示。
    if (kIsWeb) return false;
    final result = await SharePlus.instance.share(ShareParams(files: [file]));
    return result.status == ShareResultStatus.success;
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
