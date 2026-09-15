import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/ai/provider_services.dart';
import '../../app/ids.dart';
import '../../app/import_service.dart';
import '../../app/marginal_theme.dart';
import '../../app/platform_services.dart';
import '../../app/reading_prefs.dart';
import '../../core/types.dart';
import '../../app/provider_store.dart';
import '../reader/reader_page.dart';
import '../entities/entities_page.dart';
import '../illustrations/illustrations_page.dart';
import '../ai/ai_workspace_page.dart';

/// 未分组筛选的哨兵值（null 表示「全部」）。
const String _ungroupedKey = '__ungrouped__';

/// 封面色 6 组渐变（暖纸书卷气质），按书名稳定散列取一。
const List<List<Color>> _coverGradients = [
  [Color(0xFFB98A5E), Color(0xFF8A5A33)],
  [Color(0xFF7E9A82), Color(0xFF4F6B55)],
  [Color(0xFF8FA3B8), Color(0xFF54687E)],
  [Color(0xFFC08E9A), Color(0xFF8A5563)],
  [Color(0xFFA79BC9), Color(0xFF6C5F96)],
  [Color(0xFFC9A96A), Color(0xFF94743B)],
];

/// v1 .m-import-loading 的视觉参数。
const Color _importMaskColor = Color(0x9418140F); // rgba(24,20,15,.58)
const Color _importSpinnerColor = Color(0xFFE0B866);

