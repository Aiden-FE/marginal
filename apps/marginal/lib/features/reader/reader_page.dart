import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../app/chapter_window.dart';
import '../../app/marginal_theme.dart';
import '../../app/reading_prefs.dart' as prefs;
import '../../app/reader_projection.dart';
import '../../app/paragraphs.dart';
import '../../app/share.dart';
import '../../app/platform_services.dart';
import '../../app/reading_stats.dart';
import '../../app/vector_icons.dart';
import '../../app/poster_capture.dart';
import '../../core/types.dart';
import 'chrome_icon_button.dart';
import 'reader_chapter_sheet.dart';
import 'reader_chunks.dart';
import 'reader_epub_fidelity.dart';
import 'reader_favorites_sheet.dart';
import 'reader_paragraph_sheet.dart';
import 'reader_poster_sheet.dart';
import 'reader_settings_sheet.dart';
import 'reader_theme.dart' show ReaderTheme;

/// 阅读器 —— 沉浸式正文 + 自动阅读 + 设置/书签/收藏/分享（v1 语义对齐）。
///
/// 偏好与位置全部持久化到 `Work.settings`：
/// `reader.fontSize` / `reader.lineHeight` / `reader.theme` / `reader.autoSpeed`、
/// `reading`（chapterId+ratio）、`favorites.<workId>`、`bookmarks.<workId>`、
/// `reader`（chapterId，供书库“继续阅读”入口）。
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.services,
    required this.work,
    required this.initialChapterId,
    this.onOpenEntities,
    this.onOpenIllustrations,
    this.onIllustrateParagraph,
    this.onIllustrateParagraphAt,
    this.shareService,
    this.onPosterEncoder,
  });

  final PlatformServices services;
  final Work work;
  final String initialChapterId;

  /// 实体 / 插图入口（可选；未注入则不显示对应按钮）。
  final void Function(BuildContext context)? onOpenEntities;
  final void Function(BuildContext context)? onOpenIllustrations;

  /// AI 插图回调；未注入时点击“AI 插图”提示先配置供应商。
  final void Function(String paragraph)? onIllustrateParagraph;
  final FutureOr<void> Function(
    String chapterId,
    int paraIndex,
    String paragraph,
  )?
  onIllustrateParagraphAt;

  /// 分享服务（测试注入 fake；默认走 share_plus）。
  final ShareService? shareService;

  /// 海报 PNG 编码器（可注入以便测试）。
  final Future<Uint8List> Function({
    required String workTitle,
    required String chapterTitle,
    required String text,
    double pixelRatio,
  })?
  onPosterEncoder;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _chromeTimeout = Duration(milliseconds: 3500);
  static const _chromeDuration = Duration(milliseconds: 250);
  static const _chapterDwell = Duration(milliseconds: 1500);
  static const _positionSaveInterval = Duration(milliseconds: 300);
  static const _defaultLineHeight = 1.8;
  static const _gold = Color(0xFFD9A13C);

  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _paraKeys = {};
  late final DateTime _sessionStartedAt = DateTime.now();
  late DateTime _statsFlushedAt = _sessionStartedAt;
  Timer? _statsHeartbeat;

  List<Chapter> _chapters = const [];
  List<String> _paragraphs = const [];
  List<ReaderChunk> _chunks = const [];
  Map<int, List<Uint8List>> _images = {};
  ChapterWindow? _textWindow;
  bool _loadingWindow = false;
  bool _fidelityAvailable = false;
  bool _fidelityMode = false;
  String? _fidelitySrcdoc;
  int _fidelityGeneration = 0;
  int _openGeneration = 0;
  static const int _chunkBudget = 4000;
  int _index = 0;
  bool _loading = true;
  double _liveRatio = 0;
  double? _previewWorkRatio;

  /// 进度只重建悬浮卡片这一小块：自动阅读逐帧滚动时不再整页 setState。
  final ValueNotifier<double> _displayWorkRatio = ValueNotifier<double>(0);
  int _progressJumpGeneration = 0;
  bool _resumeAutoAfterProgressDrag = false;
  List<int> _chapterWeights = const [];
  late final Map<String, dynamic> _settings = Map<String, dynamic>.of(
    widget.work.settings,
  );

  // 沉浸 chrome：显示 3.5s 自动收起，交互续期，弹层打开时暂停。
  bool _chromeVisible = true;
  Timer? _chromeTimer;
  int _sheetsOpen = 0;

  // 自动阅读：逐帧等速滚动，章末停留 1.5s 切下一章，弹层打开暂停。
  bool _autoRunning = false;
  bool _autoPausedBySheet = false;
  Ticker? _autoTicker;
  Duration _autoLastElapsed = Duration.zero;
  Timer? _chapterEndTimer;

  // 阅读位置：滚动节流 300ms 保存。
  Timer? _positionSaveTimer;

  late final ReaderProjectionService _projectionService =
      ReaderProjectionService(widget.services.repository);
  late final ChapterWindowSource _windowSource = ChapterWindowSource(
    widget.services.repository,
  );
  late final EpubFidelitySource _fidelitySource = EpubFidelitySource(
    widget.services.repository,
  );
  late final ShareService _share =
      widget.shareService ?? const SharePlusService();

  // ---- 设置读取 ----

  double get _fontSize => prefs.clampFontSize(
    (_settings['reader.fontSize'] as num?) ?? prefs.defaultFontSize,
  );

  double get _lineHeight {
    final value = (_settings['reader.lineHeight'] as num?)?.toDouble();
    if (value == null || value.isNaN) return _defaultLineHeight;
    return value.clamp(1.6, 2.2).toDouble();
  }

  ReaderTheme get _theme => switch (_settings['reader.theme'] as String?) {
    'eyecare' => ReaderTheme.eyecare,
    'dark' => ReaderTheme.dark,
    _ => ReaderTheme.paper,
  };

  int get _autoSpeed => prefs.clampAutoScrollSpeed(
    (_settings['reader.autoSpeed'] as num?) ?? prefs.defaultAutoSpeed,
  );

  List<prefs.ParagraphFavorite> get _favorites =>
      prefs.listParagraphFavorites(_settings, widget.work.id);

  List<prefs.ChapterBookmark> get _bookmarks =>
      prefs.listChapterBookmarks(_settings, widget.work.id);

  bool _isFavorite(int paraIndex) => _favorites.any(
    (f) => f.chapterId == _currentChapter?.id && f.paraIndex == paraIndex,
  );

  bool _isBookmarked(String chapterId) =>
      _bookmarks.any((b) => b.chapterId == chapterId);

  Chapter? get _currentChapter => _chapters.isEmpty ? null : _chapters[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _statsHeartbeat = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _flushReadingStats(),
    );
    _scrollController.addListener(_onScroll);
    _autoTicker = createTicker(_onAutoTick);
    _bumpChrome();
    _load();
  }

  @override
  void dispose() {
    _flushReadingStats();
    _statsHeartbeat?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _chromeTimer?.cancel();
    _autoTicker?.dispose();
    _displayWorkRatio.dispose();
    _chapterEndTimer?.cancel();
    _positionSaveTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _flushReadingStats();
    }
  }

  Future<void> _flushReadingStats() async {
    final now = DateTime.now();
    final elapsed = now.difference(_statsFlushedAt).inSeconds;
    if (elapsed < 60) return;
    final minutes = elapsed ~/ 60;
    recordReadingMinutes(_settings, now: now, minutes: minutes);
    _statsFlushedAt = _statsFlushedAt.add(Duration(minutes: minutes));
    await _persistSettings();
  }

  // ---- 数据装载 ----

  Future<void> _load() async {
    final chapters = await _projectionService.chapters(widget.work.id);
    if (chapters.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    _chapterWeights = [
      for (final chapter in chapters)
        chapter.wordCount > 0 ? chapter.wordCount : 1,
    ];
    // 优先恢复上次阅读位置章节；否则用入口指定章节。
    final position = prefs.loadReadingPosition(_settings);
    var index = position == null
        ? -1
        : chapters.indexWhere((c) => c.id == position.chapterId);
    if (index < 0) {
      index = chapters.indexWhere((c) => c.id == widget.initialChapterId);
    }
    if (index < 0) index = 0;
    await _open(chapters, index, restorePosition: true);
  }

  Future<void> _open(
    List<Chapter> chapters,
    int index, {
    bool restorePosition = false,
    double? targetRatio,
  }) async {
    final generation = ++_openGeneration;
    ++_fidelityGeneration;
    // 切章前把上一章的滚动位置落库.
    _positionSaveTimer?.cancel();
    _positionSaveTimer = null;
    await _savePositionNow();

    final position = prefs.loadReadingPosition(_settings);
    final target =
        targetRatio ??
        (restorePosition &&
                position != null &&
                position.chapterId == chapters[index].id
            ? position.ratio
            : 0.0);
    final results = await Future.wait([
      _projectionService.projection(widget.work.id, chapters[index]),
      _windowSource.load(chapters[index].id, ratio: target),
      if (epubFidelitySupported)
        _fidelitySource.isAvailable(widget.work.id, chapters[index].id),
    ]);
    final projection = results[0] as ChapterProjection;
    final window = results[1] as ChapterWindow;
    final fidelityAvailable = epubFidelitySupported && results[2] == true;
    if (!mounted || generation != _openGeneration) return;
    setState(() {
      _chapters = chapters;
      _index = index;
      _textWindow = window;
      _paragraphs = _splitParagraphs(window.text);
      _chunks = [
        for (final chunk in buildReaderChunks(
          _paragraphs,
          maxCodeUnits: _chunkBudget,
        ))
          ReaderChunk(
            paraIndex: chunk.paraIndex + window.paragraphBase,
            text: chunk.text,
            start: chunk.start,
            end: chunk.end,
            isLastFragment: chunk.isLastFragment,
          ),
      ];
      _images = Map.of(projection.images);
      _fidelityAvailable = fidelityAvailable;
      if (!fidelityAvailable) _fidelityMode = false;
      _fidelitySrcdoc = null;
      _paraKeys.clear();
      _loading = false;
    });
    _settings['reader'] = {'chapterId': chapters[index].id};
    try {
      await _persistSettings();
    } catch (_) {
      // A storage connection failure must never block the reader surface.
    }
    if (_fidelityMode && fidelityAvailable) {
      // 原版排版按需加载：不在切章路径常驻整章 XHTML 字节。
      final chapter = chapters[index];
      final doc = await _fidelitySource.load(widget.work.id, chapter);
      if (!mounted ||
          generation != _openGeneration ||
          _currentChapter?.id != chapter.id) {
        return;
      }
      setState(() {
        _fidelitySrcdoc = doc == null ? null : epubFidelitySrcdoc(doc);
      });
    }
    final positioned = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        positioned.complete();
        return;
      }
      final p = _scrollController.position;
      final localRatio = window.end == window.start
          ? 0.0
          : ((target * window.totalLength - window.start) /
                    (window.end - window.start))
                .clamp(0.0, 1.0);
      _scrollController.jumpTo(
        prefs.scrollTopForRatio(
          localRatio,
          p.maxScrollExtent + p.viewportDimension,
          p.viewportDimension,
        ),
      );
      _updateProgress(_scrollController.offset);
      positioned.complete();
    });
    await positioned.future;
  }

  Future<void> _openChapterById(String chapterId) async {
    final index = _chapters.indexWhere((c) => c.id == chapterId);
    if (index < 0 || index == _index) return;
    await _open(_chapters, index);
  }

  List<String> _splitParagraphs(String value) => splitParagraphs(value);

  // ---- 设置持久化 ----

  Future<void> _persistSettings() async {
    await widget.services.repository.putWork(
      Work(
        id: widget.work.id,
        title: widget.work.title,
        author: widget.work.author,
        importSource: widget.work.importSource,
        createdAt: widget.work.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        settings: Map<String, dynamic>.of(_settings),
      ),
    );
  }

  Future<void> _setFontSize(double value) async {
    _settings['reader.fontSize'] = prefs.clampFontSize(value);
    setState(() {});
    await _persistSettings();
  }

  Future<void> _setLineHeight(double value) async {
    _settings['reader.lineHeight'] = value.clamp(1.6, 2.2).toDouble();
    setState(() {});
    await _persistSettings();
  }

  Future<void> _setTheme(ReaderTheme theme) async {
    _settings['reader.theme'] = theme.name;
    setState(() {});
    await _persistSettings();
  }

  Future<void> _setFidelityMode(bool enabled) async {
    if (enabled == _fidelityMode) return;
    final generation = ++_fidelityGeneration;
    if (enabled) {
      if (!_fidelityAvailable) return;
      _stopAuto();
      final chapter = _currentChapter;
      if (chapter == null) return;
      setState(() {
        _fidelityMode = true;
        _fidelitySrcdoc = null;
      });
      await _savePositionNow();
      final doc = await _fidelitySource.load(widget.work.id, chapter);
      if (!mounted ||
          generation != _fidelityGeneration ||
          _currentChapter?.id != chapter.id ||
          !_fidelityMode) {
        return;
      }
      if (doc == null) {
        setState(() => _fidelityMode = false);
        _snack('这一章没有可用的 EPUB 原版排版');
        return;
      }
      setState(() => _fidelitySrcdoc = epubFidelitySrcdoc(doc));
      return;
    }
    setState(() {
      _fidelityMode = false;
      _fidelitySrcdoc = null;
    });
    await _open(_chapters, _index, restorePosition: true);
  }

  Future<void> _setAutoSpeed(int value) async {
    _settings['reader.autoSpeed'] = prefs.clampAutoScrollSpeed(value);
    setState(() {});
    await _persistSettings();
  }

  // ---- 沉浸 chrome ----

  void _bumpChrome() {
    if (!_chromeVisible || _sheetsOpen > 0) return;
    _chromeTimer?.cancel();
    _chromeTimer = Timer(_chromeTimeout, () {
      if (mounted) setState(() => _chromeVisible = false);
    });
  }

  void _showChrome() {
    if (_chromeVisible) {
      _bumpChrome();
      return;
    }
    setState(() => _chromeVisible = true);
    _bumpChrome();
  }

  void _toggleChrome() {
    if (!_chromeVisible) {
      _showChrome();
      return;
    }
    setState(() => _chromeVisible = false);
    _chromeTimer?.cancel();
  }

  void _updateProgress(double scrollTop) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final localRatio = prefs.scrollRatio(
      scrollTop,
      position.maxScrollExtent + position.viewportDimension,
      position.viewportDimension,
    );
    final window = _textWindow;
    final chapterRatio = window == null || window.totalLength == 0
        ? localRatio
        : (window.start + (window.end - window.start) * localRatio) /
              window.totalLength;
    final work = prefs.workProgressRatio(
      chapterWeights: _chapterWeights,
      chapterIndex: _index,
      chapterRatio: chapterRatio,
    );
    _liveRatio = work;
    if (_previewWorkRatio == null &&
        (work - _displayWorkRatio.value).abs() >= 0.0005) {
      _displayWorkRatio.value = work;
    }
  }

  void _onScroll() {
    if (_chromeVisible && !_autoRunning) _bumpChrome();
    if (_scrollController.hasClients) {
      _updateProgress(_scrollController.offset);
    }
    _schedulePositionSave();
    _maybeShiftWindow();
  }

  Future<void> _maybeShiftWindow() async {
    final window = _textWindow;
    final chapter = _currentChapter;
    if (_loadingWindow ||
        window == null ||
        chapter == null ||
        !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final nearEnd =
        position.pixels >=
        position.maxScrollExtent - position.viewportDimension * 1.5;
    final nearStart = position.pixels <= position.viewportDimension * .5;
    int? targetOffset;
    if (nearEnd && window.end < window.totalLength) {
      targetOffset = window.end + 1;
    }
    if (nearStart && window.start > 0) {
      targetOffset = (window.start - 1).clamp(0, window.totalLength);
    }
    if (targetOffset == null) return;
    _loadingWindow = true;
    final localRatio = position.maxScrollExtent <= 0
        ? 0.0
        : (position.pixels / position.maxScrollExtent).clamp(0.0, 1.0);
    final globalOffset =
        window.start + ((window.end - window.start) * localRatio).round();
    final next = await _windowSource.load(chapter.id, offset: targetOffset);
    if (!mounted || _currentChapter?.id != chapter.id) {
      _loadingWindow = false;
      return;
    }
    setState(() {
      _textWindow = next;
      _paragraphs = _splitParagraphs(next.text);
      _chunks = [
        for (final chunk in buildReaderChunks(
          _paragraphs,
          maxCodeUnits: _chunkBudget,
        ))
          ReaderChunk(
            paraIndex: chunk.paraIndex + next.paragraphBase,
            text: chunk.text,
            start: chunk.start,
            end: chunk.end,
            isLastFragment: chunk.isLastFragment,
          ),
      ];
      _paraKeys.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final local = next.end == next.start
            ? 0.0
            : ((globalOffset - next.start) / (next.end - next.start)).clamp(
                0.0,
                1.0,
              );
        _scrollController.jumpTo(
          (local * _scrollController.position.maxScrollExtent).clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          ),
        );
      }
      _loadingWindow = false;
    });
  }

  // ---- 阅读位置 ----

  void _schedulePositionSave() {
    // 滚动节流：300ms 内至多保存一次；自动阅读时放宽到 1s，避免持续 IndexedDB 写入。
    _positionSaveTimer ??= Timer(
      _autoRunning ? const Duration(milliseconds: 1000) : _positionSaveInterval,
      () {
        _positionSaveTimer = null;
        _savePositionNow();
      },
    );
  }

  Future<void> _savePositionNow() async {
    final chapter = _currentChapter;
    if (chapter == null || !_scrollController.hasClients) return;
    final p = _scrollController.position;
    prefs.saveReadingPosition(
      _settings,
      chapter.id,
      (() {
        final localRatio = prefs.scrollRatio(
          _scrollController.offset,
          p.maxScrollExtent + p.viewportDimension,
          p.viewportDimension,
        );
        final window = _textWindow;
        return window == null || window.totalLength == 0
            ? localRatio
            : (window.start + (window.end - window.start) * localRatio) /
                  window.totalLength;
      })(),
    );
    await _persistSettings();
  }

  // ---- 弹层 ----

  Future<T?> _showSheet<T>(WidgetBuilder builder) async {
    _sheetsOpen++;
    _chromeTimer?.cancel();
    _pauseAutoForSheet();
    try {
      return await showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: builder,
      );
    } finally {
      _sheetsOpen = (_sheetsOpen - 1).clamp(0, 1 << 30);
      if (mounted) {
        if (_chromeVisible) _bumpChrome();
        _resumeAutoAfterSheet();
        setState(() {});
      }
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  // ---- 段落交互 ----

  GlobalKey _paraKey(int index) => _paraKeys.putIfAbsent(index, GlobalKey.new);

  Future<void> _showParagraphSheet(int paraIndex) async {
    final chapter = _currentChapter;
    final window = _textWindow;
    if (chapter == null || window == null) return;
    final localIndex = paraIndex - window.paragraphBase;
    if (localIndex < 0 || localIndex >= _paragraphs.length) return;
    final localParagraph = _paragraphs[localIndex];
    final paragraph = window.startsMidParagraph || window.endsMidParagraph
        ? await _windowSource.paragraphText(chapter.id, paraIndex)
        : localParagraph;
    if (!mounted) return;
    await _showSheet(
      (context) => ReaderParagraphSheet(
        paragraph: paragraph,
        isFavorite: _isFavorite(paraIndex),
        onToggleFavorite: () => _toggleParagraphFavorite(paraIndex, paragraph),
        onCopy: () => _copyParagraph(paragraph),
        onPoster: () => _showPosterSheet(paragraph),
        onIllustrate:
            widget.onIllustrateParagraphAt == null &&
                widget.onIllustrateParagraph == null
            ? null
            : () => _illustrateParagraph(paragraph, paraIndex),
      ),
    );
  }

  Future<void> _toggleParagraphFavorite(int paraIndex, String paragraph) async {
    final chapter = _currentChapter;
    if (chapter == null) return;
    final result = prefs.toggleParagraphFavorite(
      _settings,
      widget.work.id,
      prefs.ParagraphFavorite(
        chapterId: chapter.id,
        chapterTitle: chapter.title,
        paraIndex: paraIndex,
        text: paragraph,
        savedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    setState(() {});
    await _persistSettings();
    _snack(result.added ? '已收藏该段落' : '已取消收藏');
  }

  Future<void> _copyParagraph(String paragraph) async {
    await Clipboard.setData(ClipboardData(text: paragraph));
    _snack('已复制到剪贴板');
  }

  Future<void> _showPosterSheet(String paragraph) async {
    final chapter = _currentChapter;
    if (chapter == null) return;
    await _showSheet(
      (context) => ReaderPosterSheet(
        workTitle: widget.work.title,
        chapterTitle: chapter.title,
        text: paragraph,
        shareService: _share,
        encoder: widget.onPosterEncoder ?? renderPosterPng,
      ),
    );
  }

  void _illustrateParagraph(String paragraph, int paraIndex) {
    final at = widget.onIllustrateParagraphAt;
    final legacy = widget.onIllustrateParagraph;
    if (at == null && legacy == null) {
      _snack('请先在设置中配置 AI 供应商，再使用 AI 插图');
      return;
    }
    if (at != null) {
      final chapter = _currentChapter;
      if (chapter != null) {
        unawaited(Future.sync(() => at(chapter.id, paraIndex, paragraph)));
      }
    } else {
      legacy!(paragraph);
    }
  }

  // ---- 收藏列表 ----

  Future<void> _showFavorites() async {
    await _showSheet(
      (context) => ReaderFavoritesSheet(
        favorites: _favorites,
        onSelect: _jumpToFavorite,
        onRemoved: (favorite) async {
          prefs.toggleParagraphFavorite(_settings, widget.work.id, favorite);
          setState(() {});
          await _persistSettings();
        },
      ),
    );
  }

  Future<void> _jumpToFavorite(prefs.ParagraphFavorite favorite) async {
    final index = _chapters.indexWhere((c) => c.id == favorite.chapterId);
    if (index < 0) return;
    if (index != _index) await _open(_chapters, index);
    var target = _chunks.indexWhere(
      (chunk) => chunk.paraIndex == favorite.paraIndex,
    );
    if (target < 0) {
      final offset = await _windowSource.paragraphOffset(
        favorite.chapterId,
        favorite.paraIndex,
      );
      final next = await _windowSource.load(favorite.chapterId, offset: offset);
      if (!mounted) return;
      setState(() {
        _textWindow = next;
        _paragraphs = _splitParagraphs(next.text);
        _chunks = [
          for (final chunk in buildReaderChunks(
            _paragraphs,
            maxCodeUnits: _chunkBudget,
          ))
            ReaderChunk(
              paraIndex: chunk.paraIndex + next.paragraphBase,
              text: chunk.text,
              start: chunk.start,
              end: chunk.end,
              isLastFragment: chunk.isLastFragment,
            ),
        ];
        _paraKeys.clear();
      });
      target = _chunks.indexWhere(
        (chunk) => chunk.paraIndex == favorite.paraIndex,
      );
    }
    if (target < 0 || !_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _paraKey(favorite.paraIndex).currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _chromeDuration,
        alignment: 0.08,
      );
    });
  }

  // ---- 章节抽屉 / 书签 ----

  Future<void> _showChapterSheet() async {
    final texts = <String, String>{};
    for (final chapter in _chapters) {
      texts[chapter.id] = await _projectionService.repository.getChapterText(
        chapter.id,
      );
    }
    if (!mounted) return;
    await _showSheet(
      (context) => ReaderChapterSheet(
        chapters: _chapters,
        chapterTexts: texts,
        currentIndex: _index,
        bookmarks: _bookmarks,
        headerActions: [
          ('段落收藏', () => _showFavorites()),
          if (widget.onOpenEntities != null)
            ('实体卡', () => widget.onOpenEntities!(context)),
          if (widget.onOpenIllustrations != null)
            ('插图', () => widget.onOpenIllustrations!(context)),
        ],
        onSelectChapter: (chapter) => _openChapterById(chapter.id),
        onBookmarkToggled: (chapter) async {
          prefs.toggleChapterBookmark(
            _settings,
            widget.work.id,
            chapter.id,
            chapter.title,
          );
          setState(() {});
          await _persistSettings();
        },
        onBookmarkRemoved: (bookmark) async {
          prefs.toggleChapterBookmark(
            _settings,
            widget.work.id,
            bookmark.chapterId,
            bookmark.chapterTitle,
          );
          setState(() {});
          await _persistSettings();
        },
      ),
    );
  }

  Future<void> _toggleChapterBookmark() async {
    final chapter = _currentChapter;
    if (chapter == null) return;
    final result = prefs.toggleChapterBookmark(
      _settings,
      widget.work.id,
      chapter.id,
      chapter.title,
    );
    setState(() {});
    await _persistSettings();
    _snack(result.added ? '已为「${chapter.title}」加书签' : '已移除书签');
  }

  // ---- 自动阅读 ----

  void _toggleAuto() => _autoRunning ? _stopAuto() : _startAuto();

  void _startAuto() {
    if (_chapters.isEmpty || _fidelityMode) return;
    setState(() => _autoRunning = true);
    // 弹层打开期间保持暂停，关闭后由 _resumeAutoAfterSheet 启动。
    if (_sheetsOpen > 0) {
      _autoPausedBySheet = true;
    } else {
      _startTicker();
    }
  }

  void _stopAuto() {
    _stopTicker();
    _chapterEndTimer?.cancel();
    _chapterEndTimer = null;
    _autoPausedBySheet = false;
    if (mounted) setState(() => _autoRunning = false);
  }

  void _startTicker() {
    _autoTicker?.stop();
    _autoLastElapsed = Duration.zero;
    _autoTicker?.start();
  }

  void _stopTicker() {
    _autoTicker?.stop();
    _autoLastElapsed = Duration.zero;
  }

  void _onAutoTick(Duration elapsed) {
    final delta = elapsed - _autoLastElapsed;
    _autoLastElapsed = elapsed;
    _autoStep(delta);
  }

  void _autoStep(Duration delta) {
    final controller = _scrollController;
    if (!controller.hasClients) return;
    final position = controller.position;
    final atTrueChapterEnd =
        _textWindow?.end == _textWindow?.totalLength &&
        controller.offset >= position.maxScrollExtent - 0.5;
    if (atTrueChapterEnd) {
      // 章末：停留 1.5s 后切下一章继续。
      _stopTicker();
      _chapterEndTimer?.cancel();
      _chapterEndTimer = Timer(_chapterDwell, _autoAdvance);
      return;
    }
    final deltaPixels = _autoSpeed * delta.inMicroseconds / 1000000;
    if (deltaPixels <= 0) return;
    controller.jumpTo(
      (controller.offset + deltaPixels).clamp(0.0, position.maxScrollExtent),
    );
  }

  Future<void> _autoAdvance() async {
    if (!_autoRunning) return;
    if (_index + 1 < _chapters.length) {
      await _open(_chapters, _index + 1);
      if (mounted && _autoRunning && _sheetsOpen == 0) _startTicker();
    } else {
      _stopAuto();
      _snack('已经是最后一章了');
    }
  }

  void _pauseAutoForSheet() {
    if (!_autoRunning) return;
    _stopTicker();
    _chapterEndTimer?.cancel();
    _chapterEndTimer = null;
    _autoPausedBySheet = true;
    _snack('弹层已打开，自动阅读暂停');
  }

  void _resumeAutoAfterSheet() {
    if (_autoRunning && _autoPausedBySheet && _sheetsOpen == 0) {
      _autoPausedBySheet = false;
      _startTicker();
    }
  }

  // ---- 三分热区：中带唤出界面，上下带翻页（滚动模式语义） ----

  void _handleReadingTapUp(TapUpDetails details) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final local = box.globalToLocal(details.globalPosition);
    final band = (local.dy * 3 / box.size.height).floor().clamp(0, 2);
    switch (band) {
      case 0:
        _pageByViewport(-1);
      case 1:
        _toggleChrome();
      case 2:
        _pageByViewport(1);
    }
  }

  void _pageByViewport(int direction) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (direction > 0) {
      final atTrueChapterEnd =
          _textWindow?.end == _textWindow?.totalLength &&
          position.pixels >= position.maxScrollExtent - 0.5;
      if (atTrueChapterEnd) {
        if (_index + 1 < _chapters.length) {
          unawaited(_open(_chapters, _index + 1));
        }
        return;
      }
      unawaited(
        _scrollController.animateTo(
          (position.pixels + position.viewportDimension).clamp(
            0.0,
            position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      if (position.pixels <= 0.5) {
        if (_index > 0) {
          unawaited(_open(_chapters, _index - 1, targetRatio: 1.0));
        }
        return;
      }
      unawaited(
        _scrollController.animateTo(
          (position.pixels - position.viewportDimension).clamp(
            0.0,
            position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  // ---- A 方案：章节导航、进度拖动与 AI 快捷入口 ----

  Future<void> _prevChapter() async {
    if (_index > 0) await _open(_chapters, _index - 1);
  }

  Future<void> _nextChapter() async {
    if (_index + 1 < _chapters.length) {
      await _open(_chapters, _index + 1);
    }
  }

  void _startProgressDrag(double value) {
    _resumeAutoAfterProgressDrag = _autoRunning;
    if (_autoRunning) _stopTicker();
    _previewWorkRatio = value;
    _displayWorkRatio.value = value;
  }

  void _previewProgress(double value) {
    _previewWorkRatio = value;
    _displayWorkRatio.value = value;
  }

  Future<void> _finishProgressDrag(double value) async {
    final generation = ++_progressJumpGeneration;
    final target = prefs.workProgressTarget(
      chapterWeights: _chapterWeights,
      workRatio: value,
    );
    if (target.chapterIndex != _index) {
      await _open(
        _chapters,
        target.chapterIndex,
        targetRatio: target.chapterRatio,
      );
    } else if (_scrollController.hasClients) {
      final position = _scrollController.position;
      _scrollController.jumpTo(
        prefs.scrollTopForRatio(
          target.chapterRatio,
          position.maxScrollExtent + position.viewportDimension,
          position.viewportDimension,
        ),
      );
      _updateProgress(_scrollController.offset);
    }
    if (!mounted || generation != _progressJumpGeneration) return;
    _schedulePositionSave();
    _previewWorkRatio = null;
    _displayWorkRatio.value = _liveRatio;
    if (_resumeAutoAfterProgressDrag && _autoRunning && _sheetsOpen == 0) {
      _startTicker();
    }
    _resumeAutoAfterProgressDrag = false;
  }

  Future<void> _showAiMenu() async {
    final hasGlobalEntries =
        widget.onOpenEntities != null || widget.onOpenIllustrations != null;
    final hasParagraphIllustration =
        widget.onIllustrateParagraphAt != null ||
        widget.onIllustrateParagraph != null;
    if (!hasGlobalEntries && !hasParagraphIllustration) {
      _snack('请先在设置中配置 AI 供应商，再使用 AI 功能');
      return;
    }
    await _showSheet(
      (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onOpenEntities != null)
              ListTile(
                leading: const Icon(Icons.face_outlined),
                title: const Text('实体卡'),
                onTap: () => widget.onOpenEntities!(context),
              ),
            if (widget.onOpenIllustrations != null)
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('插图'),
                onTap: () => widget.onOpenIllustrations!(context),
              ),
            if (hasParagraphIllustration)
              const ListTile(
                enabled: false,
                leading: Icon(Icons.auto_awesome_outlined),
                title: Text('AI 插图'),
                subtitle: Text('长按正文段落后选择 AI 插图'),
              ),
          ],
        ),
      ),
    );
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final palette = MarginalColors.palette(
      _theme,
      Theme.of(context).brightness,
    );
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _chapters.isEmpty
                ? const Center(child: Text('该书稿还没有章节。'))
                : ColoredBox(
                    color: palette.background,
                    child: _fidelityMode && _fidelitySrcdoc != null
                        ? ReaderEpubFidelityView(
                            key: ValueKey(_currentChapter!.id),
                            srcdoc: _fidelitySrcdoc!,
                          )
                        : _buildContent(palette),
                  ),
          ),
          if (!_loading && _chapters.isNotEmpty)
            _buildTopChrome(context, palette),
          if (!_loading && _chapters.isNotEmpty)
            _buildBottomChrome(context, palette),
        ],
      ),
    );
  }

  Widget _buildContent(ReaderPalette palette) {
    return GestureDetector(
      key: const Key('reader-chrome-toggle-zone'),
      behavior: HitTestBehavior.opaque,
      onTapUp: _handleReadingTapUp,
      child: ListView.builder(
        key: const Key('reader-scroll-view'),
        controller: _scrollController,
        scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
        padding: EdgeInsets.fromLTRB(
          24,
          MediaQuery.paddingOf(context).top + 16,
          24,
          MediaQuery.paddingOf(context).bottom + 132,
        ),
        itemCount: _chunks.length,
        itemBuilder: (context, index) => _chunkItem(_chunks[index], palette),
      ),
    );
  }

  Widget _chunkItem(ReaderChunk chunk, ReaderPalette palette) {
    final textStyle = MarginalTheme.serif.copyWith(
      fontSize: _fontSize,
      height: _lineHeight,
      color: palette.foreground,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        key: chunk.start == 0 ? _paraKey(chunk.paraIndex) : null,
        behavior: HitTestBehavior.opaque,
        onLongPress: chunk.start == 0
            ? () => _showParagraphSheet(chunk.paraIndex)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(chunk.text, style: textStyle),
            if (chunk.isLastFragment && _isFavorite(chunk.paraIndex))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(Icons.star, size: _fontSize, color: _gold),
              ),
            if (chunk.isLastFragment && _images.containsKey(chunk.paraIndex))
              for (final image in _images[chunk.paraIndex]!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Image.memory(
                    image,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopChrome(BuildContext context, ReaderPalette palette) {
    final foreground = palette.foreground;
    final bookmarked = _isBookmarked(_currentChapter!.id);
    final visible = _chromeVisible || _fidelityMode;
    return Positioned(
      key: const Key('reader-top-chrome'),
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, -1),
          duration: _chromeDuration,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: _chromeDuration,
            child: Material(
              color: palette.chrome,
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('reader-back-home'),
                      tooltip: '返回主页',
                      icon: Icon(Icons.arrow_back, color: foreground),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.work.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MarginalTheme.serif.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: foreground,
                            ),
                          ),
                          Text(
                            '第 ${_index + 1}/${_chapters.length} 章 · ${_currentChapter!.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: foreground.withValues(alpha: .65),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_fidelityMode)
                      TextButton(
                        key: const Key('reader-exit-fidelity'),
                        onPressed: () => unawaited(_setFidelityMode(false)),
                        style: TextButton.styleFrom(
                          foregroundColor: foreground,
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text(
                          '语义版',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ChromeIconButton(
                      key: const Key('reader-chapter-favorite'),
                      tooltip: bookmarked ? '已收藏' : '收藏本章',
                      icon: bookmarked
                          ? VectorIconKind.bookmark
                          : VectorIconKind.bookmarkOutline,
                      color: bookmarked ? palette.accent : foreground,
                      onPressed: _toggleChapterBookmark,
                    ),
                    ChromeIconButton(
                      key: const Key('reader-theme-toggle'),
                      tooltip: _theme == ReaderTheme.dark ? '切换纸色' : '切换夜间',
                      icon: _theme == ReaderTheme.dark
                          ? VectorIconKind.sun
                          : VectorIconKind.moon,
                      color: foreground,
                      onPressed: () => _setTheme(
                        _theme == ReaderTheme.dark
                            ? ReaderTheme.paper
                            : ReaderTheme.dark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSettings() async {
    await _showSheet(
      (context) => ReaderSettingsSheet(
        fontSize: _fontSize,
        lineHeight: _lineHeight,
        theme: _theme,
        autoSpeed: _autoSpeed,
        autoRunning: _autoRunning,
        onFontSize: (v) => _setFontSize(v),
        onLineHeight: (v) => _setLineHeight(v),
        onTheme: (t) => _setTheme(t),
        onAutoSpeed: (v) => _setAutoSpeed(v),
        onAutoToggle: (v) => v ? _startAuto() : _stopAuto(),
        showFidelity: _fidelityAvailable,
        fidelity: _fidelityMode,
        onFidelityToggle: (v) => unawaited(_setFidelityMode(v)),
      ),
    );
  }

  Widget _buildBottomChrome(BuildContext context, ReaderPalette palette) {
    final foreground = palette.foreground;
    final canScrub = _chapterWeights.isNotEmpty && !_fidelityMode;
    final borderColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white10
        : MarginalColors.line;
    return Positioned(
      key: const Key('reader-bottom-chrome'),
      left: 16,
      right: 16,
      bottom: 12,
      child: IgnorePointer(
        ignoring: !_chromeVisible,
        child: AnimatedSlide(
          offset: _chromeVisible ? Offset.zero : const Offset(0, 1.6),
          duration: _chromeDuration,
          child: AnimatedOpacity(
            opacity: _chromeVisible ? 1 : 0,
            duration: _chromeDuration,
            child: Material(
              color: palette.background,
              elevation: 10,
              shadowColor: Colors.black26,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: borderColor),
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            key: const Key('reader-prev-chapter'),
                            tooltip: '上一章',
                            icon: Icon(Icons.chevron_left, color: foreground),
                            onPressed: _index > 0 ? _prevChapter : null,
                          ),
                          ValueListenableBuilder<double>(
                            valueListenable: _displayWorkRatio,
                            builder: (context, value, _) => Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    '${(value * 100).round()}%',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: foreground.withValues(alpha: .65),
                                    ),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      key: const Key('reader-progress-slider'),
                                      value: value.clamp(0.0, 1.0),
                                      activeColor: palette.accent,
                                      onChangeStart: canScrub
                                          ? _startProgressDrag
                                          : null,
                                      onChanged: canScrub
                                          ? _previewProgress
                                          : null,
                                      onChangeEnd: canScrub
                                          ? (v) => unawaited(
                                              _finishProgressDrag(v),
                                            )
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            key: const Key('reader-next-chapter'),
                            tooltip: '下一章',
                            icon: Icon(Icons.chevron_right, color: foreground),
                            onPressed: _index + 1 < _chapters.length
                                ? _nextChapter
                                : null,
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _CardAction(
                            key: const Key('reader-open-toc'),
                            icon: Icons.list_alt,
                            label: '目录',
                            color: foreground,
                            onTap: _showChapterSheet,
                          ),
                          _CardAction(
                            key: const Key('reader-open-favorites'),
                            icon: Icons.star_border,
                            label: '摘录',
                            color: foreground,
                            onTap: _showFavorites,
                          ),
                          _CardAction(
                            key: const Key('reader-auto-toggle'),
                            icon: _autoRunning
                                ? Icons.pause_circle_outline
                                : Icons.play_circle_outline,
                            label: _autoRunning ? '停止自动' : '自动阅读',
                            color: _autoRunning ? palette.accent : foreground,
                            onTap: _toggleAuto,
                          ),
                          _CardAction(
                            key: const Key('reader-ai-menu'),
                            icon: Icons.auto_awesome_outlined,
                            label: 'AI',
                            color: foreground,
                            onTap: _showAiMenu,
                          ),
                          _CardAction(
                            key: const Key('reader-open-settings'),
                            icon: Icons.text_fields,
                            label: '排版',
                            color: foreground,
                            onTap: _showSettings,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 方案悬浮卡片中的带标签动作按钮。
class _CardAction extends StatelessWidget {
  const _CardAction({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkResponse(
    onTap: onTap,
    radius: 30,
    child: SizedBox(
      width: 58,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );
}
