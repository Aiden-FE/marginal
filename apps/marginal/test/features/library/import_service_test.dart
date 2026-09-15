import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/import_service.dart';
import 'package:marginal/app/platform_services.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/data/memory_repository.dart';

const String sampleTxt = '第一章 起点\n\n少年推开门，风雪扑面。\n\n第二章 归途\n\n雪停了，路还很长。\n';

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List hexBytes(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

Uint8List epubBytes() {
  final archive = Archive()
    ..addFile(
      ArchiveFile(
        'META-INF/container.xml',
        utf8
            .encode(
              '<?xml version="1.0"?><container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>',
            )
            .length,
        utf8.encode(
          '<?xml version="1.0"?><container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>',
        ),
      ),
    )
    ..addFile(
      ArchiveFile(
        'OEBPS/content.opf',
        utf8
            .encode(
              '<package><manifest><item id="c1" href="chapter1.xhtml"/><item id="c2" href="chapter2.xhtml"/></manifest><spine><itemref idref="c1"/><itemref idref="c2"/></spine></package>',
            )
            .length,
        utf8.encode(
          '<package><manifest><item id="c1" href="chapter1.xhtml"/><item id="c2" href="chapter2.xhtml"/></manifest><spine><itemref idref="c1"/><itemref idref="c2"/></spine></package>',
        ),
      ),
    )
    ..addFile(
      ArchiveFile(
        'OEBPS/chapter1.xhtml',
        70,
        utf8.encode(
          '<html><title>第一章</title><body><p>风从门缝吹进来。</p></body></html>',
        ),
      ),
    )
    ..addFile(
      ArchiveFile(
        'OEBPS/chapter2.xhtml',
        70,
        utf8.encode('<html><title>第二章</title><body><p>天亮了。</p></body></html>'),
      ),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

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

    test('GBK TXT 正确解码而不是静默替换乱码', () async {
      final repo = MemoryRepository();
      await repo.init();
      final work = await ImportService(repo).importTxt(
        '中文.txt',
        hexBytes(
          'b5dad2bbd5c220c6f0b5e30a0ac9d9c4eacdc6bfaac3c5a3acb7e7d1a9c6cbc3e6a1a30a',
        ),
      );
      expect(work.title, '中文');
      final chapter = (await repo.listChapters(work.id)).single;
      expect(await repo.getChapterText(chapter.id), contains('风雪扑面'));
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

    test('EPUB 按 spine 顺序导入章节正文', () async {
      final repo = MemoryRepository();
      await repo.init();
      final work = await ImportService(repo).importEpub('故事.epub', epubBytes());
      expect(work.title, '故事');
      final chapters = await repo.listChapters(work.id);
      expect(chapters.map((chapter) => chapter.title), ['第一章', '第二章']);
      expect(await repo.getChapterText(chapters.first.id), '风从门缝吹进来。');
      expect(await repo.getChapterText(chapters.last.id), '天亮了。');
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
