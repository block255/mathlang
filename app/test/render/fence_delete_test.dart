// 行间围栏的**删除守卫**：`Backspace` / `Delete` 删换行时，不许把 `$$…$$` 弄坏。
//
// ★ 为什么必须有这一份（用户 2026-10-24 实测：某处连按两下退格 ⇒ 整块源码裸奔）：
//   探针 v50 逐偏移扫 `smartEditAt`，抓出**三类**坏法（都会让那一块不再被识别成数学块）：
//   ① **围栏被挪到行中间**：`文字` + `$$` 粘成 `文字$$`、`(a)` + `$$` 粘成 `(a)$$`
//      —— 围栏不在行首 ⇒ 那一块作废（这一块里所有 tex 以源码形态显示）；
//   ② **两个围栏粘成一行**：`$$\nA\n$$\n\n$$\nB\n$$` 在空行上退格 ⇒ `$$`+`$$` = `$$$$`
//      —— 两块合成**一个空块**，两块的内容一起去见鬼；
//   ③ **收尾围栏后面粘上内容**：`$$\nA\n$$\nB` 删掉 `$$\n` 之后那个换行 ⇒ `$$B`
//      —— 收尾被当成新的开头 ⇒ 块不再闭合。
//
// ★ 判据只用**权威切段器** `scanMathSpans`（不信"看起来像"）：删的是**纯换行**时，
//   行间块的**数目与内容都不许变**。（删掉 `$` 本身不归这条管 —— 那是"整段回收"。）

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/math_spans.dart';
import 'package:mathlang/render/math_nav.dart';
import 'package:mathlang/render/smart_delete.dart';

const String _d = r'$$';

/// 真正的行间块（`$$…$$`）
List<MathSpan> _display(String s) =>
    scanMathSpans(s).where((MathSpan m) => m.display).toList();

/// 把一次删除应用到源码上
String _apply(String s, SmartEdit e) =>
    e.deletes ? s.replaceRange(e.from!, e.to!, '') : s;

/// 这一删删掉的**只有换行**吗（只有这种才归围栏守卫管）
bool _onlyNewlines(String s, SmartEdit e) {
  if (!e.deletes) return false;
  final String gone = s.substring(e.from!, e.to!);
  return gone.isNotEmpty && gone.replaceAll('\n', '').isEmpty;
}

