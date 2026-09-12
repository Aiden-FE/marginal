/// 段落切分：单换行即分段（TXT 小说惯例），空行/多换行兼容。
/// 阅读器与插图锚点共用，保证 paraIndex 一致。
List<String> splitParagraphs(String text) => [
  for (final line in text.split(RegExp(r'\r\n|\r|\n')))
    if (line.trim().isNotEmpty) line.trim(),
];

String normalizeChapterText(String text) =>
    '${splitParagraphs(text).join('\n\n')}\n';
