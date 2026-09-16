import '../core/repository.dart';

class ChapterWindow {
  const ChapterWindow({
    required this.text,
    required this.start,
    required this.end,
    required this.totalLength,
    required this.paragraphBase,
  });

  final String text;
  final int start, end, totalLength, paragraphBase;
  double get startRatio => totalLength == 0 ? 0 : start / totalLength;
  double get endRatio => totalLength == 0 ? 1 : end / totalLength;
}

class ChapterWindowSource {
  ChapterWindowSource(
    this.repository, {
    this.windowSize = 48000,
    this.scanSize = 16000,
  });

  final Repository repository;
  final int windowSize, scanSize;

  Future<ChapterWindow> load(
    String chapterId, {
    double ratio = 0,
    int? offset,
  }) async {
    final total = await repository.getChapterTextLength(chapterId);
    if (total == 0) {
      return const ChapterWindow(
        text: '',
        start: 0,
        end: 0,
        totalLength: 0,
        paragraphBase: 0,
      );
    }
    final center = offset ?? (ratio.clamp(0.0, 1.0) * total).round();
    var start = (center - windowSize ~/ 3).clamp(0, total);
    var end = (start + windowSize).clamp(start, total);
    start = await _alignStart(chapterId, start);
    end = await _alignEnd(chapterId, end, total);
    final text = await repository.readChapterRange(
      chapterId,
      start,
      end - start,
    );
    return ChapterWindow(
      text: text,
      start: start,
      end: end,
      totalLength: total,
      paragraphBase: await paragraphCountBefore(chapterId, start),
    );
  }

  Future<int> paragraphCountBefore(String chapterId, int end) async {
    var count = 0;
    var offset = 0;
    var pending = '';
    while (offset < end) {
      final length = (end - offset).clamp(0, scanSize);
      final chunk = await repository.readChapterRange(
        chapterId,
        offset,
        length,
      );
      if (chunk.isEmpty) break;
      final combined = pending + chunk;
      final lines = combined.split(RegExp(r'\r\n?|\n'));
      pending = lines.removeLast();
      count += lines.where((line) => line.trim().isNotEmpty).length;
      offset += chunk.length;
    }
    if (pending.trim().isNotEmpty && offset >= end) count++;
    return count;
  }

  Future<int> paragraphOffset(String chapterId, int paragraphIndex) async {
    if (paragraphIndex <= 0) return 0;
    var offset = 0;
    var count = 0;
    var pending = '';
    var pendingStart = 0;
    final total = await repository.getChapterTextLength(chapterId);
    while (offset < total) {
      final chunk = await repository.readChapterRange(
        chapterId,
        offset,
        (total - offset).clamp(0, scanSize),
      );
      if (chunk.isEmpty) break;
      final combined = pending + chunk;
      var lineStart = pendingStart;
      final matches = RegExp(r'\r\n?|\n').allMatches(combined).toList();
      var previous = 0;
      for (final match in matches) {
        final line = combined.substring(previous, match.start);
        if (line.trim().isNotEmpty) {
          if (count == paragraphIndex) return lineStart;
          count++;
        }
        lineStart += match.end - previous;
        previous = match.end;
      }
      pending = combined.substring(previous);
      pendingStart = lineStart;
      offset += chunk.length;
    }
    return total;
  }

  Future<int> _alignStart(String chapterId, int start) async {
    if (start <= 0) return 0;
    final lookBehind = start.clamp(0, 1024);
    final prefix = await repository.readChapterRange(
      chapterId,
      start - lookBehind,
      lookBehind,
    );
    final newline = prefix.lastIndexOf('\n');
    return newline < 0 ? start : start - lookBehind + newline + 1;
  }

  Future<int> _alignEnd(String chapterId, int end, int total) async {
    if (end >= total) return total;
    final suffix = await repository.readChapterRange(
      chapterId,
      end,
      (total - end).clamp(0, 1024),
    );
    final newline = suffix.indexOf('\n');
    return newline < 0 ? end : end + newline + 1;
  }
}
