import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/repository.dart';
import '../../core/types.dart';
import 'epub_fidelity_stub.dart'
    if (dart.library.js_interop) 'epub_fidelity_web.dart'
    as impl;

export 'epub_fidelity_stub.dart'
    if (dart.library.js_interop) 'epub_fidelity_web.dart'
    show ReaderEpubFidelityView;

/// 一个章节的原版排版渲染输入：原始 XHTML 与其引用的全部 EPUB 资源。
@immutable
class EpubFidelityDoc {
  const EpubFidelityDoc({
    required this.path,
    required this.xhtml,
    required this.resources,
  });
  final String path;
  final String xhtml;

  /// 归一化压缩包内路径 → 原始资源字节（CSS/图片/字体）。
  final Map<String, Uint8List> resources;
}

/// 是否处于支持 DOM 的浏览器目标。非浏览器目标（iOS/Android/桌面/测试 VM）
/// 没有平台视图渲染 XHTML，原版排版不可用，阅读器必须降级回语义文本模式。
bool get epubFidelitySupported => impl.epubFidelitySupported;

/// 组装 iframe srcdoc：移除 base/meta refresh，把包内 CSS/图片/字体改写为
/// data: URI（保留 #fragment），外部协议地址一律替换为占位，注入禁止脚本、
/// 表单与外部网络的 CSP，并保留原文档的行内样式。
String epubFidelitySrcdoc(EpubFidelityDoc doc) {
  final directory = _directoryOf(doc.path);
  final sanitized = doc.xhtml
      .replaceAll(RegExp(r'<base\b[^>]*>', caseSensitive: false), '')
      .replaceAll(
        RegExp(
          r'''<meta\b[^>]*http-equiv=["']?refresh["']?[^>]*>''',
          caseSensitive: false,
        ),
        '',
      );
  final rewritten = sanitized.replaceAllMapped(
    RegExp(r'''(src|href|xlink:href)=["']([^"']+)["']'''),
    (match) {
      final attr = match.group(1)!;
      final raw = match.group(2)!;
      if (raw.startsWith('data:')) return match[0]!;
      final hashIndex = raw.indexOf('#');
      final fragment = hashIndex >= 0 ? raw.substring(hashIndex) : '';
      final path = hashIndex >= 0 ? raw.substring(0, hashIndex) : raw;
      if (path.isEmpty) return match[0]!;
      if (_isBlockedPath(path)) return '$attr="#"';
      final key = _normalizePath(directory, Uri.decodeComponent(path));
      final body = doc.resources[key];
      if (body == null) return match[0]!;
      return '$attr="${_dataUri(key, body, doc.resources)}$fragment"';
    },
  );
  const csp =
      '<meta http-equiv="Content-Security-Policy" content="'
      "default-src 'none'; img-src data:; font-src data:; "
      'style-src \'unsafe-inline\' data:; script-src \'none\'; '
      'form-action \'none\'; base-uri \'none\'">';
  const baseStyle =
      '<style>html{-webkit-overflow-scrolling:touch;'
      'padding:1em 0}</style>';
  final headOpen = RegExp(r'<head\b[^>]*>', caseSensitive: false);
  final htmlOpen = RegExp(r'<html\b[^>]*>', caseSensitive: false);
  if (headOpen.hasMatch(rewritten)) {
    return rewritten.replaceFirstMapped(
      headOpen,
      (m) => '${m[0]}$csp$baseStyle',
    );
  }
  if (htmlOpen.hasMatch(rewritten)) {
    return rewritten.replaceFirstMapped(
      htmlOpen,
      (m) => '${m[0]}<head>$csp$baseStyle</head>',
    );
  }
  return '<html><head>$csp$baseStyle</head>$rewritten</html>';
}

String _directoryOf(String path) =>
    path.contains('/') ? path.substring(0, path.lastIndexOf('/') + 1) : '';

/// 任何协议地址（http、javascript、mailto…）与协议相对 // 都视为被禁。
bool _isBlockedPath(String path) =>
    path.startsWith('//') ||
    RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:').hasMatch(path);

String _dataUri(
  String path,
  Uint8List bytes,
  Map<String, Uint8List> resources, [
  Set<String>? visiting,
]) {
  final seen = {...?visiting, path};
  Uint8List payload = bytes;
  if (path.toLowerCase().endsWith('.css')) {
    payload = Uint8List.fromList(
      utf8.encode(_rewriteCss(path, bytes, resources, seen)),
    );
  }
  final encoded = base64Encode(payload);
  return switch (path.toLowerCase().split('.').last) {
    'css' => 'data:text/css;base64,$encoded',
    'png' => 'data:image/png;base64,$encoded',
    'jpg' || 'jpeg' => 'data:image/jpeg;base64,$encoded',
    'gif' => 'data:image/gif;base64,$encoded',
    'webp' => 'data:image/webp;base64,$encoded',
    'svg' => 'data:image/svg+xml;base64,$encoded',
    'ttf' => 'data:font/ttf;base64,$encoded',
    'otf' => 'data:font/otf;base64,$encoded',
    'woff' => 'data:font/woff;base64,$encoded',
    'woff2' => 'data:font/woff2;base64,$encoded',
    _ => 'data:application/octet-stream;base64,$encoded',
  };
}

