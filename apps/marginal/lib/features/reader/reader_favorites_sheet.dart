import 'package:flutter/material.dart';

import '../../app/reading_prefs.dart' as prefs;
import 'sheet_host.dart';

/// 段落收藏列表（顶栏星标入口），点击跳回原章节段落。
class ReaderFavoritesSheet extends StatefulWidget {
  const ReaderFavoritesSheet({
    super.key,
    required this.favorites,
    required this.onSelect,
    required this.onRemoved,
  });

  final List<prefs.ParagraphFavorite> favorites;
  final ValueChanged<prefs.ParagraphFavorite> onSelect;
  final ValueChanged<prefs.ParagraphFavorite> onRemoved;

  @override
  State<ReaderFavoritesSheet> createState() => _ReaderFavoritesSheetState();
}

class _ReaderFavoritesSheetState extends State<ReaderFavoritesSheet> {
  late final List<prefs.ParagraphFavorite> _items = List.of(widget.favorites);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _items.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('还没有收藏的段落。在段落上点按即可收藏。')),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    '段落收藏（${_items.length}）',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final favorite in _items)
                  Dismissible(
                    key: ValueKey(
                      'fav-${favorite.chapterId}-${favorite.paraIndex}-${favorite.savedAt}',
                    ),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: const Color(0xFFAD4E43),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                      ),
                    ),
                    onDismissed: (_) => _remove(favorite),
                    child: ListTile(
                      leading: const Icon(Icons.star, color: Color(0xFFD9A13C)),
                      title: Text(
                        favorite.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        favorite.chapterTitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: '取消收藏',
                        onPressed: () => _remove(favorite),
                      ),
                      onTap: () {
                        popAndRun(context, () => widget.onSelect(favorite));
                      },
                    ),
                  ),
              ],
            ),
    );
  }

  void _remove(prefs.ParagraphFavorite favorite) {
    setState(() => _items.remove(favorite));
    widget.onRemoved(favorite);
  }
}
