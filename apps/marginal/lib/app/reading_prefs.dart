/// 阅读偏好与书架纯逻辑。
///
/// 语义移植自 v1 `mobile/logic.ts`，全部可单测。
library;


const double minFontSize = 14;
const double maxFontSize = 30;
const double defaultFontSize = 19;

double clampFontSize(num value) =>
    value.isNaN ? defaultFontSize : value.toDouble().clamp(minFontSize, maxFontSize);

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

double scrollTopForRatio(num ratio, num scrollHeight, num clientHeight) =>
    clampRatio(ratio) * (scrollHeight - clientHeight).clamp(0, double.infinity);

bool isWorkFinished({
  required String? positionChapterId,
  required double positionRatio,
  required List<String> chapterIdsInOrder,
  double threshold = 0.98,
}) {
  if (positionChapterId == null || chapterIdsInOrder.isEmpty) return false;
  return chapterIdsInOrder.last == positionChapterId && positionRatio >= threshold;
}

String workGroupLabel(String raw) => raw.trim().substring(0, raw.trim().length.clamp(0, 30));

List<String> workGroupNames(Iterable<String> groups) {
  final names = groups.where((g) => g.trim().isNotEmpty).map((g) => g.trim()).toSet().toList()
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
  factory ParagraphFavorite.fromJson(Map<String, dynamic> j) => ParagraphFavorite(
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
  Map<String, dynamic> toJson() => {'chapterId': chapterId, 'chapterTitle': chapterTitle, 'addedAt': addedAt};
  factory ChapterBookmark.fromJson(Map<String, dynamic> j) => ChapterBookmark(
    chapterId: j['chapterId'] as String? ?? '',
    chapterTitle: j['chapterTitle'] as String? ?? '',
    addedAt: j['addedAt'] as int? ?? 0,
  );
}

/// 基于 Work.settings JSON 的收藏/书签存取（跨端持久化，替代 v1 localStorage）。
List<ParagraphFavorite> listParagraphFavorites(Map<String, dynamic> settings, String workId) =>
    ((settings['favorites.$workId'] as List?) ?? const [])
        .map((e) => ParagraphFavorite.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

({List<ParagraphFavorite> favorites, bool added}) toggleParagraphFavorite(
  Map<String, dynamic> settings,
  String workId,
  ParagraphFavorite favorite,
) {
  final favorites = listParagraphFavorites(settings, workId);
  final index = favorites.indexWhere(
    (item) => item.chapterId == favorite.chapterId && item.paraIndex == favorite.paraIndex,
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

List<ChapterBookmark> listChapterBookmarks(Map<String, dynamic> settings, String workId) =>
    ((settings['bookmarks.$workId'] as List?) ?? const [])
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
    bookmarks.insert(0, ChapterBookmark(chapterId: chapterId, chapterTitle: chapterTitle, addedAt: DateTime.now().millisecondsSinceEpoch));
    added = true;
  }
  settings['bookmarks.$workId'] = bookmarks.map((e) => e.toJson()).toList();
  return (bookmarks: bookmarks, added: added);
}

({String chapterId, double ratio})? loadReadingPosition(Map<String, dynamic> settings) {
  final raw = settings['reading'];
  if (raw is! Map) return null;
  final chapterId = raw['chapterId'];
  final ratio = raw['ratio'];
  if (chapterId is! String || ratio is! num) return null;
  return (chapterId: chapterId, ratio: clampRatio(ratio));
}

void saveReadingPosition(Map<String, dynamic> settings, String chapterId, double ratio) {
  settings['reading'] = {'chapterId': chapterId, 'ratio': clampRatio(ratio)};
}
