/// 阅读偏好与书架纯逻辑。
///
/// 语义移植自 v1 `mobile/logic.ts`，全部可单测。
library;

import 'chapter_window.dart';

const double minFontSize = 14;
const double maxFontSize = 30;
const double defaultFontSize = 19;

double clampFontSize(num value) => value.isNaN
    ? defaultFontSize
    : value.toDouble().clamp(minFontSize, maxFontSize);

const int minAutoSpeed = 20;
const int maxAutoSpeed = 180;
const int defaultAutoSpeed = 60;

int clampAutoScrollSpeed(num value) {
  if (!value.isFinite) return defaultAutoSpeed;
  return value.round().clamp(minAutoSpeed, maxAutoSpeed);
}

enum ReaderTheme { paper, eyecare, dark }

ReaderTheme parseReaderTheme(String? value) => switch (value) {
  'eyecare' => ReaderTheme.eyecare,
  'dark' => ReaderTheme.dark,
  _ => ReaderTheme.paper,
};

ReaderTheme nextReaderTheme(ReaderTheme theme) => switch (theme) {
  ReaderTheme.paper => ReaderTheme.eyecare,
  ReaderTheme.eyecare => ReaderTheme.dark,
  ReaderTheme.dark => ReaderTheme.paper,
};

double clampRatio(num value) =>
    value.isNaN ? 0 : value.clamp(0.0, 1.0).toDouble();

/// 内容不足一屏时视为整章已读（短尾声章也能拿到“读完”判定）。
double scrollRatio(num scrollTop, num scrollHeight, num clientHeight) {
  final max = scrollHeight - clientHeight;
  if (max <= 0) return 1;
  return clampRatio(scrollTop / max);
}

/// 按章节正文长度加权汇总全本阅读进度。
double workProgressRatio({
  required List<int> chapterWeights,
  required int chapterIndex,
  required num chapterRatio,
}) {
  if (chapterWeights.isEmpty ||
      chapterIndex < 0 ||
      chapterIndex >= chapterWeights.length) {
    return 0;
  }
  final weights = chapterWeights
      .map((weight) => weight > 0 ? weight.toDouble() : 1.0)
      .toList(growable: false);
  final total = weights.fold<double>(0, (sum, value) => sum + value);
  final before = weights
      .take(chapterIndex)
      .fold<double>(0, (sum, value) => sum + value);
  return clampRatio(
    (before + weights[chapterIndex] * clampRatio(chapterRatio)) / total,
  );
}

({int chapterIndex, double chapterRatio}) workProgressTarget({
  required List<int> chapterWeights,
  required num workRatio,
}) {
  if (chapterWeights.isEmpty) return (chapterIndex: 0, chapterRatio: 0);
  final weights = chapterWeights
      .map((weight) => weight > 0 ? weight.toDouble() : 1.0)
      .toList(growable: false);
  final total = weights.fold<double>(0, (sum, value) => sum + value);
  var remaining = clampRatio(workRatio) * total;
  for (var i = 0; i < weights.length; i++) {
    if (remaining <= weights[i] || i == weights.length - 1) {
      return (
        chapterIndex: i,
        chapterRatio: clampRatio(remaining / weights[i]),
      );
    }
    remaining -= weights[i];
  }
  return (chapterIndex: weights.length - 1, chapterRatio: 1);
}

double scrollTopForRatio(num ratio, num scrollHeight, num clientHeight) =>
    clampRatio(ratio) * (scrollHeight - clientHeight).clamp(0, double.infinity);

const double minLineHeight = 1.6;
const double maxLineHeight = 2.2;
const double defaultLineHeight = 1.8;

double clampLineHeight(num value) => value.isNaN
    ? defaultLineHeight
    : value.toDouble().clamp(minLineHeight, maxLineHeight);

