import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart' show XFile;

import '../../app/poster.dart';
import '../../app/share.dart';

/// 分享海报预览 —— RepaintBoundary 捕获 ParagraphPosterPainter 画布，
/// capture 后经 ShareService 分享 PNG；Web 降级为仅预览 + 提示。
class ReaderPosterSheet extends StatefulWidget {
  const ReaderPosterSheet({
    super.key,
    required this.workTitle,
    required this.chapterTitle,
    required this.text,
    required this.shareService,
  });

  final String workTitle;
  final String chapterTitle;
  final String text;
  final ShareService shareService;

  @override
  State<ReaderPosterSheet> createState() => _ReaderPosterSheetState();
}

class _ReaderPosterSheetState extends State<ReaderPosterSheet> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _sharing = false;

  Future<void> _shareImage() async {
    setState(() => _sharing = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (!mounted) return;
      if (data == null) {
        _snack('海报生成失败，请重试');
        return;
      }
      final file = XFile.fromData(
        data.buffer.asUint8List(),
        mimeType: 'image/png',
        name: 'marginal-poster.png',
      );
      final ok = await widget.shareService.shareImage(file);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop();
      } else {
        _snack('当前环境不支持直接分享图片，可长按海报截图保存');
      }
    } catch (e) {
      if (mounted) _snack('海报生成失败：$e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final lines = wrapPosterText(widget.text);
    final height = (520 + lines.length * 62).clamp(1200, 2400).toDouble();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 900 / height,
                child: RepaintBoundary(
                  key: _boundaryKey,
                  child: CustomPaint(
                    painter: ParagraphPosterPainter(
                      workTitle: widget.workTitle,
                      chapterTitle: widget.chapterTitle,
                      text: widget.text,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _sharing ? null : _shareImage,
                    icon: _sharing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share, size: 18),
                    label: const Text('分享图片'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
