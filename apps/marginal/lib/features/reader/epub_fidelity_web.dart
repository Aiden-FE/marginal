import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

const bool epubFidelitySupported = true;

/// sandbox 与 srcdoc 内的 CSP 一同隔离 EPUB 内容；不授予脚本或宿主权限。
class ReaderEpubFidelityView extends StatelessWidget {
  const ReaderEpubFidelityView({super.key, required this.srcdoc});
  final String srcdoc;

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (element) {
      final frame = element as web.HTMLIFrameElement;
      frame
        ..setAttribute('sandbox', '')
        ..srcdoc = srcdoc.toJS
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = 'transparent';
    },
  );
}
