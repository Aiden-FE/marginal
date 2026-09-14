import 'package:flutter/material.dart';

/// 段落交互 action sheet —— 收藏 / 复制 / 分享海报 / AI 插图。
///
/// 点击任意动作先收起面板，再由 ReaderPage 执行回调。
class ReaderParagraphSheet extends StatelessWidget {
  const ReaderParagraphSheet({
    super.key,
    required this.paragraph,
    required this.isFavorite,
    this.onToggleFavorite,
    this.onCopy,
    this.onPoster,
    this.onIllustrate,
  });

  final String paragraph;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onCopy;
  final VoidCallback? onPoster;
  final VoidCallback? onIllustrate;

  static const _gold = Color(0xFFD9A13C);

  void _run(BuildContext context, VoidCallback? action) {
    Navigator.of(context).pop();
    if (action != null) {
      Future<void>.delayed(const Duration(milliseconds: 260), action);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                paragraph,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            ListTile(
              key: const Key('action-favorite'),
              leading: Icon(
                isFavorite ? Icons.star : Icons.star_border,
                color: isFavorite ? _gold : null,
              ),
              title: Text(isFavorite ? '取消收藏' : '收藏段落'),
              onTap: () => _run(context, onToggleFavorite),
            ),
            ListTile(
              key: const Key('action-copy'),
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text('复制'),
              onTap: () => _run(context, onCopy),
            ),
            ListTile(
              key: const Key('action-poster'),
              leading: const Icon(Icons.photo_outlined),
              title: const Text('生成分享海报'),
              onTap: () => _run(context, onPoster),
            ),
            ListTile(
              key: const Key('action-illustrate'),
              enabled: onIllustrate != null,
              leading: const Icon(Icons.auto_awesome),
              title: const Text('AI 插图'),
              subtitle: onIllustrate == null ? const Text('请先配置 AI 供应商') : null,
              onTap: onIllustrate == null
                  ? null
                  : () => _run(context, onIllustrate),
            ),
          ],
        ),
      ),
    );
  }
}
