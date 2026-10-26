// 批 41（2026-10-26）：**分页符是原子对象** —— 删除侧的三条口径。
//
// 用户实测背景：他在末页文末下面的空行里连按删除（**本意不是删分页符**），
// 结果页面上直接印出了 `<!-- pagebreak -->` 这行编码。
//
// 正常行为（不需要用户选）：
//   ① 这次删除**不会**造出"分页符残片" ⇒ **照旧删**（空行/普通换行/字符都随便删）；
//   ② 这次删除**会**把 `<!-- pagebreak -->` 粘成 `甲<!-- pagebreak -->` / `!-- pagebreak -->`
//      ⇒ 改成删掉**整个分页符行**（一次删干净 ≈ 取消这一页的分页）；
//   ③ **绝不允许**出现残片；也**绝不许殃及**：删标记上/下的空行时，分页符必须还在。
//
// ★ 曾经的两种错法（都做过，留作反面教材）：
//   · 「拒绝」⇒ 删除键变死按（用户："怎么按也回不到文末"）；
//   · 「碰到标记就整行删」⇒ 删它上面一行的空行也把分页符带走（探针 `Delete @7`）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/block.dart';
import 'package:mathlang/render/math_nav.dart';
import 'package:mathlang/render/smart_delete.dart';

String _apply(String doc, SmartEdit e) =>
    e.isNone ? doc : doc.replaceRange(e.from!, e.to!, '');

/// 结果里不许有"含 pagebreak 但不是完好整行标记"的行
void _expectNoBareMarker(String doc, String why) {
  for (final String line in doc.split('\n')) {
    if (!line.contains('pagebreak')) continue;
    expect(BlockMarkers.isPageBreak(line), isTrue,
        reason: '$why ⇒ 页面上会露出编码：「$line」\n整篇：${doc.replaceAll('\n', r'\n')}');
  }
}

bool _hasMarker(String doc) => doc.split('\n').any(BlockMarkers.isPageBreak);

/// 这次删除的范围离"分页符行"是否至少隔着一整行？
bool _farFromMarker(String doc, int from, int to) {
  var ls = 0;
  while (ls <= doc.length) {
    int le = doc.indexOf('\n', ls);
    if (le < 0) le = doc.length;
    if (BlockMarkers.isPageBreak(doc.substring(ls, le))) {
      return to < ls - 2 || from > le + 2;
    }
    if (le >= doc.length) break;
    ls = le + 1;
  }
  return false;
}

void main() {
  group('★ 不许殃及：删标记上/下的空行，分页符必须还在', () {
    // ★ 这里要分清两件事（探针实测过）：
    //   · 光标在标记**上面那一行**（空行）按 Delete ⇒ 段落边界一删，`bb` 就与标记行合并
    //     ⇒ 不可能既保留分页符又合并段落 ⇒ **删掉分页符是对的**（Word 也是这个行为）；
    //     唯一不许出的是"残片"和"正文被误删"。
    //   · 光标在标记**下面那一行**按 Delete ⇒ 动的是它下面的空行，与标记无关
    //     ⇒ **分页符必须原样留着**（这才是"不许殃及"）。
    test('★ 删标记上一行的空行 ⇒ 等于删掉这个分页符（常规行为），但正文与残片都得干净', () {
      const String doc = 'aa\n\nbb\n\n<!-- pagebreak -->\n';
      final int blankLine = doc.indexOf('\n\n<!--'); // 标记上一行那个空行的行首
      expect(doc[blankLine], '\n', reason: '前置：确实是空行');
      final SmartEdit e = smartEditAt(doc, blankLine, forward: true);
      final String out = _apply(doc, e);
      _expectNoBareMarker(out, 'Delete @$blankLine');
      expect(out.contains('aa'), isTrue, reason: '正文不许被误删：$out');
      expect(out.contains('bb'), isTrue, reason: '正文不许被误删：$out');
    });

    test('★ 删标记**下面**那一行的空行 ⇒ 分页符必须原样留着', () {
      const String doc = 'aa\n\nbb\n\n<!-- pagebreak -->\n\n';
      final int below = doc.indexOf('-->') + 3; // 标记行末尾那个换行之后
      expect(doc[below], '\n', reason: '前置：标记下面确实是空行');
      final SmartEdit e = smartEditAt(doc, below, forward: true);
      final String out = _apply(doc, e);
      expect(_hasMarker(out), isTrue,
          reason: '分页符被顺手删掉了：${out.replaceAll('\n', r'\n')}');
      _expectNoBareMarker(out, 'Delete @$below');
    });
  });

  group('★ 会毁掉它时 ⇒ 删掉**整个**分页符行（一次删干净）', () {
    test('★ 退格在标记行首（上一行有字）⇒ 整个分页符行消失，不留残片', () {
      const String doc = '甲\n<!-- pagebreak -->\n乙\n';
      final int start = doc.indexOf('<!--');
      final SmartEdit e = smartEditAt(doc, start, forward: false);
      final String out = _apply(doc, e);
      expect(_hasMarker(out), isFalse, reason: '这一下应当删掉整行：$out');
      _expectNoBareMarker(out, '退格 @$start');
      expect(out.contains('甲'), isTrue, reason: '正文字符不许被删：$out');
      expect(out.contains('乙'), isTrue, reason: '正文字符不许被删：$out');
    });

    test('★ Delete 在标记行尾（下一行有字）⇒ 整个分页符行消失', () {
      const String doc = '甲\n<!-- pagebreak -->\n乙\n';
      final int end = doc.indexOf('-->') + 3; // 标记行那个换行
      final SmartEdit e = smartEditAt(doc, end, forward: true);
      final String out = _apply(doc, e);
      expect(_hasMarker(out), isFalse, reason: '这一下应当删掉整行：$out');
      _expectNoBareMarker(out, 'Delete @$end');
    });

    test('★ 删标记自己的一个字符（如 `<`）⇒ 也是整行删掉，不许留半截', () {
      const String doc = '甲\n<!-- pagebreak -->\n乙\n';
      final int lt = doc.indexOf('<!--');
      final SmartEdit e = smartEditAt(doc, lt, forward: true);
      final String out = _apply(doc, e);
      _expectNoBareMarker(out, 'Delete 标记首字符');
      expect(_hasMarker(out), isFalse, reason: '删了半截标记就只能整行删：$out');
    });
  });

  group('★ 全域：任何偏移 × 两个方向 ⇒ 不许残片，也不许无谓殃及', () {
    test('★★ 全域断言', () {
      var checked = 0;
      for (final String doc in <String>[
        '甲\n<!-- pagebreak -->\n乙\n',
        '甲\n\n<!-- pagebreak -->\n\n乙\n',
        '甲\n<!-- pagebreak -->\n\n\n',
        '甲\n\n<!-- pagebreak -->\n',
        '\n<!-- pagebreak -->\n',
      ]) {
        for (var o = 0; o <= doc.length; o++) {
          for (final bool fwd in <bool>[false, true]) {
            final SmartEdit e = smartEditAt(doc, o, forward: fwd);
            if (e.isNone) continue;
            checked++;
            final String out = _apply(doc, e);
            _expectNoBareMarker(out, '${fwd ? 'Delete' : '退格'} @$o');
            if (_farFromMarker(doc, e.from!, e.to!)) {
              expect(_hasMarker(out), isTrue,
                  reason: '${fwd ? 'Delete' : '退格'} @$o 离标记很远却把分页符删了：'
                      '${out.replaceAll('\n', r'\n')}');
            }
          }
        }
      }
      expect(checked, greaterThan(20), reason: '别空转：至少要真的删过这么多次');
    });
  });
}
