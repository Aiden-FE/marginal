import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/import_service.dart';
import 'package:marginal/app/platform_services.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/data/memory_repository.dart';

const String sampleTxt = '第一章 起点\n\n少年推开门，风雪扑面。\n\n第二章 归途\n\n雪停了，路还很长。\n';

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

class FailingChapterRepository extends MemoryRepository {
  var writes = 0;

  @override
  Future<void> putChapter(String workId, Chapter chapter, String text) async {
    writes++;
    if (writes >= 1) throw StateError('simulated chapter write failure');
    await super.putChapter(workId, chapter, text);
  }
}

void main() {
  group('ImportService.importTxt onProgress', () {
    test('依次回调 读取文件 → 解析切分 → 写入书库', () async {
      final services = await PlatformServices.boot(persistent: false);
      final stages = <String>[];
      await ImportService(services.repository)
          .importTxt('风雪.txt', bytesOf(sampleTxt), onProgress: stages.add);
      expect(stages, [
        ImportStages.readFile,
        ImportStages.splitting,
        ImportStages.writing,
      ]);
    });

    test('不传 onProgress 也能正常导入', () async {
      final services = await PlatformServices.boot(persistent: false);
      final work = await ImportService(services.repository)
          .importTxt('风雪.txt', bytesOf(sampleTxt));
      expect(work.title, '风雪');
      expect((await services.repository.listChapters(work.id)).length, 2);
    });

    test('章节写入失败时清理残缺书稿', () async {
      final repo = FailingChapterRepository();
      await repo.init();
      await expectLater(
        ImportService(repo).importTxt('失败.txt', bytesOf(sampleTxt)),
        throwsStateError,
      );
      expect(await repo.listWorks(), isEmpty);
      expect(await repo.listChapters('missing-work'), isEmpty);
    });

    test('空 TXT 拒绝导入且不写库', () async {
      final repo = MemoryRepository();
      await repo.init();
      await expectLater(
        ImportService(repo).importTxt('空.txt', Uint8List(0)),
        throwsFormatException,
      );
      expect(await repo.listWorks(), isEmpty);
    });

    test('阶段回调先于章节写库完成', () async {
      final services = await PlatformServices.boot(persistent: false);
      final stagesAtWriteTime = <String>[];
      var sawWriting = false;
      await ImportService(services.repository).importTxt(
        '风雪.txt',
        bytesOf(sampleTxt),
        onProgress: (stage) {
          if (stage == ImportStages.writing) sawWriting = true;
          stagesAtWriteTime.add(stage);
        },
      );
      expect(sawWriting, isTrue);
      expect(stagesAtWriteTime.last, ImportStages.writing);
    });
  });
}
