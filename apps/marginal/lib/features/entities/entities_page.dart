import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/ai/ai_services.dart';
import '../../app/ids.dart';
import '../../app/marginal_theme.dart';
import '../../app/platform_services.dart';
import '../../core/repository.dart';
import '../../core/types.dart';

/// 筛选维度：全部 / 按类型 / 正典。
enum EntityFilter { all, character, scene, item, canon }

IconData iconForKind(EntityKind kind) => switch (kind) {
  EntityKind.character => Icons.person,
  EntityKind.scene => Icons.landscape,
  EntityKind.item => Icons.diamond,
};

/// 提取结果写入：同名同 kind 合并 aliases/attributes，否则新建草稿卡。
EntityCard mergeExtracted(
  EntityCard? existing,
  ExtractedEntity entity,
  String workId,
) {
  if (existing == null) {
    return EntityCard(
      id: newId('entity'),
      workId: workId,
      name: entity.name,
      kind: entity.kind,
      aliases: [
        for (final a in entity.aliases)
          if (a.trim().isNotEmpty) a.trim(),
      ],
      attributes: {
        for (final e in entity.attributes.entries)
          if (e.key.trim().isNotEmpty && e.value.trim().isNotEmpty)
            e.key.trim(): e.value.trim(),
      },
      status: 'draft',
    );
  }
  final aliases = [...existing.aliases];
  for (final a in entity.aliases) {
    final v = a.trim();
    if (v.isEmpty || v == existing.name || aliases.contains(v)) continue;
    aliases.add(v);
  }
  final attributes = {...existing.attributes};
  for (final e in entity.attributes.entries) {
    if (e.key.trim().isEmpty || e.value.trim().isEmpty) continue;
    attributes[e.key.trim()] = e.value.trim();
  }
  return EntityCard(
    id: existing.id,
    workId: existing.workId,
    name: existing.name,
    kind: existing.kind,
    aliases: aliases,
    attributes: attributes,
    status: existing.status,
    portraitBlobId: existing.portraitBlobId,
    createdAt: existing.createdAt,
  );
}

class EntitiesPage extends StatefulWidget {
  const EntitiesPage({
    super.key,
    required this.services,
    required this.work,
    this.extractionService,
  });
  final PlatformServices services;
  final Work work;
  final EntityExtractionService? extractionService;
  @override
  State<EntitiesPage> createState() => _EntitiesPageState();
}

class _EntitiesPageState extends State<EntitiesPage> {
  List<EntityCard> _cards = [];
  List<Chapter> _chapters = [];
  String? _selectedChapterId;
  EntityFilter _filter = EntityFilter.all;
  bool _extracting = false;

  Repository get _repo => widget.services.repository;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final chapters = await _repo.listChapters(widget.work.id);
    final cards = await _repo.listEntityCards(widget.work.id);
    if (!mounted) return;
    setState(() {
      _chapters = chapters;
      _cards = cards;
      if (_selectedChapterId == null ||
          !chapters.any((c) => c.id == _selectedChapterId)) {
        _selectedChapterId = chapters.isEmpty ? null : chapters.first.id;
      }
    });
  }

  Chapter? get _chapter {
    for (final c in _chapters) {
      if (c.id == _selectedChapterId) return c;
    }
    return null;
  }

  List<EntityCard> get _filtered => [
    for (final c in _cards)
      if (switch (_filter) {
        EntityFilter.all => true,
        EntityFilter.canon => c.isCanon,
        EntityFilter.character => c.kind == EntityKind.character,
        EntityFilter.scene => c.kind == EntityKind.scene,
        EntityFilter.item => c.kind == EntityKind.item,
      })
        c,
  ];

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

  Future<void> _extract() async {
    final svc = widget.extractionService;
    if (svc == null) {
      _toast('请先在设置中配置供应商');
      return;
    }
    final chapter = _chapter;
    if (chapter == null) {
      _toast('请先选择章节');
      return;
    }
    setState(() => _extracting = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(days: 1),
        content: Text('正在从「${chapter.title}」提取实体…'),
      ),
    );
    try {
      final extracted = await svc.extract(
        workId: widget.work.id,
        chapterId: chapter.id,
      );
      final existing = await _repo.listEntityCards(widget.work.id);
      var created = 0;
      var merged = 0;
      for (final e in extracted) {
        EntityCard? match;
        for (final c in existing) {
          if (c.name == e.name && c.kind == e.kind) {
            match = c;
            break;
          }
        }
        await _repo.putEntityCard(mergeExtracted(match, e, widget.work.id));
        if (match == null) {
          created++;
        } else {
          merged++;
        }
      }
      await _load();
      messenger.hideCurrentSnackBar();
      _toast('提取完成：新增 $created 张、合并 $merged 张实体卡');
    } catch (err) {
      messenger.hideCurrentSnackBar();
      _toast('提取失败：$err', error: true);
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  Future<Uint8List?> _blobBytes(String blobId) async {
    final direct = await _repo.getBlobData(blobId);
    if (direct != null) return direct;
    for (final b in await _repo.listBlobs(widget.work.id)) {
      if (b.id == blobId) return _repo.getBlobData(b.storageKey);
    }
    return null;
  }

  Future<void> _openDetail(EntityCard card) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EntityDetailSheet(
        services: widget.services,
        workId: widget.work.id,
        initial: card,
        onChanged: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.work.title),
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
                onChanged: (v) => setState(() => _selectedChapterId = v),
              ),
            ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _extracting ? null : _extract,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('提取实体'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in EntityFilter.values)
                  ChoiceChip(
                    label: Text(switch (f) {
                      EntityFilter.all => '全部',
                      EntityFilter.character => '角色',
                      EntityFilter.scene => '场景',
                      EntityFilter.item => '物品',
                      EntityFilter.canon => '正典',
                    }),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
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
    final items = _filtered;
    if (items.isEmpty) {
      return _EmptyState(hasCards: _cards.isNotEmpty, filter: _filter);
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.95,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _EntityCardTile(
        card: items[i],
        blobBytes: () => _blobBytes(items[i].portraitBlobId!),
        onTap: () => _openDetail(items[i]),
      ),
    );
  }
}

