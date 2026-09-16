import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/core/types.dart';
import 'package:marginal/data/memory_repository.dart';
import 'package:marginal/features/reader/reader_epub_fidelity.dart';

void main() {
  test('srcdoc 保留固定版式 viewport 并离线内嵌 CSS、背景图与字体', () {
    final doc = EpubFidelityDoc(
      path: 'OEBPS/Text/chapter.xhtml',
      xhtml: '''
<html><head>
<meta name="viewport" content="width=1200,height=1600"/>
<link rel="stylesheet" href="../Styles/book.css"/>
</head><body><img src="../Images/page.png"/></body></html>
''',
      resources: {
        'OEBPS/Styles/book.css': Uint8List.fromList(
          utf8.encode('''
@font-face { font-family: book; src: url('../Fonts/book.woff2'); }
body { background: url('../Images/page.png'); font-family: book; }
'''),
        ),
        'OEBPS/Images/page.png': Uint8List.fromList([1, 2, 3]),
        'OEBPS/Fonts/book.woff2': Uint8List.fromList([4, 5, 6]),
      },
    );

    final srcdoc = epubFidelitySrcdoc(doc);

    expect(srcdoc, contains('width=1200,height=1600'));
    expect(srcdoc, contains('Content-Security-Policy'));
    expect(srcdoc, contains("script-src 'none'"));
    expect(srcdoc, contains('data:image/png;base64,AQID'));
    final cssMatch = RegExp(r'data:text/css;base64,([A-Za-z0-9+/=]+)')
        .firstMatch(srcdoc);
    expect(cssMatch, isNotNull);
    final css = utf8.decode(base64Decode(cssMatch!.group(1)!));
    expect(css, contains('data:image/png;base64,AQID'));
    expect(css, contains('data:font/woff2;base64,BAUG'));
  });

  test('srcdoc 禁用外部地址、base 与 meta refresh，保留资源 fragment', () {
    final doc = EpubFidelityDoc(
      path: 'OEBPS/Text/chapter.xhtml',
      xhtml: '''
<html><head>
<base href="https://evil.example/"/>
<meta http-equiv="refresh" content="0; url=https://evil.example/"/>
</head><body>
<a href="https://evil.example/x">外链</a>
<img src="//evil.example/x.png"/>
<svg><use xlink:href="../Images/sprite.svg#icon"/></svg>
</body></html>
''',
      resources: {
        'OEBPS/Images/sprite.svg': Uint8List.fromList(utf8.encode('<svg/>')),
      },
    );

    final srcdoc = epubFidelitySrcdoc(doc);

    expect(srcdoc, isNot(contains('evil.example')));
    expect(srcdoc, isNot(contains('<base ')));
    expect(srcdoc, isNot(contains('http-equiv="refresh"')));
    expect(srcdoc, contains('data:image/svg+xml;base64,'));
    expect(srcdoc, contains('#icon'));
    expect(srcdoc, contains('form-action \'none\''));
  });

  test('srcdoc 递归内嵌 CSS @import 并禁用外部 @import', () {
    final doc = EpubFidelityDoc(
      path: 'OEBPS/Text/chapter.xhtml',
      xhtml: '''
<html><head><link rel="stylesheet" href="../Styles/book.css"/></head>
<body><p>正文</p></body></html>
''',
      resources: {
        'OEBPS/Styles/book.css': Uint8List.fromList(
          utf8.encode(
            "@import \"theme.css\";\n@import 'https://evil.example/x.css';\n",
          ),
        ),
        'OEBPS/Styles/theme.css': Uint8List.fromList(
          utf8.encode('body { color: red; }'),
        ),
      },
    );

    final srcdoc = epubFidelitySrcdoc(doc);

    final cssMatch = RegExp(r'data:text/css;base64,([A-Za-z0-9+/=]+)')
        .firstMatch(srcdoc);
    expect(cssMatch, isNotNull);
    final css = utf8.decode(base64Decode(cssMatch!.group(1)!));
    expect(css, isNot(contains('"theme.css"')));
    expect(css, contains('@import url("data:text/css;base64,'));
    final nestedMatch = RegExp(
      r'@import url\("data:text/css;base64,([A-Za-z0-9+/=]+)"\)',
    ).firstMatch(css);
    expect(utf8.decode(base64Decode(nestedMatch!.group(1)!)), contains('red'));
    expect(css, isNot(contains('evil.example')));
    expect(css, contains('@import 已阻断'));
  });

  test('source loader 按章节锚点加载 XHTML 与全部 EPUB 渲染资源', () async {
    final repository = MemoryRepository();
    await repository.init();
    const work = Work(id: 'work', title: 'EPUB');
    const chapter = Chapter(
      id: 'chapter',
      workId: 'work',
      idx: 0,
      title: 'Fixed page',
    );
    await repository.putWork(work);
    await repository.putChapter(work.id, chapter, '语义降级正文');
    await repository.putBlob(
      const BlobRec(
        id: 'source',
        workId: 'work',
        storageKey: 'work/OEBPS/Text/chapter.xhtml',
        kind: 'epub-xhtml',
      ),
      Uint8List.fromList(
        utf8.encode(
          '<html><link href="../Styles/book.css"/><body>正文</body></html>',
        ),
      ),
    );
    await repository.putBlob(
      const BlobRec(
        id: 'css',
        workId: 'work',
        storageKey: 'work/OEBPS/Styles/book.css',
        kind: 'epub-css',
      ),
      Uint8List.fromList(
        utf8.encode(
          "@import \"../Styles/theme.css\";\n"
          "@font-face { src: url('../Fonts/book.woff2'); }",
        ),
      ),
    );
    await repository.putBlob(
      const BlobRec(
        id: 'theme',
        workId: 'work',
        storageKey: 'work/OEBPS/Styles/theme.css',
        kind: 'epub-css',
      ),
      Uint8List.fromList(utf8.encode('body { color: red; }')),
    );
    await repository.putBlob(
      const BlobRec(
        id: 'font',
        workId: 'work',
        storageKey: 'work/OEBPS/Fonts/book.woff2',
        kind: 'epub-font',
      ),
      Uint8List.fromList([1, 2]),
    );
    await repository.putAnchor(
      const Anchor(
        id: 'source-anchor',
        workId: 'work',
        chapterId: 'chapter',
        targetId: 'source',
        targetType: 'epub-source',
      ),
    );

    final doc = await EpubFidelitySource(repository).load(work.id, chapter);

    expect(doc, isNotNull);
    expect(doc!.path, 'OEBPS/Text/chapter.xhtml');
    expect(
      doc.resources.keys,
      containsAll([
        'OEBPS/Styles/book.css',
        'OEBPS/Styles/theme.css',
        'OEBPS/Fonts/book.woff2',
      ]),
    );
  });

  test('测试 VM 明确禁用 DOM 原版排版并走语义阅读降级', () {
    expect(epubFidelitySupported, isFalse);
  });
}