/// 在窗口化阅读里，scroll 像素是相对于当前窗口段的。
/// 这一组函数把"窗口内滚动比例"和"章节级比例"在一个地方互转，
/// 避免 reader 调用方各自推导却把章节比例误喂给窗口局部函数。
class WindowPositioning {
  const WindowPositioning({required this.window, required this.viewport});

  final ChapterWindow window;
  final double viewport;

  /// 当前滚动位置 → 章节级比例（0..1，章节末尾 = 1）。
  /// 当章节只有一个窗口、且内容不足一屏时，按 `scrollRatio` 的约定视为 1。
  double chapterRatioFromScroll(double scrollOffset, double maxScrollExtent) {
    final local = scrollRatio(
      scrollOffset,
      maxScrollExtent + viewport,
      viewport,
    );
    if (window.totalLength == 0) return local;
    return (window.start + (window.end - window.start) * local) /
        window.totalLength;
  }

  /// 章节级比例 → 窗口内比例（0..1，落在当前窗口的局部坐标）。
  /// 当目标在当前窗口之外时，会按 0/1 截断；调用方负责决定是否需要切窗口。
  double localRatioForChapterRatio(double chapterRatio) {
    if (window.end == window.start) return 0;
    final global = clampRatio(chapterRatio) * window.totalLength;
    return ((global - window.start) / (window.end - window.start)).clamp(
      0.0,
      1.0,
    );
  }

  /// 章节级比例 → 像素滚动位置（直接喂给 `ScrollController.jumpTo`）。
  double scrollOffsetForChapterRatio(double chapterRatio, double maxScrollExtent) {
    final local = localRatioForChapterRatio(chapterRatio);
    return scrollTopForRatio(local, maxScrollExtent + viewport, viewport);
  }

  /// 当前滚动位置 → 章节内的全局字节偏移（用于跨窗口切换时保持上下文）。
  int globalOffsetFromScroll(double scrollOffset, double maxScrollExtent) {
    if (maxScrollExtent <= 0) return window.start;
    final local = (scrollOffset / maxScrollExtent).clamp(0.0, 1.0);
    return window.start + ((window.end - window.start) * local).round();
  }

  /// 章节内全局字节偏移 → 像素滚动位置（窗口平移后恢复阅读位置）。
  double scrollOffsetForGlobalOffset(int globalOffset, double maxScrollExtent) {
    if (window.end == window.start) return 0;
    final local = ((globalOffset - window.start) / (window.end - window.start))
        .clamp(0.0, 1.0);
    return local * maxScrollExtent.clamp(0.0, double.infinity);
  }

  /// 章节级比例对应的全局字节偏移是否落在当前窗口内。
  bool containsChapterRatio(double chapterRatio) {
    final global = clampRatio(chapterRatio) * window.totalLength;
    return global >= window.start && global <= window.end;
  }
}

bool isWorkFinished({
  required String? positionChapterId,
  required double positionRatio,
  required List<String> chapterIdsInOrder,
  double threshold = 0.98,
}) {
  if (positionChapterId == null || chapterIdsInOrder.isEmpty) return false;
  return chapterIdsInOrder.last == positionChapterId &&
      positionRatio >= threshold;
}

String workGroupLabel(String raw) =>
    raw.trim().substring(0, raw.trim().length.clamp(0, 30));

List<String> workGroupNames(Iterable<String> groups) {
  final names =
      groups
          .where((g) => g.trim().isNotEmpty)
          .map((g) => g.trim())
          .toSet()
          .toList()
        ..sort((a, b) => a.compareTo(b));
  return names;
}

