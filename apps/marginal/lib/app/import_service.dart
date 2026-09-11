import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';

import '../core/bundle.dart';
import '../core/repository.dart';
import '../core/split.dart';
import '../core/types.dart';
import 'ids.dart';

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

class ImportService {
  ImportService(this.repository);
  final Repository repository;
  Future<Work> importTxt(String name, Uint8List bytes) async {
    String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      text = utf8.decode(bytes, allowMalformed: true);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final work = Work(
      id: newId('work'),
      title: name.replaceFirst(RegExp(r'\.txt$', caseSensitive: false), ''),
      importSource: name,
      createdAt: now,
      updatedAt: now,
    );
    await repository.putWork(work);
    final proposed = assembleChapters(text, splitByHeuristics(text));
    for (var i = 0; i < proposed.length; i++) {
      final body = sliceChapterText(
        text,
        proposed[i].startLine,
        proposed[i].endLine,
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
}
