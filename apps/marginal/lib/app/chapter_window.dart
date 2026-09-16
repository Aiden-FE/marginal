import '../core/repository.dart';

class ChapterWindow {
  const ChapterWindow({
    required this.text,
    required this.start,
    required this.end,
    required this.totalLength,
    required this.paragraphBase,
    required this.startsMidParagraph,
    required this.endsMidParagraph,
  });

  final String text;
  final int start, end, totalLength, paragraphBase;
  final bool startsMidParagraph, endsMidParagraph;
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
        startsMidParagraph: false,
        endsMidParagraph: false,
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
      startsMidParagraph: await _isMidParagraph(chapterId, start),
      endsMidParagraph: await _isMidParagraph(chapterId, end),
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

  Future<String> paragraphText(String chapterId, int paragraphIndex) async {
    final start = await paragraphOffset(chapterId, paragraphIndex);
    final total = await repository.getChapterTextLength(chapterId);
    if (start >= total) return '';
    final buffer = StringBuffer();
    var offset = start;
    while (offset < total) {
      final chunk = await repository.readChapterRange(
        chapterId,
        offset,
        (total - offset).clamp(0, scanSize),
      );
      if (chunk.isEmpty) break;
      final newline = RegExp(r'\r\n?|\n').firstMatch(chunk);
      if (newline != null) {
        buffer.write(chunk.substring(0, newline.start));
        break;
      }
      buffer.write(chunk);
      offset += chunk.length;
    }
    return buffer.toString().trim();
  }

  Future<bool> _isMidParagraph(String chapterId, int offset) async {
    final total = await repository.getChapterTextLength(chapterId);
    if (offset <= 0 || offset >= total) return false;
    final around = await repository.readChapterRange(chapterId, offset - 1, 2);
    if (around.length < 2) return false;
    return around[0] != '\n' && around[1] != '\n';
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
