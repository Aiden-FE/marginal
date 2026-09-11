class SplitPoint {
  final int line;
  final String title;
  final double confidence;
  const SplitPoint(this.line, this.title, this.confidence);
}

List<SplitPoint> splitByHeuristics(String text) {
  final lines = text.split(RegExp(r'\r\n|\r|\n'));
  final points = <SplitPoint>[];
  final bodyLens = lines.map((l) => l.length).toList();
  final nonEmpty = bodyLens.where((l) => l > 0).toList();
  final avg = nonEmpty.isEmpty
      ? 40.0
      : nonEmpty.reduce((a, b) => a + b) / nonEmpty.length;
  final titlePatterns = [
    RegExp(r'^\s*(第\s*[0-9一二三四五六七八九十百千两零〇]+\s*[章回节卷集部篇])\s*[:：、\s]*(.*)$'),
    RegExp(
      r'^\s*(Chapter|CHAPTER|chapter)\s+(\d+|[IVXLCivxlc]+)(?:\s*[.:：\-\s]\s*(.*))?$',
    ),
    RegExp(r'^\s*([0-9]{1,4})\s*[、.．:：]\s*(\S.{0,30})$'),
    RegExp(r'^\s*[（(]\s*([0-9一二三四五六七八九十]+)\s*[)）]\s*(\S.{0,30})$'),
    RegExp(r'^\s*(序章|序言|楔子|引子|尾声|终章|番外)\s*.*$'),
  ];
  final bases = [0.95, 0.9, 0.55, 0.4, 0.9];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final t = line.trim();
    if (t.isEmpty) continue;
    SplitPoint? matched;
    for (var p = 0; p < titlePatterns.length; p++) {
      final m = titlePatterns[p].firstMatch(line);
      if (m == null) continue;
      final weak = bases[p] < 0.8;
      final prevBlank = i == 0 || lines[i - 1].trim().isEmpty;
      if (weak && !prevBlank) continue;
      final title = m
          .groups([1, 2])
          .whereType<String>()
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      var conf = bases[p];
      if (line.length > 50) conf -= 0.35;
      final next = lines
          .skip(i + 1)
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
      if (next.length > 30) conf = (conf + 0.05).clamp(0, 1).toDouble();
      matched = SplitPoint(
        i,
        title.length > 60 ? title.substring(0, 60) : title,
        conf.clamp(0.05, 1),
      );
      break;
    }
    if (matched == null) {
      final prevBlank = i == 0 || lines[i - 1].trim().isEmpty;
      final short = t.length <= (20 > avg * 0.35 ? 20 : avg * 0.35);
      final noPunct = !RegExp(r'[。！？…」"’】,.!?]$').hasMatch(t);
      final nextLong =
          (i + 1 < lines.length ? lines[i + 1].length : 0) > avg * 0.8;
      if (prevBlank && short && noPunct && nextLong && t.length >= 4) {
        matched = SplitPoint(i, t.length > 60 ? t.substring(0, 60) : t, 0.2);
      }
    }
    if (matched != null) points.add(matched);
  }
  return points;
}

List<String> splitTextLines(String text) => text.split(RegExp(r'\r\n|\r|\n'));

String sliceChapterText(String text, int start, int end) {
  final ls = splitTextLines(text);
  return '${ls.sublist(start.clamp(0, ls.length), end.clamp(0, ls.length)).join('\n').trim()}\n';
}

class ProposedChapter {
  final String title;
  final int startLine, endLine;
  final bool lowConfidence;
  const ProposedChapter(
    this.title,
    this.startLine,
    this.endLine,
    this.lowConfidence,
  );
}

List<ProposedChapter> assembleChapters(String text, List<SplitPoint> points) {
  final lines = splitTextLines(text);
  final total = lines.length;
  final kept = points.where((p) => p.confidence >= 0.25).toList();
  if (kept.isEmpty) return [ProposedChapter('全文', 0, total, true)];
  final out = <ProposedChapter>[];
  for (var i = 0; i < kept.length; i++) {
    final p = kept[i];
    final start = (i == 0 && p.line > 0) ? 0 : p.line;
    final end = i + 1 < kept.length ? kept[i + 1].line : total;
    out.add(ProposedChapter(p.title, start, end, p.confidence < 0.6));
  }
  return out;
}
