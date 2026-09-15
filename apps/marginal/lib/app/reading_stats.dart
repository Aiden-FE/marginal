class ReadingStats {
  const ReadingStats({required this.minutes, required this.streakDays});
  final int minutes;
  final int streakDays;
}

ReadingStats readReadingStats(Map<String, dynamic> settings, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final raw = settings['readingStats'];
  if (raw is! Map) return const ReadingStats(minutes: 0, streakDays: 0);
  final days = (raw['days'] as List? ?? const []).whereType<String>().toSet();
  return ReadingStats(
    minutes: (raw['minutes'] as num?)?.toInt() ?? 0,
    streakDays: readingStreakDays(days, current),
  );
}

void recordReadingMinutes(
  Map<String, dynamic> settings, {
  required DateTime now,
  required int minutes,
}) {
  final raw = settings['readingStats'];
  final existing = raw is Map ? raw : const <String, dynamic>{};
  final days = (existing['days'] as List? ?? const [])
      .whereType<String>()
      .toSet();
  days.add(readingDateKey(now));
  settings['readingStats'] = {
    'minutes':
        ((existing['minutes'] as num?)?.toInt() ?? 0) + minutes.clamp(0, 60),
    'days': days.toList()..sort(),
  };
}

int readingStreakDays(Set<String> days, DateTime now) {
  var cursor = DateTime(now.year, now.month, now.day);
  var count = 0;
  while (days.contains(readingDateKey(cursor))) {
    count++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return count;
}

String readingDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
