import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/reading_stats.dart';

void main() {
  test('记录分钟数并以本地日期计算连续天数', () {
    final settings = <String, dynamic>{};
    final day = DateTime(2026, 9, 15, 21);
    recordReadingMinutes(settings, now: day, minutes: 12);
    recordReadingMinutes(settings, now: day, minutes: 8);
    recordReadingMinutes(
      settings,
      now: day.subtract(const Duration(days: 1)),
      minutes: 5,
    );

    final stats = readReadingStats(settings, now: day);
    expect(stats.minutes, 25);
    expect(stats.streakDays, 2);
  });

  test('断档后连续天数从零开始，单次分钟增量限制在合理范围', () {
    final settings = <String, dynamic>{
      'readingStats': {
        'minutes': 4,
        'days': ['2026-09-12'],
      },
    };
    recordReadingMinutes(settings, now: DateTime(2026, 9, 15), minutes: 99);
    final stats = readReadingStats(settings, now: DateTime(2026, 9, 15));
    expect(stats.minutes, 64);
    expect(stats.streakDays, 1);
  });
}
