import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/import_service.dart';
import 'package:marginal/app/platform_services.dart';
import 'package:marginal/data/memory_repository.dart';
import 'package:marginal/features/reader/reader_epub_fidelity.dart';
import 'package:marginal/features/reader/reader_page.dart';

/// EPUB 富文本跨端降级：非浏览器目标（本测试运行在 VM）不渲染 DOM，
/// 语义正文、章节图片照常可用，且不暴露「原版排版」开关。
void main() {
  Uint8List epubBytes() {
    final archive = Archive()
      ..addFile(
        ArchiveFile(
          'META-INF/container.xml',
          100,
          utf8.encode(
            '<container><rootfile full-path="OEBPS/content.opf"/></container>',
          ),
        ),
      )
      ..addFile(
        ArchiveFile(
          'OEBPS/content.opf',
          200,
          utf8.encode(
            '<package><manifest><item id="c1" href="Text/chapter1.xhtml"/>'
            '<item id="css" href="Styles/book.css"/></manifest>'
            '<spine><itemref idref="c1"/></spine></package>',
          ),
        ),
      )
      ..addFile(
        ArchiveFile(
          'OEBPS/Text/chapter1.xhtml',
          160,
          utf8.encode(
            '<html><head><title>第一章</title>'
            '<link rel="stylesheet" href="../Styles/book.css"/></head>'
            '<body><p>风从门缝吹进来。</p>'
            '<img src="../Images/page.png"/></body></html>',
          ),
        ),
      )
      ..addFile(
        ArchiveFile(
          'OEBPS/Styles/book.css',
          30,
          utf8.encode('p { text-indent: 2em; }'),
        ),
      )
      ..addFile(
        ArchiveFile('OEBPS/Images/page.png', 4, Uint8List.fromList([1, 2, 3, 4])),
      );
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  testWidgets('VM 目标：语义正文与图片可用，不显示原版排版开关', (tester) async {
    final repo = MemoryRepository();
    await repo.init();
    final work = await ImportService(repo).importEpub('故事.epub', epubBytes());
    final services = PlatformServices(repository: repo);
    final chapters = await repo.listChapters(work.id);

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          services: services,
          work: work,
          initialChapterId: chapters.first.id,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(epubFidelitySupported, isFalse, reason: '本测试锁定非浏览器降级');
    expect(find.text('风从门缝吹进来。'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget, reason: '语义插图锚点仍渲染');

    await tester.tap(find.byKey(const Key('reader-open-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('epub-fidelity-switch')), findsNothing);

    await tester.tapAt(const Offset(20, 40));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
