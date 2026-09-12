import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/poster.dart';

void main() {
  group('wrapPosterText', () {
    test('空文本返回空列表', () {
      expect(wrapPosterText(''), isEmpty);
      expect(wrapPosterText('   '), isEmpty);
    });

    test('短文本单行输出并归一空白', () {
      expect(wrapPosterText('你  好\n\n世界'), ['你 好 世界']);
    });

    test('中文按 20 个全角单位断行', () {
      final lines = wrapPosterText('汉' * 45);
      expect(lines, hasLength(3));
      expect(lines[0], hasLength(20));
      expect(lines[1], hasLength(20));
      expect(lines[2], hasLength(5));
    });

    test('半角字符按 0.55 单位计宽', () {
      final lines = wrapPosterText('a' * 40);
      expect(lines, hasLength(2));
      expect(lines[0], hasLength(36)); // 36 * 0.55 = 19.8
      expect(lines.join('').length, 40);
    });

    test('超过 maxLines 截断并以省略号结尾', () {
      final lines = wrapPosterText('汉' * 500);
      expect(lines, hasLength(18));
      expect(lines.last, endsWith('…'));
    });

    test('maxUnits 自定义宽度生效', () {
      final lines = wrapPosterText('汉' * 10, maxUnits: 4);
      expect(lines, hasLength(3));
      expect(lines.take(2).every((l) => l.length == 4), isTrue);
    });
  });
}
