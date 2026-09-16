import 'dart:typed_data';

import '../core/repository.dart';
import '../core/types.dart';

/// The reader-facing view of one chapter.
class ChapterProjection {
  const ChapterProjection({required this.chapter, this.images = const {}});
  final Chapter chapter;
  final Map<int, List<Uint8List>> images;
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
    final activeAnchors = (await repository.listAnchors(workId))
        .where((a) => a.chapterId == chapter.id && a.state == 'active')
        .toList();
    if (activeAnchors.isEmpty) {
      return ChapterProjection(chapter: chapter);
    }
    final images = <int, List<Uint8List>>{};
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
      if (bytes != null) {
        images.putIfAbsent(anchor.paraIndex, () => []).add(bytes);
      }
    }
    return ChapterProjection(chapter: chapter, images: images);
  }
}
