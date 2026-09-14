import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/share.dart';
import 'package:marginal/features/reader/reader_poster_sheet.dart';

void main() {
  testWidgets('海报 sheet 打开即预渲染 PNG 图片，可长按存储', (tester) async {
    Uint8List? captured;
    final share = RecordingShareService(
      onImage: (file) async {
        captured = await file.readAsBytes();
        return true;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPosterSheet(
            workTitle: '书',
            chapterTitle: '第一章',
            text: '要分享的那一段。',
            shareService: share,
            encoder: ({
              required workTitle,
              required chapterTitle,
              required text,
              double pixelRatio = 3,
            }) async => Uint8List.fromList(fakePng),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 预览必须是真实图片（Image.memory），Safari 长按即可存储。
    expect(find.byType(Image), findsOneWidget);
    await tester.ensureVisible(find.text('分享图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享图片'));
    await tester.pumpAndSettle();
    expect(captured, isNotNull);
    expect(
      captured!.sublist(0, 4),
      equals([0x89, 0x50, 0x4E, 0x47]),
      reason: '应为 PNG',
    );
  });

  testWidgets('分享失败时保留预览与降级提示', (tester) async {
    final share = RecordingShareService(onImage: (_) async => false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPosterSheet(
            workTitle: '书',
            chapterTitle: '第一章',
            text: '一段。',
            shareService: share,
            encoder: ({
              required workTitle,
              required chapterTitle,
              required text,
              double pixelRatio = 3,
            }) async => Uint8List.fromList(fakePng),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享图片'));
    await tester.pumpAndSettle();
    expect(find.textContaining('长按海报图片'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('空编码器立即进入错误态而不持续 loading', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPosterSheet(
            workTitle: '书',
            chapterTitle: '第一章',
            text: '一段。',
            shareService: RecordingShareService(),
            encoder: null,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('未配置编码器'), findsAtLeastNWidgets(1));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('海报编码挂起时超时给出错误提示且按钮禁用', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPosterSheet(
            workTitle: '书',
            chapterTitle: '第一章',
            text: '一段。',
            shareService: RecordingShareService(),
            encoder: ({
              required workTitle,
              required chapterTitle,
              required text,
              double pixelRatio = 3,
            }) => Completer<Uint8List>().future,
            renderTimeout: const Duration(milliseconds: 100),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.textContaining('海报生成失败'), findsAtLeastNWidgets(1));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '分享图片'),
    );
    expect(button.onPressed, isNull, reason: '编码失败时分享按钮禁用');
  });
}

const fakePng = [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

class RecordingShareService implements ShareService {
  RecordingShareService({this.onImage});
  final Future<bool> Function(dynamic file)? onImage;
  @override
  Future<bool> shareImage(dynamic file) async =>
      onImage == null ? true : await onImage!(file);
}
