import 'package:flutter/material.dart';

import '../../app/marginal_theme.dart';
import '../../app/reading_prefs.dart' as prefs;
import '../../core/types.dart';

/// 章节抽屉 —— 书内搜索 / 书签列表 / 全部章节（当前章高亮、书签星标）。
class ReaderChapterSheet extends StatefulWidget {
  const ReaderChapterSheet({
    super.key,
    required this.chapters,
    required this.chapterTexts,
    required this.currentIndex,
    required this.bookmarks,
    required this.onSelectChapter,
    required this.onBookmarkRemoved,
  });

  final List<Chapter> chapters;

  /// chapterId -> 全文，用于书内搜索上下文片段。
  final Map<String, String> chapterTexts;
  final int currentIndex;
  final List<prefs.ChapterBookmark> bookmarks;
  final ValueChanged<Chapter> onSelectChapter;
  final ValueChanged<prefs.ChapterBookmark> onBookmarkRemoved;

  @override
  State<ReaderChapterSheet> createState() => _ReaderChapterSheetState();
}

class _Hit {
  const _Hit(this.chapter, this.count, this.snippet);
  final Chapter chapter;
  final int count;
  final String snippet;
}

class _ReaderChapterSheetState extends State<ReaderChapterSheet> {
  late final List<prefs.ChapterBookmark> _bookmarks = List.of(widget.bookmarks);
  String _query = '';

  List<_Hit> get _hits {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final hits = <_Hit>[];
    for (final chapter in widget.chapters) {
      final text = widget.chapterTexts[chapter.id] ?? '';
      final titleCount = _countOccurrences(chapter.title.toLowerCase(), q);
      final textCount = _countOccurrences(text.toLowerCase(), q);
      final count = titleCount + textCount;
      if (count == 0) continue;
      hits.add(
        _Hit(chapter, count, _snippet(text.isEmpty ? chapter.title : text, q)),
      );
    }
    return hits;
  }

  static int _countOccurrences(String haystack, String needle) {
    if (needle.isEmpty) return 0;
    var count = 0;
    var index = haystack.indexOf(needle);
    while (index >= 0) {
      count++;
      index = haystack.indexOf(needle, index + needle.length);
    }
    return count;
  }

  static String _snippet(String text, String q) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ');
    final index = flat.toLowerCase().indexOf(q);
    if (index < 0) return flat.substring(0, flat.length.clamp(0, 40));
    final start = (index - 16).clamp(0, flat.length);
    final end = (index + q.length + 24).clamp(0, flat.length);
    return '${start > 0 ? '…' : ''}${flat.substring(start, end)}${end < flat.length ? '…' : ''}';
  }

  bool _isBookmarked(String chapterId) =>
      _bookmarks.any((b) => b.chapterId == chapterId);

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: const Key('chapter-search-field'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索书内文字或章节标题',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: _query.trim().isEmpty ? _buildBrowse() : _buildSearch(hits),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowse() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_bookmarks.isNotEmpty) ...[
          _sectionTitle('书签'),
          for (final bookmark in _bookmarks)
            Dismissible(
              key: ValueKey('bookmark-${bookmark.chapterId}'),
              direction: DismissDirection.endToStart,
              background: Container(
                color: MarginalColors.danger,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: const Icon(Icons.delete_outline, color: Colors.white),
              ),
              onDismissed: (_) => _removeBookmark(bookmark),
              child: ListTile(
                leading: const Icon(
                  Icons.bookmark,
                  color: MarginalColors.accent,
                ),
                title: Text(
                  bookmark.chapterTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '删除书签',
                  onPressed: () => _removeBookmark(bookmark),
                ),
                onTap: () => _select(
                  widget.chapters.firstWhere(
                    (c) => c.id == bookmark.chapterId,
                    orElse: () => widget.chapters.first,
                  ),
                ),
              ),
            ),
        ],
        _sectionTitle('全部章节'),
        for (var i = 0; i < widget.chapters.length; i++)
          ListTile(
            selected: i == widget.currentIndex,
            selectedColor: MarginalColors.accent,
            leading: Text(
              '${i + 1}',
              style: TextStyle(
                color: i == widget.currentIndex
                    ? MarginalColors.accent
                    : Theme.of(context).hintColor,
                fontSize: 13,
              ),
            ),
            title: Text(
              widget.chapters[i].title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: i == widget.currentIndex
                  ? const TextStyle(fontWeight: FontWeight.w700)
                  : null,
            ),
            trailing: _isBookmarked(widget.chapters[i].id)
                ? const Icon(Icons.star, size: 18, color: Color(0xFFD9A13C))
                : null,
            onTap: () => _select(widget.chapters[i]),
          ),
      ],
    );
  }

  Widget _buildSearch(List<_Hit> hits) {
    if (hits.isEmpty) {
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('没有找到相关内容。')),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _sectionTitle('搜索结果（${hits.length} 章）'),
        for (final hit in hits)
          ListTile(
            title: Text(
              hit.chapter.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: _highlighted(hit.snippet),
            trailing: Text(
              '× ${hit.count}',
              style: TextStyle(
                color: Theme.of(context).hintColor,
                fontSize: 12,
              ),
            ),
            onTap: () => _select(hit.chapter),
          ),
      ],
    );
  }

  Widget _highlighted(String snippet) {
    final q = _query.trim();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final index = snippet.toLowerCase().indexOf(q.toLowerCase(), start);
      if (index < 0) {
        spans.add(TextSpan(text: snippet.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: snippet.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: snippet.substring(
            index,
            (index + q.length).clamp(0, snippet.length),
          ),
          style: TextStyle(
            color: MarginalColors.accent,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = index + q.length;
      if (start >= snippet.length) break;
    }
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall,
        children: spans,
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor),
    ),
  );

  void _removeBookmark(prefs.ChapterBookmark bookmark) {
    setState(
      () => _bookmarks.removeWhere((b) => b.chapterId == bookmark.chapterId),
    );
    widget.onBookmarkRemoved(bookmark);
  }

  void _select(Chapter chapter) {
    Navigator.of(context).pop();
    widget.onSelectChapter(chapter);
  }
}
