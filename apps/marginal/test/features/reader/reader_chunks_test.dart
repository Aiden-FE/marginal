import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/features/reader/reader_chunks.dart';

void main() {
  test('长段落按预算分片且保留原始段落身份', () {
    final text = 'a' * 200000;
    final chunks = buildReaderChunks([text], maxCodeUnits: 4000);

    expect(chunks.length, greaterThan(40));
    expect(chunks.every((chunk) => chunk.paraIndex == 0), isTrue);
    expect(chunks.first.start, 0);
    expect(chunks.last.end, text.length);
    expect(chunks.where((chunk) => chunk.isLastFragment), hasLength(1));
    expect(chunks.map((chunk) => chunk.text).join(), text);
  });

  test('分片不会拆开 UTF-16 surrogate pair', () {
    final text = '前${String.fromCharCode(0x1F4D6)}后' * 3000;
    final chunks = buildReaderChunks([text], maxCodeUnits: 401);

    for (var i = 0; i < chunks.length - 1; i++) {
      final left = chunks[i].text.codeUnits.last;
      final right = chunks[i + 1].text.codeUnits.first;
      expect(
        left >= 0xD800 && left <= 0xDBFF && right >= 0xDC00 && right <= 0xDFFF,
        isFalse,
      );
    }
    expect(chunks.map((chunk) => chunk.text).join(), text);
  });

  test('短段落保持一个视觉片段', () {
    final chunks = buildReaderChunks(['第一段', '第二段']);

    expect(chunks.map((chunk) => chunk.paraIndex), [0, 1]);
    expect(chunks.every((chunk) => chunk.isLastFragment), isTrue);
  });
}
