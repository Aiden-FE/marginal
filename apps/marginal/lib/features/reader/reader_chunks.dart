class ReaderChunk {
  const ReaderChunk({
    required this.paraIndex,
    required this.text,
    required this.start,
    required this.end,
    required this.isLastFragment,
  });

  final int paraIndex;
  final String text;
  final int start;
  final int end;
  final bool isLastFragment;
}

/// 将逻辑段落拆成可延迟构建的视觉片段。
///
/// [paraIndex] 始终指向原始段落；片段只改变渲染边界，不改变收藏、锚点
/// 或 AI 操作的身份。按 UTF-16 code unit 向后寻找安全边界，避免把代理对
/// 拆开；组合字符交由 Flutter 文本布局继续处理。
List<ReaderChunk> buildReaderChunks(
  List<String> paragraphs, {
  int maxCodeUnits = 4000,
}) {
  final chunks = <ReaderChunk>[];
  final limit = maxCodeUnits < 2 ? 2 : maxCodeUnits;
  for (var paraIndex = 0; paraIndex < paragraphs.length; paraIndex++) {
    final paragraph = paragraphs[paraIndex];
    if (paragraph.length <= limit) {
      chunks.add(
        ReaderChunk(
          paraIndex: paraIndex,
          text: paragraph,
          start: 0,
          end: paragraph.length,
          isLastFragment: true,
        ),
      );
      continue;
    }
    var start = 0;
    while (start < paragraph.length) {
      var end = (start + limit).clamp(start + 1, paragraph.length);
      if (end < paragraph.length && end > start) {
        final previous = paragraph.codeUnitAt(end - 1);
        final next = paragraph.codeUnitAt(end);
        if (_isHighSurrogate(previous) && _isLowSurrogate(next)) end--;
      }
      if (end <= start) {
        end = (start + limit).clamp(start + 1, paragraph.length);
      }
      chunks.add(
        ReaderChunk(
          paraIndex: paraIndex,
          text: paragraph.substring(start, end),
          start: start,
          end: end,
          isLastFragment: end == paragraph.length,
        ),
      );
      start = end;
    }
  }
  return chunks;
}

bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;
bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;