class _EntityCardTile extends StatelessWidget {
  const _EntityCardTile({
    required this.card,
    required this.blobBytes,
    required this.onTap,
  });

  final EntityCard card;
  final Future<Uint8List?> Function() blobBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Portrait(
                    card: card,
                    blobBytes: card.portraitBlobId == null ? null : blobBytes,
                  ),
                  const Spacer(),
                  if (card.isCanon)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.verified,
                        size: 18,
                        color: MarginalColors.accent,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                card.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MarginalTheme.serif.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? MarginalColors.nightInk : MarginalColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              if (card.aliases.isNotEmpty)
                Text(
                  card.aliases.join('、'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? MarginalColors.nightInk
                        : MarginalColors.muted,
                  ),
                ),
              const Spacer(),
              Row(
                children: [
                  Icon(
                    iconForKind(card.kind),
                    size: 14,
                    color: MarginalColors.accent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    entityKindLabel(card.kind),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? MarginalColors.nightInk
                          : MarginalColors.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Portrait extends StatelessWidget {
  const _Portrait({required this.card, required this.blobBytes});

  final EntityCard card;
  final Future<Uint8List?> Function()? blobBytes;

  @override
  Widget build(BuildContext context) {
    final bytes = blobBytes?.call();
    if (bytes == null) {
      return _kindAvatar();
    }
    return FutureBuilder<Uint8List?>(
      future: bytes,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) return _kindAvatar();
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(data, width: 48, height: 48, fit: BoxFit.cover),
        );
      },
    );
  }

  Widget _kindAvatar() => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: MarginalColors.accentSoft,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(iconForKind(card.kind), color: MarginalColors.accent, size: 24),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasCards, required this.filter});

  final bool hasCards;
  final EntityFilter filter;

  @override
  Widget build(BuildContext context) {
    if (hasCards) {
      return Center(
        child: Text(
          '没有符合筛选的实体卡',
          style: TextStyle(color: MarginalColors.muted),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.style_outlined,
            size: 48,
            color: MarginalColors.muted,
          ),
          const SizedBox(height: 12),
          Text(
            '还没有实体卡',
            style: MarginalTheme.serif.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: MarginalColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '在顶栏选择章节并点击「提取实体」，\n从正文中提取角色、场景与物品卡片。',
            textAlign: TextAlign.center,
            style: TextStyle(color: MarginalColors.muted, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _EntityDetailSheet extends StatefulWidget {
  const _EntityDetailSheet({
    required this.services,
    required this.workId,
    required this.initial,
    required this.onChanged,
  });

  final PlatformServices services;
  final String workId;
  final EntityCard initial;
  final VoidCallback onChanged;

  @override
  State<_EntityDetailSheet> createState() => _EntityDetailSheetState();
}

class _EntityDetailSheetState extends State<_EntityDetailSheet> {
  late EntityCard _card = widget.initial;
  final _aliasCtrl = TextEditingController();

  Repository get _repo => widget.services.repository;

  @override
  void dispose() {
    _aliasCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(EntityCard card) async {
    setState(() => _card = card);
    await _repo.putEntityCard(card);
    widget.onChanged();
  }

  Future<void> _toggleCanon() async {
    await _save(
      EntityCard(
        id: _card.id,
        workId: _card.workId,
        name: _card.name,
        kind: _card.kind,
        aliases: _card.aliases,
        attributes: _card.attributes,
        status: _card.isCanon ? 'draft' : 'canon',
        portraitBlobId: _card.portraitBlobId,
        createdAt: _card.createdAt,
      ),
    );
  }

  Future<void> _addAlias() async {
    final v = _aliasCtrl.text.trim();
    if (v.isEmpty || v == _card.name || _card.aliases.contains(v)) return;
    _aliasCtrl.clear();
    await _save(
      EntityCard(
        id: _card.id,
        workId: _card.workId,
        name: _card.name,
        kind: _card.kind,
        aliases: [..._card.aliases, v],
        attributes: _card.attributes,
        status: _card.status,
        portraitBlobId: _card.portraitBlobId,
        createdAt: _card.createdAt,
      ),
    );
  }

  Future<void> _removeAlias(String alias) => _save(
    EntityCard(
      id: _card.id,
      workId: _card.workId,
      name: _card.name,
      kind: _card.kind,
      aliases: _card.aliases.where((a) => a != alias).toList(),
      attributes: _card.attributes,
      status: _card.status,
      portraitBlobId: _card.portraitBlobId,
      createdAt: _card.createdAt,
    ),
  );

  Future<void> _editAttribute({String? key, String? value}) async {
    final keyCtrl = TextEditingController(text: key ?? '');
    final valueCtrl = TextEditingController(text: value ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(key == null ? '添加属性' : '编辑属性'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyCtrl,
              autofocus: key == null,
              decoration: const InputDecoration(labelText: '属性名'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: valueCtrl,
              decoration: const InputDecoration(labelText: '属性值'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    final newKey = keyCtrl.text.trim();
    final newValue = valueCtrl.text.trim();
    if (newKey.isEmpty || newValue.isEmpty) return;
    final attributes = {..._card.attributes};
    if (key != null && key != newKey) attributes.remove(key);
    attributes[newKey] = newValue;
    await _save(
      EntityCard(
        id: _card.id,
        workId: _card.workId,
        name: _card.name,
        kind: _card.kind,
        aliases: _card.aliases,
        attributes: attributes,
        status: _card.status,
        portraitBlobId: _card.portraitBlobId,
        createdAt: _card.createdAt,
      ),
    );
  }

  Future<void> _removeAttribute(String key) async {
    final attributes = {..._card.attributes}..remove(key);
    await _save(
      EntityCard(
        id: _card.id,
        workId: _card.workId,
        name: _card.name,
        kind: _card.kind,
        aliases: _card.aliases,
        attributes: attributes,
        status: _card.status,
        portraitBlobId: _card.portraitBlobId,
        createdAt: _card.createdAt,
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除实体卡'),
        content: Text('确定删除「${_card.name}」？该操作不可撤销。'),
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
    await _repo.deleteEntityCard(_card.id);
    widget.onChanged();
    if (mounted) Navigator.of(context).pop();
  }

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
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: MarginalColors.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    iconForKind(_card.kind),
                    color: MarginalColors.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _card.name,
                    style: MarginalTheme.serif.copyWith(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: MarginalColors.ink,
                    ),
                  ),
                ),
                if (_card.isCanon)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: MarginalColors.accentSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '正典',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: MarginalColors.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: OutlinedButton.icon(
              onPressed: _toggleCanon,
              icon: Icon(_card.isCanon ? Icons.undo : Icons.verified, size: 18),
              label: Text(_card.isCanon ? '退回草稿' : '设为正典'),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                _sectionTitle('属性'),
                if (_card.attributes.isEmpty) _hint('暂无属性，点击下方按钮添加。'),
                for (final e in _card.attributes.entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      '${e.key}：${e.value}',
                      style: const TextStyle(color: MarginalColors.ink),
                    ),
                    onTap: () => _editAttribute(key: e.key, value: e.value),
                    trailing: IconButton(
                      tooltip: '删除属性',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => _removeAttribute(e.key),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _editAttribute(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加属性'),
                ),
                const SizedBox(height: 16),
                _sectionTitle('别名'),
                if (_card.aliases.isEmpty) _hint('暂无别名。'),
                if (_card.aliases.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final a in _card.aliases)
                          InputChip(
                            label: Text(a),
                            visualDensity: VisualDensity.compact,
                            onDeleted: () => _removeAlias(a),
                          ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _aliasCtrl,
                        decoration: const InputDecoration(hintText: '添加别名'),
                        onSubmitted: (_) => _addAlias(),
                      ),
                    ),
                    IconButton(
                      tooltip: '添加别名',
                      onPressed: _addAlias,
                      icon: const Icon(Icons.add_circle_outline),
                      color: MarginalColors.accent,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: MarginalColors.danger,
                  ),
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('删除实体卡'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
        color: MarginalColors.muted,
      ),
    ),
  );

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(color: MarginalColors.muted, fontSize: 13),
    ),
  );
}
