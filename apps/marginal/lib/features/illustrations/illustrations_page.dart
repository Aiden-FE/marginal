import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/ai/ai_services.dart';
import '../../app/ids.dart';
import '../../app/marginal_theme.dart';
import '../../app/platform_services.dart';
import '../../core/repository.dart';
import '../../core/types.dart';

/// 按空行切分段落（与阅读投影一致的简单规则）。
List<String> splitParagraphs(String text) => [
  for (final p in text.split(RegExp(r'\n\s*\n')))
    if (p.trim().isNotEmpty) p.trim(),
];

/// 摘要：压平空白并截断到 maxChars。
String summarizeText(String text, {int maxChars = 500}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= maxChars) return flat;
  return '${flat.substring(0, maxChars)}…';
}

String _describeCard(EntityCard c) {
  final attrs = c.attributes.entries
      .take(6)
      .map((e) => '${e.key}：${e.value}')
      .join('，');
  return '${entityKindLabel(c.kind)}「${c.name}」${attrs.isEmpty ? '' : '（$attrs）'}';
}

/// 章节封面插图提示词：canon 实体设定 + 500 字正文摘要。
String buildChapterPrompt(List<EntityCard> canonCards, String chapterText) {
  final parts = <String>['请为小说章节生成一幅整页章节插图。'];
  if (canonCards.isNotEmpty) {
    parts.add('出场正典实体：${canonCards.map(_describeCard).join('；')}。');
  }
  parts.add('章节正文摘要：${summarizeText(chapterText)}');
  return parts.join('\n');
}

/// 段落插图提示词：段落原文 + 可选拼入的正典人物。
String buildParagraphPrompt(
  List<EntityCard> chosenCards,
  String paragraphText,
) {
  final parts = <String>['请为小说段落生成一幅插图。'];
  if (chosenCards.isNotEmpty) {
    parts.add('需呈现的正典实体：${chosenCards.map(_describeCard).join('；')}。');
  }
  parts.add('段落原文：${summarizeText(paragraphText)}');
  return parts.join('\n');
}

class IllustrationsPage extends StatefulWidget {
  const IllustrationsPage({
    super.key,
    required this.services,
    required this.work,
    this.generationService,
  });
  final PlatformServices services;
  final Work work;
  final IllustrationGenerationService? generationService;
  @override
  State<IllustrationsPage> createState() => _IllustrationsPageState();
}

class _IllustrationsPageState extends State<IllustrationsPage> {
  List<Chapter> _chapters = [];
  List<Illustration> _illustrations = [];
  List<EntityCard> _cards = [];
  String? _selectedChapterId;
  String _chapterText = '';
  bool _busy = false;
  String _progress = '';

  Repository get _repo => widget.services.repository;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Chapter? get _chapter {
    for (final c in _chapters) {
      if (c.id == _selectedChapterId) return c;
    }
    return null;
  }

  Future<void> _load() async {
    final chapters = await _repo.listChapters(widget.work.id);
    final illustrations = await _repo.listIllustrations(widget.work.id);
    final cards = await _repo.listEntityCards(widget.work.id);
    final chapter = _chapter ?? (chapters.isEmpty ? null : chapters.first);
    final text = chapter == null ? '' : await _repo.getChapterText(chapter.id);
    if (!mounted) return;
    setState(() {
      _chapters = chapters;
      _illustrations = illustrations;
      _cards = cards;
      _chapterText = text;
      _selectedChapterId = chapter?.id;
    });
  }

