import 'dart:convert';

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
      allowedExtensions: ['txt', 'mabk'],
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
    stage(ImportStages.writing);
    await repository.putWork(work);
    for (var i = 0; i < proposed.length; i++) {
      final body = normalizeChapterText(
        sliceChapterText(text, proposed[i].startLine, proposed[i].endLine),
      );
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