class ParagraphFavorite {
  final String chapterId, chapterTitle, text;
  final int paraIndex, savedAt;
  const ParagraphFavorite({
    required this.chapterId,
    required this.chapterTitle,
    required this.paraIndex,
    required this.text,
    required this.savedAt,
  });
  Map<String, dynamic> toJson() => {
    'chapterId': chapterId,
    'chapterTitle': chapterTitle,
    'paraIndex': paraIndex,
    'text': text,
    'savedAt': savedAt,
  };
  factory ParagraphFavorite.fromJson(Map<String, dynamic> j) =>
      ParagraphFavorite(
        chapterId: j['chapterId'] as String? ?? '',
        chapterTitle: j['chapterTitle'] as String? ?? '',
        paraIndex: (j['paraIndex'] as num?)?.toInt() ?? 0,
        text: j['text'] as String? ?? '',
        savedAt: j['savedAt'] as int? ?? 0,
      );
}

class ChapterBookmark {
  final String chapterId, chapterTitle;
  final int addedAt;
  const ChapterBookmark({
    required this.chapterId,
    required this.chapterTitle,
    required this.addedAt,
  });
  Map<String, dynamic> toJson() => {
    'chapterId': chapterId,
    'chapterTitle': chapterTitle,
    'addedAt': addedAt,
  };
  factory ChapterBookmark.fromJson(Map<String, dynamic> j) => ChapterBookmark(
    chapterId: j['chapterId'] as String? ?? '',
    chapterTitle: j['chapterTitle'] as String? ?? '',
    addedAt: j['addedAt'] as int? ?? 0,
  );
}

/// 基于 Work.settings JSON 的收藏/书签存取（跨端持久化，替代 v1 localStorage）。
List<ParagraphFavorite> listParagraphFavorites(
  Map<String, dynamic> settings,
  String workId,
) => ((settings['favorites.$workId'] as List?) ?? const [])
    .map((e) => ParagraphFavorite.fromJson(Map<String, dynamic>.from(e as Map)))
    .toList();

({List<ParagraphFavorite> favorites, bool added}) toggleParagraphFavorite(
  Map<String, dynamic> settings,
  String workId,
  ParagraphFavorite favorite,
) {
  final favorites = listParagraphFavorites(settings, workId);
  final index = favorites.indexWhere(
    (item) =>
        item.chapterId == favorite.chapterId &&
        item.paraIndex == favorite.paraIndex,
  );
  var added = false;
  if (index >= 0) {
    favorites.removeAt(index);
  } else {
    favorites.insert(0, favorite);
    added = true;
  }
  settings['favorites.$workId'] = favorites.map((e) => e.toJson()).toList();
  return (favorites: favorites, added: added);
}

List<ChapterBookmark> listChapterBookmarks(
  Map<String, dynamic> settings,
  String workId,
) => ((settings['bookmarks.$workId'] as List?) ?? const [])
    .map((e) => ChapterBookmark.fromJson(Map<String, dynamic>.from(e as Map)))
    .toList();

({List<ChapterBookmark> bookmarks, bool added}) toggleChapterBookmark(
  Map<String, dynamic> settings,
  String workId,
  String chapterId,
  String chapterTitle,
) {
  final bookmarks = listChapterBookmarks(settings, workId);
  final index = bookmarks.indexWhere((item) => item.chapterId == chapterId);
  var added = false;
  if (index >= 0) {
    bookmarks.removeAt(index);
  } else {
    bookmarks.insert(
      0,
      ChapterBookmark(
        chapterId: chapterId,
        chapterTitle: chapterTitle,
        addedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    added = true;
  }
  settings['bookmarks.$workId'] = bookmarks.map((e) => e.toJson()).toList();
  return (bookmarks: bookmarks, added: added);
}

({String chapterId, double ratio})? loadReadingPosition(
  Map<String, dynamic> settings,
) {
  final raw = settings['reading'];
  if (raw is! Map) return null;
  final chapterId = raw['chapterId'];
  final ratio = raw['ratio'];
  if (chapterId is! String || ratio is! num) return null;
  return (chapterId: chapterId, ratio: clampRatio(ratio));
}

void saveReadingPosition(
  Map<String, dynamic> settings,
  String chapterId,
  double ratio,
) {
  settings['reading'] = {'chapterId': chapterId, 'ratio': clampRatio(ratio)};
}