  Future<void> _selectChapter(String? id) async {
    setState(() => _selectedChapterId = id);
    final text = id == null ? '' : await _repo.getChapterText(id);
    if (mounted) setState(() => _chapterText = text);
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? MarginalColors.danger : null,
        ),
      );
  }

  Future<Uint8List?> _blobBytes(String blobId) async {
    final direct = await _repo.getBlobData(blobId);
    if (direct != null) return direct;
    for (final b in await _repo.listBlobs(widget.work.id)) {
      if (b.id == blobId) return _repo.getBlobData(b.storageKey);
    }
    return null;
  }

  /// 把 Future 包装成 AiTaskEvent 流：进度 → 完成/失败，UI 统一按事件驱动。
  Stream<AiTaskEvent> _generationEvents(
    IllustrationGenerationService service,
    String prompt,
  ) async* {
    yield const AiTaskProgress('正在生成插图…', 0, 1);
    try {
      final blobId = await service.generate(
        workId: widget.work.id,
        prompt: prompt,
      );
      yield AiTaskDone<String>(blobId);
    } catch (err) {
      yield AiTaskFailed('$err');
    }
  }

  Future<void> _runGeneration(
    String prompt, {
    required int? paraIndex,
    List<String> entityCardIds = const [],
  }) async {
    final service = widget.generationService;
    if (service == null) {
      _toast('请先在设置中配置供应商');
      return;
    }
    final chapter = _chapter;
    if (chapter == null) {
      _toast('请先选择章节');
      return;
    }
    setState(() {
      _busy = true;
      _progress = '准备生成…';
    });
    try {
      await for (final event in _generationEvents(service, prompt)) {
        switch (event) {
          case AiTaskProgress(:final message):
            if (mounted) setState(() => _progress = message);
          case AiTaskDone(:final value):
            final blobId = value as String;
            await _repo.putIllustration(
              Illustration(
                id: newId('illo'),
                workId: widget.work.id,
                prompt: prompt,
                providerId: '',
                model: '',
                blobId: blobId,
                chapterId: chapter.id,
                paraIndex: paraIndex,
                status: 'draft',
                entityCardIds: entityCardIds,
                createdAt: DateTime.now().millisecondsSinceEpoch,
              ),
            );
            await _repo.putAnchor(
              Anchor(
                id: newId('anchor'),
                workId: widget.work.id,
                chapterId: chapter.id,
                targetId: blobId,
                paraIndex: paraIndex ?? 0,
                targetType: 'illustration',
              ),
            );
            if (mounted) {
              _toast(
                paraIndex == null
                    ? '章节插图已生成（草稿，封面位）'
                    : '段落插图已生成（草稿，段落 $paraIndex）',
              );
            }
          case AiTaskFailed(:final error):
            if (mounted) _toast('生成失败：$error', error: true);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
      await _load();
    }
  }

  Future<void> _generateChapter() async {
    if (widget.generationService == null) {
      _toast('请先在设置中配置供应商');
      return;
    }
    if (_chapter == null) {
      _toast('请先选择章节');
      return;
    }
    final canon = _cards.where((c) => c.isCanon).toList();
    await _runGeneration(
      buildChapterPrompt(canon, _chapterText),
      paraIndex: null,
    );
  }

  Future<void> _openParagraphFlow() async {
    if (widget.generationService == null) {
      _toast('请先在设置中配置供应商');
      return;
    }
    final chapter = _chapter;
    if (chapter == null) {
      _toast('请先选择章节');
      return;
    }
    final canonCharacters = _cards
        .where((c) => c.isCanon && c.kind == EntityKind.character)
        .toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ParagraphSheet(
        chapterTitle: chapter.title,
        paragraphs: splitParagraphs(_chapterText),
        canonCharacters: canonCharacters,
        onGenerate: (paraIndex, prompt, entityIds) => _runGeneration(
          prompt,
          paraIndex: paraIndex,
          entityCardIds: entityIds,
        ),
      ),
    );
  }

  Future<void> _accept(Illustration illustration) async {
    await _repo.putIllustration(
      Illustration(
        id: illustration.id,
        workId: illustration.workId,
        prompt: illustration.prompt,
        providerId: illustration.providerId,
        model: illustration.model,
        blobId: illustration.blobId,
        chapterId: illustration.chapterId,
        paraIndex: illustration.paraIndex,
        status: 'accepted',
        entityCardIds: illustration.entityCardIds,
        createdAt: illustration.createdAt,
      ),
    );
    await _load();
    if (mounted) _toast('插图已设为接受');
  }

  Future<void> _delete(Illustration illustration) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除插图'),
        content: const Text('将同时删除挂载该插图的锚点，确定删除？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MarginalColors.danger,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final anchors = await _repo.listAnchors(widget.work.id);
    for (final a in anchors) {
      if (a.targetType == 'illustration' &&
          (a.targetId == illustration.blobId ||
              a.targetId == illustration.id)) {
        await _repo.deleteAnchor(a.id);
      }
    }
    await _repo.deleteIllustration(illustration.id);
    await _load();
    if (mounted) _toast('插图已删除');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.work.title} · 插图'),
        actions: [
          if (_chapters.length > 1)
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedChapterId,
                borderRadius: BorderRadius.circular(12),
                items: [
                  for (final c in _chapters)
                    DropdownMenuItem(value: c.id, child: Text(c.title)),
                ],
                onChanged: (v) => _selectChapter(v),
              ),
            ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _generateChapter,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('生成章节插图'),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _openParagraphFlow,
              icon: const Icon(Icons.article_outlined, size: 18),
              label: const Text('生成段落插图'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LinearProgressIndicator(minHeight: 2),
                  const SizedBox(height: 6),
                  Text(
                    _progress,
                    style: const TextStyle(
                      fontSize: 12,
                      color: MarginalColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildGrid()),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    if (_illustrations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.image_outlined,
              size: 48,
              color: MarginalColors.muted,
            ),
            const SizedBox(height: 12),
            Text(
              '还没有插图',
              style: MarginalTheme.serif.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: MarginalColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '选择章节后生成章节封面插图，\n或选择某个段落生成段落插图。',
              textAlign: TextAlign.center,
              style: TextStyle(color: MarginalColors.muted, height: 1.6),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: _illustrations.length,
      itemBuilder: (context, i) => _IllustrationTile(
        illustration: _illustrations[i],
        loadBytes: () => _blobBytes(_illustrations[i].blobId),
        onAccept: _illustrations[i].status == 'draft'
            ? () => _accept(_illustrations[i])
            : null,
        onDelete: () => _delete(_illustrations[i]),
      ),
    );
  }
}

class _IllustrationTile extends StatefulWidget {
  const _IllustrationTile({
    required this.illustration,
    required this.loadBytes,
    required this.onDelete,
    this.onAccept,
  });

  final Illustration illustration;
  final Future<Uint8List?> Function() loadBytes;
  final VoidCallback onDelete;
  final VoidCallback? onAccept;

  @override
  State<_IllustrationTile> createState() => _IllustrationTileState();
}

class _IllustrationTileState extends State<_IllustrationTile> {
  bool _promptExpanded = false;

  @override
  Widget build(BuildContext context) {
    final illustration = widget.illustration;
    final accepted = illustration.status == 'accepted';
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1.25,
            child: FutureBuilder<Uint8List?>(
              future: widget.loadBytes(),
              builder: (context, snap) {
                final data = snap.data;
                if (data == null) {
                  return Container(
                    color: MarginalColors.surface2,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.image_outlined,
                      color: MarginalColors.muted,
                    ),
                  );
                }
                return Image.memory(
                  data,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accepted
                        ? MarginalColors.accentSoft
                        : MarginalColors.surface2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    accepted ? '已接受' : '草稿',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accepted
                          ? MarginalColors.accent
                          : MarginalColors.muted,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  illustration.paraIndex == null
                      ? '章节封面'
                      : '段落 ${illustration.paraIndex}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: MarginalColors.muted,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
            child: InkWell(
              onTap: () => setState(() => _promptExpanded = !_promptExpanded),
              child: Row(
                children: [
                  const Icon(
                    Icons.notes,
                    size: 14,
                    color: MarginalColors.muted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '提示词',
                      style: TextStyle(
                        fontSize: 12,
                        color: _promptExpanded
                            ? MarginalColors.accent
                            : MarginalColors.muted,
                      ),
                    ),
                  ),
                  Icon(
                    _promptExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: MarginalColors.muted,
                  ),
                ],
              ),
            ),
          ),
          if (_promptExpanded)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                child: SingleChildScrollView(
                  child: Text(
                    illustration.prompt,
                    style: const TextStyle(fontSize: 11, height: 1.5),
                  ),
                ),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
            child: Row(
              children: [
                if (widget.onAccept != null)
                  TextButton.icon(
                    onPressed: widget.onAccept,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('设为接受', style: TextStyle(fontSize: 12)),
                  )
                else
                  const Spacer(),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: MarginalColors.danger,
                  ),
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('删除', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ParagraphSheet extends StatefulWidget {
  const _ParagraphSheet({
    required this.chapterTitle,
    required this.paragraphs,
    required this.canonCharacters,
    required this.onGenerate,
  });

  final String chapterTitle;
  final List<String> paragraphs;
  final List<EntityCard> canonCharacters;
  final void Function(int paraIndex, String prompt, List<String> entityIds)
  onGenerate;

  @override
  State<_ParagraphSheet> createState() => _ParagraphSheetState();
}

class _ParagraphSheetState extends State<_ParagraphSheet> {
  int? _selected;
  final Set<String> _chosen = {};

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return SizedBox(
      height: height * 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '生成段落插图 · ${widget.chapterTitle}',
              style: MarginalTheme.serif.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: MarginalColors.ink,
              ),
            ),
          ),
          if (widget.paragraphs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                '本章没有可用的段落。',
                style: TextStyle(color: MarginalColors.muted),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (var i = 0; i < widget.paragraphs.length; i++)
                    ListTile(
                      leading: Icon(
                        _selected == i
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: _selected == i
                            ? MarginalColors.accent
                            : MarginalColors.muted,
                      ),
                      title: Text('段落 $i'),
                      subtitle: Text(
                        widget.paragraphs[i],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => setState(() => _selected = i),
                    ),
                  if (widget.canonCharacters.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(8, 12, 8, 4),
                      child: Text(
                        '拼入正典人物（可选）',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: MarginalColors.muted,
                        ),
                      ),
                    ),
                    for (final c in widget.canonCharacters)
                      CheckboxListTile(
                        dense: true,
                        value: _chosen.contains(c.id),
                        title: Text(c.name),
                        onChanged: (on) => setState(() {
                          if (on ?? false) {
                            _chosen.add(c.id);
                          } else {
                            _chosen.remove(c.id);
                          }
                        }),
                      ),
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: FilledButton.icon(
              onPressed: _selected == null
                  ? null
                  : () {
                      final ids = _chosen.toList();
                      Navigator.of(context).pop();
                      widget.onGenerate(
                        _selected!,
                        buildParagraphPrompt([
                          for (final c in widget.canonCharacters)
                            if (_chosen.contains(c.id)) c,
                        ], widget.paragraphs[_selected!]),
                        ids,
                      );
                    },
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('生成插图'),
            ),
          ),
        ],
      ),
    );
  }
}
