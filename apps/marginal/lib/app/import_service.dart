import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import '../core/bundle.dart';
import '../core/repository.dart';
import '../core/split.dart';
import '../core/types.dart';
import 'ids.dart';
import 'paragraphs.dart';

class PickedInput {
  const PickedInput(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

abstract interface class FileSource {
  Future<PickedInput?> pick();
}

class PickerFileSource implements FileSource {
  const PickerFileSource();
  @override
  Future<PickedInput?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['txt', 'mabk', 'epub'],
    );
    final file = result?.files.single;
    return file?.bytes == null ? null : PickedInput(file!.name, file.bytes!);
  }
}

/// 导入阶段文案（ImportService.importTxt 的 onProgress 回调约定）。
abstract final class ImportStages {
  static const readFile = '读取文件';
  static const splitting = '解析切分';
  static const writing = '写入书库';
}

class ImportService {
  ImportService(this.repository);
  final Repository repository;

  /// 导入 TXT：onProgress 依次回调「读取文件 → 解析切分 → 写入书库」。
  Future<Work> importTxt(
    String name,
    Uint8List bytes, {
    void Function(String stage)? onProgress,
  }) async {
    void stage(String s) => onProgress?.call(s);
    stage(ImportStages.readFile);
    String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      text = utf8.decode(bytes, allowMalformed: true);
    }
    stage(ImportStages.splitting);
    final now = DateTime.now().millisecondsSinceEpoch;
    final work = Work(
      id: newId('work'),
      title: name.replaceFirst(RegExp(r'\.txt$', caseSensitive: false), ''),
      importSource: name,
      createdAt: now,
      updatedAt: now,
    );
    final proposed = assembleChapters(text, splitByHeuristics(text));
    if (proposed.isEmpty || text.trim().isEmpty) {
      throw const FormatException('TXT 没有可导入的正文');
    }
    stage(ImportStages.writing);
    await repository.putWork(work);
    try {
      for (var i = 0; i < proposed.length; i++) {
        final body = normalizeChapterText(
          sliceChapterText(text, proposed[i].startLine, proposed[i].endLine),
        );
        if (body.trim().isEmpty) continue;
        final chapter = Chapter(
          id: newId('chapter'),
          workId: work.id,
          idx: i,
          title: proposed[i].title,
          wordCount: body.runes.length,
          contentHash: sha256.convert(utf8.encode(body)).toString(),
        );
        await repository.putChapter(work.id, chapter, body);
      }
      if ((await repository.listChapters(work.id)).isEmpty) {
        throw const FormatException('TXT 没有可导入的章节');
      }
    } catch (_) {
      await repository.deleteWork(work.id);
      rethrow;
    }
    return work;
  }

  Future<Work> importEpub(
    String name,
    Uint8List bytes, {
    void Function(String stage)? onProgress,
  }) async {
    onProgress?.call(ImportStages.readFile);
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, String>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final content = file.content as List<int>;
      files[file.name] = utf8.decode(content, allowMalformed: true);
    }
    final container = files['META-INF/container.xml'];
    if (container == null) throw const FormatException('EPUB 缺少 container.xml');
    final opfPath = _xmlAttr(container, 'rootfile', 'full-path');
    if (opfPath == null) throw const FormatException('EPUB 缺少 OPF 清单');
    final opf = files[opfPath];
    if (opf == null) throw const FormatException('EPUB 找不到 OPF 文件');
    final base = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';
    final manifest = <String, String>{
      for (final match in RegExp(
        r'''<item\b[^>]*?id=["']([^"']+)["'][^>]*?href=["']([^"']+)["']''',
        caseSensitive: false,
      ).allMatches(opf))
        match.group(1)!: _resolvePath(base, match.group(2)!),
    };
    final spine = [
      for (final match in RegExp(
        r'''<itemref\b[^>]*?idref=["']([^"']+)["']''',
        caseSensitive: false,
      ).allMatches(opf))
        match.group(1)!,
    ];
    if (spine.isEmpty) throw const FormatException('EPUB 没有可读章节');
    onProgress?.call(ImportStages.splitting);
    final chapters = <MapEntry<String, String>>[];
    for (final id in spine) {
      final path = manifest[id];
      final html = path == null ? null : files[path];
      if (html == null) continue;
      final title = _htmlTitle(html) ?? '第 ${chapters.length + 1} 章';
      final text = _htmlText(html);
      if (text.trim().isNotEmpty) chapters.add(MapEntry(title, text));
    }
    if (chapters.isEmpty) throw const FormatException('EPUB 没有可读正文');
    onProgress?.call(ImportStages.writing);
    final now = DateTime.now().millisecondsSinceEpoch;
    final work = Work(
      id: newId('work'),
      title: name.replaceFirst(RegExp(r'\.epub$', caseSensitive: false), ''),
      importSource: name,
      createdAt: now,
      updatedAt: now,
    );
    await repository.putWork(work);
    try {
      for (var i = 0; i < chapters.length; i++) {
        final text = chapters[i].value;
        await repository.putChapter(
          work.id,
          Chapter(
            id: newId('chapter'),
            workId: work.id,
            idx: i,
            title: chapters[i].key,
            wordCount: text.runes.length,
            contentHash: sha256.convert(utf8.encode(text)).toString(),
          ),
          text,
        );
      }
    } catch (_) {
      await repository.deleteWork(work.id);
      rethrow;
    }
    return work;
  }

  Future<Work> importMabk(Uint8List bytes, {required bool copy}) async {
    final bundle = readBundle(bytes);
    final data = bundle.data;
    await repository.importBundle(data, copy: copy, blobData: bundle.blobData);
    return (await repository.listWorks()).firstWhere(
      (w) => w.id == data.work.id || w.title == '${data.work.title}（副本）',
    );
  }

  String? _xmlAttr(String source, String tag, String attribute) {
    final match = RegExp(
      '<$tag\\b[^>]*\\b$attribute=["\\\']([^"\\\']+)["\\\']',
      caseSensitive: false,
    ).firstMatch(source);
    return match?.group(1);
  }

  String _resolvePath(String base, String path) {
    final parts = [...base.split('/'), ...path.split('/')];
    final resolved = <String>[];
    for (final part in parts) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (resolved.isNotEmpty) resolved.removeLast();
      } else {
        resolved.add(part);
      }
    }
    return resolved.join('/');
  }

  String? _htmlTitle(String html) {
    final match = RegExp(
      r'<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    final title = match == null ? null : _htmlText(match.group(1)!);
    final clean = title?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  String _htmlText(String html) {
    final withoutHead = html
        .replaceAll(
          RegExp(r'<head[^>]*>.*?</head>', caseSensitive: false, dotAll: true),
          '',
        )
        .replaceAll(
          RegExp(
            r'<title[^>]*>.*?</title>',
            caseSensitive: false,
            dotAll: true,
          ),
          '',
        );
    final withoutStyle = withoutHead.replaceAll(
      RegExp(
        r'<(script|style)[^>]*>.*?</\1>',
        caseSensitive: false,
        dotAll: true,
      ),
      '',
    );
    final withBreaks = withoutStyle.replaceAll(
      RegExp(r'<br\s*/?>|</p>|</div>|</h[1-6]>', caseSensitive: false),
      '\n',
    );
    final text = withBreaks.replaceAll(RegExp(r'<[^>]+>'), '');
    return _decodeHtmlEntities(text)
        .replaceAll(RegExp(r'[ \\t]+'), ' ')
        .replaceAll(RegExp(r'\\n{3,}'), '\\n\\n')
        .trim();
  }

  String _decodeHtmlEntities(String text) => text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAllMapped(
        RegExp(r'&#(\\d+);'),
        (match) => String.fromCharCode(int.parse(match.group(1)!)),
      )
      .replaceAllMapped(
        RegExp(r'&#x([0-9a-f]+);', caseSensitive: false),
        (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
      );

  /// 导出整本书为 .mabk 并唤起系统分享。
  ///
  /// 返回 false 表示当前平台不支持（Web 无法写文件分享，调用方应置灰按钮）。
  Future<bool> exportMabk(Work work) async {
    if (kIsWeb) return false;
    try {
      final bytes = buildBundle(await repository.exportAll(work.id));
      final fileName = work.title.isEmpty ? 'book.mabk' : '${work.title}.mabk';
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'application/zip')],
          fileNameOverrides: [fileName],
        ),
      );
      return result.status != ShareResultStatus.dismissed;
    } catch (_) {
      return false;
    }
  }
}