void main() {
  group('现场（探针 v50 抓到的三类）', () {
    const String srcA = '$_d\nA\n$_d\n\n$_d\nB\n$_d\n';

    test('① 两块之间空一行：在空行上退格 ⇒ 仍是两块，不许粘成 `\$\$\$\$`', () {
      // 空行上（偏移 9 = 第二个 `$$` 行首）退格
      final SmartEdit e1 = smartEditAt(srcA, 9, forward: false);
      final String s1 = _apply(srcA, e1);
      expect(s1.contains('$_d$_d'), isFalse, reason: '两块不许粘成一行：${s1.replaceAll("\n", "⏎")}');
      expect(_display(s1).length, 2, reason: '两块都得活着：${s1.replaceAll("\n", "⏎")}');
      // 连按第二下（用户现场的"两下"）
      final SmartEdit e2 = smartEditAt(s1, e1.caret, forward: false);
      final String s2 = _apply(s1, e2);
      expect(s2.contains('$_d$_d'), isFalse,
          reason: '第二下也不许粘：${s2.replaceAll("\n", "⏎")}');
      expect(_display(s2).length, 2,
          reason: '第二下之后仍是两块：${s2.replaceAll("\n", "⏎")}');
    });

    test('③ 文字行 + 块 + 块：删文字后的空行 ⇒ 块还在、围栏仍在本行行首', () {
      const String src = '文字\n\n$_d\nA\n$_d\n\n$_d\nB\n$_d\n';
      final SmartEdit e = smartEditAt(src, 4, forward: false);
      final String s = _apply(src, e);
      expect(s.startsWith('文字$_d'), isFalse,
          reason: '围栏不许被拽到文字后面：${s.replaceAll("\n", "⏎")}');
      expect(_display(s).length, 2, reason: '两块都得活着：${s.replaceAll("\n", "⏎")}');
    });

    test('① 文字行紧贴围栏行：退格不许造成 `(a)\$\$`', () {
      const String src = '(a)\n$_d\nA\n$_d\n';
      final SmartEdit e = smartEditAt(src, 4, forward: false);
      final String s = _apply(src, e);
      expect(s.contains('(a)$_d'), isFalse,
          reason: '围栏不许离开行首：${s.replaceAll("\n", "⏎")}');
      expect(_display(s).length, 1,
          reason: '那一块还得是行间块：${s.replaceAll("\n", "⏎")}');
    });

    test('③ 收尾围栏后面粘内容 ⇒ `\$\$B`（块不再闭合）', () {
      const String src = '$_d\nA\n$_d\nB\n';
      // 光标在 B 之前（`$$` 与 `B` 之间的换行之后）退格
      final SmartEdit e = smartEditAt(src, 7, forward: false);
      final String s = _apply(src, e);
      expect(s.contains('${_d}B'), isFalse,
          reason: '收尾围栏不许粘上内容：${s.replaceAll("\n", "⏎")}');
      expect(_display(s).length, 1,
          reason: '那一块还得是行间块：${s.replaceAll("\n", "⏎")}');
    });
  });

  group('全域：删纯换行 ⇒ 行间块的数目与内容都不许变', () {
    final List<String> sources = <String>[
      '$_d\nA\n$_d\n\n$_d\nB\n$_d\n',
      '(a)\n$_d\nA\n$_d\n',
      '文字\n\n$_d\nA\n$_d\n\n$_d\nB\n$_d\n',
      '$_d\nA\n$_d\nB\n',
      'B\n$_d\nA\n$_d\n',
      '$_d\nA\n$_d\n$_d\nB\n$_d\n',
      // 同一行开合的块（`$$a$$`，批 17 口径）
      _d + 'a' + _d + '\n\n' + _d + 'b' + _d + '\n', // ignore: prefer_interpolation_to_compose_strings
      'x\n\n$_d\nA\n$_d\n\ny\n',
      '$_d\nA\n$_d\n',
      '\n\n$_d\nA\n$_d\n\n\n',
    ];

    test('Backspace / Delete × 每个偏移 × 连按两下', () {
      // 数一下"真的检查过"的删除 —— 防止守卫变成**空转**（一个用例都没碰上还说全绿）
      var checked = 0;
      for (final String src in sources) {
        final int before = _display(src).length;
        for (final bool forward in <bool>[false, true]) {
          for (var o = 0; o <= src.length; o++) {
            final SmartEdit e1 = smartEditAt(src, o, forward: forward);
            if (!_onlyNewlines(src, e1)) continue;
            checked++;
            final String s1 = _apply(src, e1);
            expect(_display(s1).length, before,
                reason: '「${src.replaceAll("\n", "⏎")}」off=$o forward=$forward '
                    '删[${e1.from},${e1.to}) ⇒ 「${s1.replaceAll("\n", "⏎")}」：块数变了');
            for (final MathSpan m in _display(s1)) {
              expect(m.tex.contains(_d), isFalse,
                  reason: '「${s1.replaceAll("\n", "⏎")}」里那块 tex 含 `\$\$`：'
                      '「${m.tex.replaceAll("\n", "⏎")}」');
            }

            final SmartEdit e2 = smartEditAt(s1, e1.caret, forward: forward);
            if (!_onlyNewlines(s1, e2)) continue;
            checked++;
            final String s2 = _apply(s1, e2);
            expect(_display(s2).length, before,
                reason: '两下之后块数变了：「${src.replaceAll("\n", "⏎")}」off=$o '
                    '⇒ 「${s2.replaceAll("\n", "⏎")}」');
            for (final MathSpan m in _display(s2)) {
              expect(m.tex.contains(_d), isFalse,
                  reason: '两下之后「${s2.replaceAll("\n", "⏎")}」里那块 tex 含 `\$\$`：'
                      '「${m.tex.replaceAll("\n", "⏎")}」');
            }
          }
        }
      }
      expect(checked, greaterThanOrEqualTo(30),
          reason: '全域用例太少（实际只检查了 $checked 次）—— 守卫会变成空转');
    });
  });
}
