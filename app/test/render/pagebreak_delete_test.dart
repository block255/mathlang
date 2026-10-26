// 批 39（2026-10-26）：**删除不许把分页符行弄坏**。
//
// 用户手测截图（`…141348_ugbj.png`）：在末页空行上连按几下删除之后，页面上**直接露出了
// `<!-- pagebreak -->` 这行编码**（还配着两根光标条）。根因：`BlockMarkers.isPageBreak`
// 要求"**整行正好是** `<!-- pagebreak -->`"——把它的换行吃掉、或把邻居粘上来，
// 那一行就退化成普通段落，编码当场画在纸上。
//
// `render/math_nav.dart` 的 `_fenceBrokenByDelete` 早就为 `$$` / ```` ``` ```` 做了这件事
// （批 32：三类坏法），**分页符当时没算进去** —— 这是同族第四类。
//
// 判据（全域）：任何偏移 × 两个方向，删完之后**不许出现"含 pagebreak 但不是分页符行"的行**。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/block.dart';
import 'package:mathlang/render/math_nav.dart';
import 'package:mathlang/render/smart_delete.dart';

/// 删完之后页面上会不会露出编码
void _expectNoBareMarker(String doc, String why) {
  for (final String line in doc.split('\n')) {
    if (!line.contains('pagebreak')) continue;
    expect(BlockMarkers.isPageBreak(line), isTrue,
        reason: '$why ⇒ 页面上会露出编码：「$line」\n整篇：${doc.replaceAll('\n', r'\n')}');
  }
}

const String kDoc = '甲\n<!-- pagebreak -->\n乙\n';

void main() {
  group('★ 分页符行不许被删除弄坏（否则页面上露出 `<!-- pagebreak -->`）', () {
    test('★ 退格吃掉分页符行**后面**那个换行 ⇒ 必须拒绝（改前：`<!-- pagebreak -->乙`）', () {
      final int nl = kDoc.indexOf('-->') + 3; // 分页符行末尾 = 那个换行
      final SmartEdit e = smartEditAt(kDoc, nl + 1, forward: false);
      final String out = e.isNone
          ? kDoc
          : kDoc.replaceRange(e.from!, e.to!, '');
      _expectNoBareMarker(out, '退格 @${nl + 1}');
    });

    test('★ Delete 吃掉分页符行后面那个换行 ⇒ 必须拒绝', () {
      final int nl = kDoc.indexOf('-->') + 3;
      final SmartEdit e = smartEditAt(kDoc, nl, forward: true);
      final String out = e.isNone
          ? kDoc
          : kDoc.replaceRange(e.from!, e.to!, '');
      _expectNoBareMarker(out, 'Delete @$nl');
    });

    test('★ 退格吃掉分页符行**前面**那个换行、把正文粘上来 ⇒ 必须拒绝', () {
      const String doc = '甲\n<!-- pagebreak -->\n乙\n';
      final int start = doc.indexOf('<!--');
      final SmartEdit e = smartEditAt(doc, start, forward: false);
      final String out = e.isNone
          ? doc
          : doc.replaceRange(e.from!, e.to!, '');
      _expectNoBareMarker(out, '退格 @$start');
    });

    test('★★ 全域：每个偏移 × 两个方向 ⇒ 永远不许露出编码', () {
      var checked = 0;
      for (final String doc in <String>[
        kDoc,
        '甲\n\n<!-- pagebreak -->\n\n乙\n',
        '甲\n<!-- pagebreak -->\n\n\n',
        '\n<!-- pagebreak -->\n',
      ]) {
        for (var o = 0; o <= doc.length; o++) {
          for (final bool fwd in <bool>[false, true]) {
            final SmartEdit e = smartEditAt(doc, o, forward: fwd);
            if (e.isNone) continue;
            checked++;
            final String out = doc.replaceRange(e.from!, e.to!, '');
            _expectNoBareMarker(out, '${fwd ? 'Delete' : '退格'} @$o');
          }
        }
      }
      expect(checked, greaterThan(20), reason: '别空转：至少真的要删这么多次');
    });
  });
}