String _rewriteCss(
  String path,
  Uint8List bytes,
  Map<String, Uint8List> resources,
  Set<String> seen,
) {
  final directory = _directoryOf(path);
  final css = utf8.decode(bytes);
  final withImports = css.replaceAllMapped(
    RegExp(r'''@import\s+(?:url\(\s*)?["']([^"']+)["']\s*\)?\s*;'''),
    (match) {
      final raw = match.group(1)!;
      if (raw.startsWith('data:')) return match[0]!;
      final key = _normalizePath(
        directory,
        Uri.decodeComponent(raw.split('#').first),
      );
      final body = resources[key];
      if (_isBlockedPath(raw) || body == null || seen.contains(key)) {
        return '/* @import 已阻断 */';
      }
      return '@import url("${_dataUri(key, body, resources, seen)}");';
    },
  );
  return withImports.replaceAllMapped(
    RegExp(r'''url\(\s*(["']?)([^"')]+)\1\s*\)'''),
    (match) {
      final raw = match.group(2)!;
      if (raw.startsWith('data:')) return match[0]!;
      final hashIndex = raw.indexOf('#');
      final fragment = hashIndex >= 0 ? raw.substring(hashIndex) : '';
      final plain = hashIndex >= 0 ? raw.substring(0, hashIndex) : raw;
      if (plain.isEmpty) return match[0]!;
      if (_isBlockedPath(plain)) return 'url("#")';
      final key = _normalizePath(directory, Uri.decodeComponent(plain));
      final body = resources[key];
      if (body == null || seen.contains(key)) return match[0]!;
      return 'url("${_dataUri(key, body, resources, seen)}$fragment")';
    },
  );
}

/// 加载一章的原始 XHTML 及其引用到的全部压缩包内资源。
class EpubFidelitySource {
  EpubFidelitySource(this.repository);
  final Repository repository;

  /// 是否存在可用的原版排版源（不做字节级读取，供模式开关判定）。
  Future<bool> isAvailable(String workId, String chapterId) async {
    final anchors = await repository.listAnchors(workId);
    final anchor = anchors
        .where(
          (a) =>
              a.chapterId == chapterId &&
              a.targetType == 'epub-source' &&
              a.state == 'active',
        )
        .firstOrNull;
    if (anchor == null) return false;
    final blobs = await repository.listBlobs(workId);
    return blobs.any((b) => b.id == anchor.targetId);
  }

  Future<EpubFidelityDoc?> load(String workId, Chapter chapter) async {
    final anchors = await repository.listAnchors(workId);
    final anchor = anchors
        .where(
          (a) =>
              a.chapterId == chapter.id &&
              a.targetType == 'epub-source' &&
              a.state == 'active',
        )
        .firstOrNull;
    if (anchor == null) return null;
    final blobs = await repository.listBlobs(workId);
    final docBlob = blobs.where((b) => b.id == anchor.targetId).firstOrNull;
    if (docBlob == null) return null;
    final bytes = await repository.getBlobData(docBlob.storageKey);
    if (bytes == null) return null;
    final path = docBlob.storageKey.substring(
      docBlob.storageKey.indexOf('/') + 1,
    );
    final xhtml = utf8.decode(bytes);
    final directory = _directoryOf(path);
    final pending = <String>{};
    for (final match in RegExp(
      r'''(?:src|href)=["']([^"']+)["']''',
    ).allMatches(xhtml)) {
      final raw = match.group(1)!;
      if (raw.contains('://') || raw.startsWith('data:')) continue;
      pending.add(_normalizePath(directory, raw.split('#').first));
    }
    final resources = <String, Uint8List>{};
    while (pending.isNotEmpty) {
      final candidate = pending.first;
      pending.remove(candidate);
      if (resources.containsKey(candidate)) continue;
      final rec = blobs
          .where((b) => b.storageKey == '$workId/$candidate')
          .firstOrNull;
      if (rec == null) continue;
      final data = await repository.getBlobData(rec.storageKey);
      if (data == null) continue;
      resources[candidate] = data;
      if (!candidate.toLowerCase().endsWith('.css')) continue;
      final cssDirectory = _directoryOf(candidate);
      final css = utf8.decode(data);
      final cssRefs = <String>[
        for (final match in RegExp(
          r'''url\(\s*["']?([^"')]+)["']?\s*\)''',
        ).allMatches(css))
          match.group(1)!,
        for (final match in RegExp(
          r'''@import\s+(?:url\(\s*)?["']([^"')]+)["']''',
        ).allMatches(css))
          match.group(1)!,
      ];
      for (final raw in cssRefs) {
        if (raw.contains('://') || raw.startsWith('data:')) continue;
        pending.add(_normalizePath(cssDirectory, raw.split('#').first));
      }
    }
    return EpubFidelityDoc(path: path, xhtml: xhtml, resources: resources);
  }
}

String _normalizePath(String base, String href) {
  final combined = href.startsWith('/')
      ? href.substring(1)
      : base + Uri.decodeComponent(href);
  final segments = <String>[];
  for (final segment in combined.split('/')) {
    if (segment == '.' || segment.isEmpty) continue;
    if (segment == '..') {
      if (segments.isNotEmpty) segments.removeLast();
      continue;
    }
    segments.add(segment);
  }
  return segments.join('/');
}
