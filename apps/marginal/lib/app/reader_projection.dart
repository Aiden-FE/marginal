import 'dart:typed_data';

import '../core/repository.dart';
import '../core/types.dart';

/// The reader-facing view of one chapter.
class ChapterProjection {
  const ChapterProjection({
    required this.chapter,
    required this.text,
    this.images = const {},
  });
  final Chapter chapter;
  final String text;
  final Map<int, Uint8List> images;
}

/// Builds [ChapterProjection]s for the reader: chapters are ordered by idx,
/// and active anchors are resolved against a single blob pass per projection,
/// so navigation never rescans the work's blob list per anchor.
class ReaderProjectionService {
  ReaderProjectionService(this.repository);
  final Repository repository;

  Future<List<Chapter>> chapters(String workId) async =>
      (await repository.listChapters(workId))
        ..sort((a, b) => a.idx.compareTo(b.idx));

  Future<ChapterProjection> projection(String workId, Chapter chapter) async {
    final text = await repository.getChapterText(chapter.id);
    final activeAnchors = (await repository.listAnchors(workId))
        .where((a) => a.chapterId == chapter.id && a.state == 'active')
        .toList();
    if (activeAnchors.isEmpty) {
      return ChapterProjection(chapter: chapter, text: text);
    }
    final images = <int, Uint8List>{};
    // 一次拉取本稿全部 blob 记录与字节，再按锚点落位。
    final blobs = await repository.listBlobs(workId);
    final wanted = activeAnchors.map((a) => a.targetId).toSet();
    final data = <String, Uint8List>{};
    for (final blob in blobs) {
      if (!wanted.contains(blob.id)) continue;
      final bytes = await repository.getBlobData(blob.storageKey);
      if (bytes != null) data[blob.id] = bytes;
    }
    for (final anchor in activeAnchors) {
      final bytes = data[anchor.targetId];
      if (bytes != null) images[anchor.paraIndex] = bytes;
    }
    return ChapterProjection(chapter: chapter, text: text, images: images);
  }
}
