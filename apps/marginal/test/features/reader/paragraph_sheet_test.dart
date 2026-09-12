import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/features/reader/reader_paragraph_sheet.dart';

void main() {
  Future<void> pumpHost(
    WidgetTester tester, {
    required ReaderParagraphSheet sheet,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => sheet,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('未收藏时显示收藏段落，点击回调并收起面板', (tester) async {
    var toggled = 0;
    await pumpHost(
      tester,
      sheet: ReaderParagraphSheet(
        paragraph: '一段值得收藏的文字。',
        isFavorite: false,
        onToggleFavorite: () => toggled++,
      ),
    );
    expect(find.text('收藏段落'), findsOneWidget);
    expect(find.text('取消收藏'), findsNothing);

    await tester.tap(find.text('收藏段落'));
    await tester.pumpAndSettle();
    expect(toggled, 1);
    expect(find.text('收藏段落'), findsNothing, reason: '点击后面板收起');
  });

  testWidgets('已收藏时显示取消收藏', (tester) async {
    await pumpHost(
      tester,
      sheet: ReaderParagraphSheet(
        paragraph: '已收藏段落。',
        isFavorite: true,
        onToggleFavorite: () {},
      ),
    );
    expect(find.text('取消收藏'), findsOneWidget);
  });

  testWidgets('AI 插图与分享回调被触发', (tester) async {
    var illustrated = 0;
    var shared = 0;
    await pumpHost(
      tester,
      sheet: ReaderParagraphSheet(
        paragraph: '段落',
        isFavorite: false,
        onShareText: () => shared++,
        onIllustrate: () => illustrated++,
      ),
    );
    await tester.tap(find.text('AI 插图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享文字'));
    await tester.pumpAndSettle();
    expect(illustrated, 1);
    expect(shared, 1);
  });

  testWidgets('回调未注入时点击仅收起面板不崩溃', (tester) async {
    await pumpHost(
      tester,
      sheet: const ReaderParagraphSheet(paragraph: '段落', isFavorite: false),
    );
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsNothing);
  });
}