int _stableHash(String s) =>
    s.isEmpty ? 0 : s.runes.fold(0, (h, c) => (h * 31 + c) & 0x7fffffff);

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.services,
    this.fileSource = const PickerFileSource(),
    this.showWorkspaceFeatures = false,
    this.showAppBar = true,
  });
  final PlatformServices services;
  final FileSource fileSource;
  final bool showWorkspaceFeatures;
  final bool showAppBar;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<Work> _works = const [];
  Map<String, List<Chapter>> _chaptersByWork = const {};
  String? _filter; // null=全部，_ungroupedKey=未分组，其余为分组名
  String _query = '';
  bool _importing = false;
  bool _showUnreadOnly = false;
  String _stage = ImportStages.readFile;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final works = await widget.services.repository.listWorks();
    final chapters = <String, List<Chapter>>{};
    for (final work in works) {
      chapters[work.id] = await widget.services.repository.listChapters(
        work.id,
      );
    }
    if (mounted) {
      setState(() {
        _works = works;
        _chaptersByWork = chapters;
      });
    }
  }

  String _groupOf(Work work) =>
      ((work.settings['group'] as String?) ?? '').trim();

  bool _isFavorite(Work work) => work.settings['favorite'] == true;

  ({double ratio, bool finished}) _progressOf(Work work) {
    final pos = loadReadingPosition(work.settings);
    final chapters = _chaptersByWork[work.id] ?? const [];
    final finished = isWorkFinished(
      positionChapterId: pos?.chapterId,
      positionRatio: pos?.ratio ?? 0,
      chapterIdsInOrder: chapters.map((c) => c.id).toList(),
    );
    return (ratio: pos?.ratio ?? 0, finished: finished);
  }

  List<Work> get _groupNames =>
      _works.where((w) => _groupOf(w).isNotEmpty).toList();

  bool _isUnread(Work work) {
    final progress = _progressOf(work);
    return !progress.finished && progress.ratio <= 0.98;
  }

  bool _matchesQuery(Work work) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    final chapters = _chaptersByWork[work.id] ?? const <Chapter>[];
    return [
      work.title,
      work.author,
      _groupOf(work),
      ...chapters.map((chapter) => chapter.title),
    ].any((value) => value.toLowerCase().contains(query));
  }

  List<Work> get _visibleWorks {
    final visible = _works.where((work) {
      final group = _groupOf(work);
      if (_filter == _ungroupedKey && group.isNotEmpty) return false;
      if (_filter != null && _filter != _ungroupedKey && group != _filter) {
        return false;
      }
      if (_showUnreadOnly && !_isUnread(work)) return false;
      return _matchesQuery(work);
    }).toList();
    visible.sort((a, b) {
      final favorite = (_isFavorite(b) ? 1 : 0) - (_isFavorite(a) ? 1 : 0);
      if (favorite != 0) return favorite;
      final recent = _recentAt(b).compareTo(_recentAt(a));
      if (recent != 0) return recent;
      return a.title.compareTo(b.title);
    });
    return visible;
  }

  int _recentAt(Work work) {
    final raw = work.settings['readingUpdatedAt'];
    if (raw is num) return raw.toInt();
    return work.updatedAt;
  }

  Work? get _continueWork {
    final reading = _works.where((work) {
      final position = loadReadingPosition(work.settings);
      return position != null && _isUnread(work);
    }).toList()..sort((a, b) => _recentAt(b).compareTo(_recentAt(a)));
    return reading.isEmpty ? null : reading.first;
  }

  Future<void> _showSearch() async {
    final controller = TextEditingController(text: _query);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('搜索书稿'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '书名、作者、分组或章节标题',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _query = result);
  }

  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    final input = await widget.fileSource.pick();
    if (input == null) return;
    if (mounted) {
      setState(() {
        _importing = true;
        _stage = ImportStages.readFile;
      });
    }
    try {
      final service = ImportService(widget.services.repository);
      final lowerName = input.name.toLowerCase();
      final work = lowerName.endsWith('.mabk')
          ? await service.importMabk(input.bytes, copy: true)
          : lowerName.endsWith('.epub')
          ? await service.importEpub(
              input.name,
              input.bytes,
              onProgress: (stage) {
                if (mounted) setState(() => _stage = stage);
              },
            )
          : await service.importTxt(
              input.name,
              input.bytes,
              onProgress: (stage) {
                if (mounted) setState(() => _stage = stage);
              },
            );
      await _refresh();
      if (mounted) setState(() => _importing = false);
      messenger.showSnackBar(SnackBar(content: Text('已导入「${work.title}」')));
    } catch (e) {
      if (mounted) setState(() => _importing = false);
      messenger.showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }

  Future<void> _open(Work work) async {
    await _markReadingActivity(work);
    final chapters = await widget.services.repository.listChapters(work.id);
    if (!mounted || chapters.isEmpty) return;
    final saved = (work.settings['reader'] as Map?)?['chapterId'] as String?;
    final initial = chapters.any((c) => c.id == saved)
        ? saved!
        : chapters.first.id;
    final extraction = _extractionService();
    final generation = _generationService();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderPage(
          services: widget.services,
          work: work,
          initialChapterId: initial,
          onOpenEntities: (context) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EntitiesPage(
                services: widget.services,
                work: work,
                extractionService: extraction,
              ),
            ),
          ),
          onOpenIllustrations: (context) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => IllustrationsPage(
                services: widget.services,
                work: work,
                generationService: generation,
              ),
            ),
          ),
          onIllustrateParagraphAt: generation == null
              ? null
              : (chapterId, paraIndex, paragraph) =>
                    _generateParagraphIllustration(
                      work,
                      chapterId,
                      paraIndex,
                      paragraph,
                      generation,
                    ),
        ),
      ),
    );
    await _refresh();
  }

  ProviderEntry? _activeProvider() {
    for (final provider in widget.services.providerStore.providers) {
      if (provider.id != 'demo') return provider;
    }
    return null;
  }

  ProviderEntityExtractionService? _extractionService() {
    final provider = _activeProvider();
    return provider == null
        ? null
        : ProviderEntityExtractionService(
            repository: widget.services.repository,
            provider: provider,
          );
  }

  ProviderIllustrationGenerationService? _generationService() {
    final provider = _activeProvider();
    return provider == null
        ? null
        : ProviderIllustrationGenerationService(
            repository: widget.services.repository,
            provider: provider,
          );
  }

  Future<void> _generateParagraphIllustration(
    Work work,
    String chapterId,
    int paraIndex,
    String paragraph,
    ProviderIllustrationGenerationService generation,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在生成段落插图…')));
    try {
      final provider = _activeProvider()!;
      final blobId = await generation.generate(
        workId: work.id,
        prompt: '为小说段落生成插图：$paragraph',
      );
      final illustration = Illustration(
        id: newId('illustration'),
        workId: work.id,
        prompt: paragraph,
        providerId: provider.id,
        model: provider.model,
        blobId: blobId,
        chapterId: chapterId,
        paraIndex: paraIndex,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await widget.services.repository.putIllustration(illustration);
      await widget.services.repository.putAnchor(
        Anchor(
          id: newId('anchor'),
          workId: work.id,
          chapterId: chapterId,
          targetId: blobId,
          paraIndex: paraIndex,
        ),
      );
      messenger.showSnackBar(const SnackBar(content: Text('段落插图已生成')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('生成失败：$e')));
    }
  }

  Future<void> _patchSettings(Work work, Map<String, dynamic> patch) async {
    final settings = Map<String, dynamic>.from(work.settings)..addAll(patch);
    await widget.services.repository.putWork(
      Work(
        id: work.id,
        title: work.title,
        author: work.author,
        importSource: work.importSource,
        createdAt: work.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        settings: settings,
      ),
    );
    await _refresh();
  }

  Future<void> _markReadingActivity(Work work) async {
    await _patchSettings(work, {
      'readingUpdatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _toggleFavorite(Work work) =>
      _patchSettings(work, {'favorite': !_isFavorite(work)});

  Future<void> _delete(Work work) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('删除书稿'),
        content: Text('「${work.title}」将被删除，且无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: MarginalColors.danger),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await widget.services.repository.deleteWork(work.id);
      await _refresh();
      messenger.showSnackBar(const SnackBar(content: Text('已删除书稿')));
    }
  }

  Future<void> _exportMabk(Work work) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ImportService(widget.services.repository).exportMabk(work);
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? '已导出「${work.title}」.mabk' : '当前平台暂不支持导出分享')),
    );
  }

  Future<void> _rename(Work work) async {
    final controller = TextEditingController(text: work.title);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名书稿'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '书稿名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final title = controller.text.trim();
    if (saved != true || title.isEmpty || title == work.title) return;
    await widget.services.repository.putWork(
      Work(
        id: work.id,
        title: title,
        author: work.author,
        importSource: work.importSource,
        createdAt: work.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        settings: work.settings,
      ),
    );
    await _refresh();
  }

  Future<void> _showWorkSheet(Work work) async {
    final existingGroups = _groupNames.map(_groupOf).toSet().toList()..sort();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        final controller = TextEditingController(text: _groupOf(work));
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  work.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MarginalTheme.serif.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: '分组',
                    hintText: '如：科幻 / 待读',
                  ),
                ),
                if (existingGroups.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final group in existingGroups)
                          ActionChip(
                            label: Text(group),
                            onPressed: () => controller.text = group,
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final group = controller.text.trim();
                      Navigator.pop(sheetCtx);
                      _patchSettings(work, {'group': group});
                    },
                    child: const Text('保存分组'),
                  ),
                ),
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.play_arrow_rounded),
                  title: const Text('继续阅读'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _open(work);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('重命名'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _rename(work);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _isFavorite(work)
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: MarginalColors.accent,
                  ),
                  title: Text(_isFavorite(work) ? '移出收藏' : '加入收藏'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _toggleFavorite(work);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.list_alt_outlined),
                  title: const Text('查看目录'),
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    final chapters = await widget.services.repository
                        .listChapters(work.id);
                    if (!mounted) return;
                    await showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (_) => ListView(
                        shrinkWrap: true,
                        children: [
                          for (final chapter in chapters)
                            ListTile(
                              title: Text(chapter.title),
                              subtitle: Text('第 ${chapter.idx + 1} 章'),
                              onTap: () {
                                Navigator.pop(context);
                                _open(work);
                              },
                            ),
                        ],
                      ),
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: !kIsWeb,
                  leading: const Icon(Icons.ios_share),
                  title: const Text('导出 .mabk'),
                  subtitle: kIsWeb ? const Text('当前平台暂不支持导出分享') : null,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _exportMabk(work);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('AI 修复与提案'),
                  subtitle: const Text('章节异常、文字异常在 AI Tab 中处理'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AiWorkspacePage(
                          services: widget.services,
                          initialWork: work,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.face_outlined),
                  title: const Text('实体卡'),
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    final extraction = _extractionService();
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => EntitiesPage(
                          services: widget.services,
                          work: work,
                          extractionService: extraction,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('插图'),
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    final generation = _generationService();
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => IllustrationsPage(
                          services: widget.services,
                          work: work,
                          generationService: generation,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.delete_outline,
                    color: MarginalColors.danger,
                  ),
                  title: const Text(
                    '删除',
                    style: TextStyle(color: MarginalColors.danger),
                  ),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _delete(work);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? MarginalColors.accent
                : (dark ? Colors.white10 : MarginalColors.surface),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? MarginalColors.accent
                  : (dark ? Colors.white24 : MarginalColors.line),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? Colors.white
                  : (dark ? MarginalColors.nightInk : MarginalColors.muted),
            ),
          ),
        ),
      ),
    );
  }

  Widget _workCard(Work work) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final progress = _progressOf(work);
    final gradients =
        _coverGradients[_stableHash(work.title) % _coverGradients.length];
    final firstChar = work.title.isEmpty
        ? '书'
        : String.fromCharCode(work.title.runes.first);
    final subtitle = [
      if (work.author.isNotEmpty) work.author,
      if (work.importSource.isNotEmpty) work.importSource,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(work),
        onLongPress: () => _showWorkSheet(work),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 74,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: gradients,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      firstChar,
                      style: MarginalTheme.serif.copyWith(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: .92),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          work.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MarginalTheme.serif.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: dark
                                ? MarginalColors.nightInk
                                : MarginalColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: dark
                                  ? MarginalColors.nightInk.withValues(
                                      alpha: .6,
                                    )
                                  : MarginalColors.muted,
                            ),
                          ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: progress.ratio,
                                  minHeight: 4,
                                  backgroundColor: dark
                                      ? Colors.white12
                                      : MarginalColors.line,
                                  color: MarginalColors.accent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${(progress.ratio * 100).round()}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                color: dark
                                    ? MarginalColors.nightInk
                                    : MarginalColors.muted,
                              ),
                            ),
                            if (progress.finished) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: MarginalColors.accentSoft,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  '读完',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: MarginalColors.accent,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: '书稿工具',
                icon: const Icon(Icons.more_horiz_rounded),
                color: dark ? MarginalColors.nightInk : MarginalColors.muted,
                onPressed: () => _showWorkSheet(work),
              ),
            ),
            if (_isFavorite(work))
              const Positioned(
                top: 8,
                right: 42,
                child: Icon(
                  Icons.star_rounded,
                  size: 20,
                  color: MarginalColors.accent,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _continueCard(Work work) {
    final progress = _progressOf(work);
    final position = loadReadingPosition(work.settings);
    final chapter = position == null
        ? null
        : (_chaptersByWork[work.id] ?? const <Chapter>[])
              .where((item) => item.id == position.chapterId)
              .firstOrNull;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(work),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              const Icon(
                Icons.play_circle_outline_rounded,
                color: MarginalColors.accent,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '继续阅读',
                      style: TextStyle(
                        fontSize: 11,
                        color: MarginalColors.muted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      work.title,
                      style: MarginalTheme.serif.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: MarginalColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      chapter == null ? '上次阅读位置' : chapter.title,
                      style: const TextStyle(
                        fontSize: 12,
                        color: MarginalColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(progress.ratio * 100).round()}%',
                style: const TextStyle(
                  color: MarginalColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: MarginalColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final groupNames = _groupNames.map(_groupOf).toSet().toList()..sort();
    final visible = _visibleWorks;
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: dark
                  ? MarginalColors.nightBg
                  : MarginalColors.bg,
              title: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: MarginalColors.accent,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'M',
                      style: MarginalTheme.serif.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '书库',
                    style: MarginalTheme.serif.copyWith(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: dark
                          ? MarginalColors.nightInk
                          : MarginalColors.ink,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: '设置',
                  onPressed: () => Navigator.of(context).pushNamed('/settings'),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            )
          : null,
      floatingActionButton: widget.showAppBar
          ? FloatingActionButton(
              onPressed: _import,
              tooltip: '导入 TXT / .mabk',
              child: const Icon(Icons.add),
            )
          : null,
      body: Stack(
        children: [
          Column(
            children: [
              if (widget.showWorkspaceFeatures)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _showSearch,
                          icon: const Icon(Icons.search_rounded, size: 18),
                          label: Text(
                            _query.isEmpty ? '搜索书名、作者、分组或章节' : _query,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            foregroundColor: _query.isEmpty
                                ? MarginalColors.muted
                                : MarginalColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: '清除搜索',
                        onPressed: _query.isEmpty
                            ? null
                            : () => setState(() => _query = ''),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      _chip(
                        '全部',
                        _filter == null && !_showUnreadOnly,
                        () => setState(() {
                          _filter = null;
                          _showUnreadOnly = false;
                        }),
                      ),
                      if (widget.showWorkspaceFeatures)
                        _chip(
                          '待读',
                          _showUnreadOnly,
                          () => setState(() {
                            _filter = null;
                            _showUnreadOnly = true;
                          }),
                        ),
                      for (final group in groupNames)
                        _chip(
                          group,
                          _filter == group,
                          () => setState(() {
                            _filter = group;
                            _showUnreadOnly = false;
                          }),
                        ),
                      _chip(
                        '未分组',
                        _filter == _ungroupedKey,
                        () => setState(() {
                          _filter = _ungroupedKey;
                          _showUnreadOnly = false;
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.showWorkspaceFeatures && _continueWork != null)
                _continueCard(_continueWork!),
              Expanded(
                child: _works.isEmpty
                    ? const Center(child: Text('还没有书稿。导入一本 TXT 开始阅读。'))
                    : visible.isEmpty
                    ? Center(
                        child: Text(
                          _query.isEmpty ? '该筛选还没有书稿。' : '没有找到匹配的书稿。',
                        ),
                      )
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, i) => _workCard(visible[i]),
                      ),
              ),
            ],
          ),
          if (_importing)
            Positioned.fill(
              child: ColoredBox(
                color: _importMaskColor,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        color: _importSpinnerColor,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _stage,
                        style: const TextStyle(
                          color: Color(0xFFF5F1E8),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
