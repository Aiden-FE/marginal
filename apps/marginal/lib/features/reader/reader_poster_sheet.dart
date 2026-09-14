import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart' show XFile;

import '../../app/poster_capture.dart';
import '../../app/share.dart';

/// 分享海报 —— 打开即预渲染 PNG（Safari 手势上下文之外无法分享异步产物），
/// 预览用真实 <img>（长按即可存储/分享），分享按钮直接使用已就绪字节。
class ReaderPosterSheet extends StatefulWidget {
  const ReaderPosterSheet({
    super.key,
    required this.workTitle,
    required this.chapterTitle,
    required this.text,
    required this.shareService,
    this.encoder = renderPosterPng,
    this.renderTimeout = const Duration(seconds: 6),
  });

  final String workTitle;
  final String chapterTitle;
  final String text;
  final ShareService shareService;
  final Future<Uint8List> Function({
    required String workTitle,
    required String chapterTitle,
    required String text,
    double pixelRatio,
  })?
  encoder;

  final Duration renderTimeout;

  @override
  State<ReaderPosterSheet> createState() => _ReaderPosterSheetState();
}

class _ReaderPosterSheetState extends State<ReaderPosterSheet> {
  Uint8List? _readyPng;
  String? _error;
  bool _sharing = false;
  Timer? _renderTimeoutTimer;

  /// Safari 上 PNG 编码可能挂起：超时给出明确错误而不是永远转圈。

  @override
  void initState() {
    super.initState();
    _render();
  }

  Future<void> _render() async {
    final encode = widget.encoder;
    if (encode == null) {
      setState(() => _error = '海报生成失败：未配置编码器');
      return;
    }
    _renderTimeoutTimer = Timer(widget.renderTimeout, () {
      if (mounted && _readyPng == null) {
        setState(() => _error = '海报生成失败：编码超时');
      }
    });
    try {
      final bytes = await encode(
        workTitle: widget.workTitle,
        chapterTitle: widget.chapterTitle,
        text: widget.text,
      );
      _renderTimeoutTimer?.cancel();
      if (!mounted || _error != null) return;
      setState(() => _readyPng = bytes);
    } catch (e) {
      _renderTimeoutTimer?.cancel();
      if (mounted) setState(() => _error = '海报生成失败：$e');
    }
  }

  @override
  void dispose() {
    _renderTimeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _shareImage() async {
    final bytes = _readyPng;
    if (bytes == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      final file = XFile.fromData(
        bytes,
        mimeType: 'image/png',
        name: 'marginal-poster.png',
      );
      final ok = await widget.shareService.shareImage(file);
      if (!mounted) return;
      if (!ok) _snack('当前环境不支持直接分享，长按海报图片可存储/分享');
    } catch (e) {
      if (mounted) _snack('分享失败：$e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final ready = _readyPng != null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Color(0xFFAD4E43)),
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: double.infinity,
                child: AspectRatio(
                  aspectRatio: 900 / 1200,
                  child: ready
                      ? Image.memory(_readyPng!, fit: BoxFit.contain)
                      : _error != null
                      ? Center(child: Text(_error!))
                      : const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
            if (ready)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '长按海报图片可存储或分享',
                  style: Theme.of(context).textTheme.bodySmall,
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
                    onPressed: ready && !_sharing ? _shareImage : null,
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
