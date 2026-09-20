import 'package:flutter_test/flutter_test.dart';

import 'package:marginal/app/copy_rules.dart';
import 'package:marginal/core/bundle.dart';
import 'package:marginal/core/split.dart';
import 'package:marginal/core/types.dart';

void main() {
  test('mabk round trip and copy re-id', () {
    const data = BundleData(
      work: Work(id: 'w', title: '书'),
      chapters: [Chapter(id: 'c', workId: 'w', idx: 0, title: '章')],
      texts: {'c': '正文'},
    );
    final parsed = readBundle(buildBundle(data));
    expect(parsed.data.work.id, 'w');
    expect(parsed.data.texts['c'], '正文');
    expect(reidForCopy(parsed.data).work.id, isNot('w'));
  });
  test('copy remaps anchor targetId when it points to a blob', () {
    const data = BundleData(
      work: Work(id: 'w', title: '书'),
      blobs: [BlobRec(id: 'b', workId: 'w', storageKey: 'k', kind: 'image')],
      anchors: [Anchor(id: 'a', workId: 'w', chapterId: 'c', targetId: 'b')],
    );
    final copy = reidForCopy(data);
    expect(copy.anchors.single.targetId, copy.blobs.single.id);
  });

  test(
    'typed proposal parsing rejects unknown kinds and malformed repairs',
    () {
      expect(() => parseProposalKind('unknown'), throwsFormatException);
      expect(
        () => TextRepairPayload.fromJson({'chapterId': 'c'}),
        throwsFormatException,
      );
      expect(parseProposalStatus('approved'), ProposalStatus.approved);
    },
  );

  test('txt heuristic finds Chinese chapters', () {
    final points = splitByHeuristics('第一章 开始\n\n这是正文内容。\n\n第二章 继续\n\n这是更多正文。');
    expect(points.map((p) => p.title), contains('第一章 开始'));
    expect(points.map((p) => p.title), contains('第二章 继续'));
  });
}
