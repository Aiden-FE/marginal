import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/repository.dart';
import '../core/types.dart';

class ApprovalService {
  ApprovalService(this.repository);
  final Repository repository;
  Future<void> reject(Proposal p) => repository.updateProposal(
    Proposal(
      id: p.id,
      workId: p.workId,
      runId: p.runId,
      type: p.type,
      payload: p.payload,
      status: 'rejected',
      createdAt: p.createdAt,
    ),
  );
  Future<void> approve(Proposal p) async {
    final a = jsonDecode(p.payload) as Map<String, dynamic>;
    if (p.type == 'text_repair') {
      final c = (await repository.listChapters(p.workId))
          .firstWhere((x) => x.id == a['chapterId']);
      var parts = (await repository.getChapterText(c.id))
          .split(RegExp(r'\n\s*\n'));
      for (final raw in (a['patches'] as List)) {
        final x = Map<String, dynamic>.from(raw);
        final i = (x['paraIndex'] as num).toInt();
        if (i >= 0 && i < parts.length && parts[i].contains(x['original'])) {
          parts[i] = parts[i].replaceFirst(x['original'], x['replacement']);
        }
      }
      final text = '${parts.join('\n\n').trim()}\n';
      await repository.putChapter(
        p.workId,
        Chapter(
          id: c.id,
          workId: c.workId,
          idx: c.idx,
          title: c.title,
          wordCount: text.runes.length,
          contentHash: sha256.convert(utf8.encode(text)).toString(),
        ),
        text,
      );
    }
    await repository.updateProposal(
      Proposal(
        id: p.id,
        workId: p.workId,
        runId: p.runId,
        type: p.type,
        payload: p.payload,
        status: 'approved',
        createdAt: p.createdAt,
      ),
    );
  }
}
