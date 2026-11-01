// 批 23（2026-10-24）建立：**块与块之间"空一行"时的双光标**。
//
// 用户实测（20:0x 第二组图）：`aaa` + 三个行间块，**块与块之间空一行**
// （`$$\n…\n$$\n\n$$\n…`）。屏幕上一根在**页面左边的行首**（空行自己的文本光标）、
// 一根在**块的左缘**（块的"块之前"边界条）。
//
// ★★★ 2026-11-01 **口径推翻重写**（台账 F13）：根因不是"空行该让位"，而是
//   **块多认领了前面那一格**（`acceptFrom = sliceStart - 1`）。
//   旧口径：空行行首 == 块的 `acceptFrom` ⇒ 空行让位、由块画（批 23 的补丁）。
//   新口径：块的行首是**它自己的 `$$`**（`acceptFrom = sliceStart`）⇒ 与空行行首差 1
//           ⇒ **不再重叠** ⇒ 各画各的，谁都不用让。
//
// 守卫三条（缺一不可）：
//   ① "空一行"（`\n\n` ⇒ **段落分隔符**，零高度）⇒ **0 根**（它不是位置，谁都不该画）；
//   ② 真行（`\n\n\n` 的第二个空行）⇒ 空行自己画 **1 根**，块不画；
//   ③ 打上字之后（真空行变成文字行）⇒ 文字层画 **1 根**，块不画。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/core/paragraph_break.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';

/// 段落 + 两个行间块，**块之间空一行**（= 两个换行 = 段落分隔符）。
const String kDoc = '甲\n\n\$\$\na\n\$\$\n\n\$\$\nb\n\$\$\n';

/// 连续**两个**空行 + 一个行间块：第一个是分隔符，后两个是真行
/// （`甲⏎⏎⏎⏎$$`：`\n` 三个以上才出真行）。
const String kTwoBlanks = '甲\n\n\n\n\$\$\na\n\$\$\n';

/// 真行上打了字（`甲⏎⏎w⏎$$`）。
const String kTyped = '甲\n\nw\n\$\$\na\n\$\$\n';

Future<void> _mount(WidgetTester tester, DocBuffer buf) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
}

/// 所有空行槽（`_BlankSlot` 是私有类，按运行时类型名取；量测树里也有同一个，
/// 所以同名参数会出现两份 —— 这里取「是否**全部**都画」的与）。
List<dynamic> _blankSlots(WidgetTester tester) => tester.allWidgets
    .where((Widget w) => w.runtimeType.toString() == '_BlankSlot')
    .map((Widget w) => w as dynamic)
    .toList();

/// 覆盖 [blankStart] 那一行的空行槽，`caretHere` 是不是**全部**为 true。
bool? _blankDrawsAt(WidgetTester tester, int blankStart) {
  bool? all;
  for (final dynamic b in _blankSlots(tester)) {
    final List<int> run = b.lineOffsets as List<int>;
    if (!run.contains(blankStart)) continue;
    final bool here = b.caretHere as bool;
    all = all == null ? here : (all && here);
  }
  return all;
}

bool _someBlockShowsCaret(WidgetTester tester) => find
    .byType(MathWithCaret)
    .evaluate()
    .any((Element e) => (e.widget as MathWithCaret).showCaret);

int _textBars(WidgetTester tester) {
  var n = 0;
  for (final Element e in find.byType(Container).evaluate()) {
    final Widget w = e.widget;
    if (w is! Container) continue;
    final BoxConstraints? c = w.constraints;
    if (c == null || c.minWidth != 1.5 || c.maxWidth != 1.5) continue;
    n++;
  }
  return n;
}

void main() {
  group('批 23 · 空行与"下一块"不再抢同一格', () {
    testWidgets(r'★ ① 块与块之间"空一行" = 段落分隔符 ⇒ 0 根（F13 新口径）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(kDoc);
      await _mount(tester, buf);

      final int blank1 = kDoc.indexOf('\n\n') + 1;
      final int openA = kDoc.indexOf(r'$$');
      final int closeA = kDoc.indexOf(r'$$', openA + 2);
      final int openB = kDoc.indexOf(r'$$', closeA + 2);
      final int blank2 = kDoc.indexOf('\n\n', blank1 + 1) + 1;

      // 前置：这两格**确实**是段落分隔符（零高度、不是位置）
      expect(isParagraphSeparator(kDoc, blank1), isTrue,
          reason: '前置：`甲⏎⏎\$\$` 的第二个换行是分隔符');
      expect(isParagraphSeparator(kDoc, blank2), isTrue,
          reason: '前置：`\$\$⏎⏎\$\$` 的第二个换行也是分隔符');
      // 前置：块的行首是**它自己的 `$$`**（新口径），不再是"前面那一格"
      expect(openA, blank1 + 1, reason: '块 A 的行首紧接在分隔符之后（差 1 格）');
      expect(openB, blank2 + 1, reason: '块 B 同理');

      for (final int blank in <int>[blank1, blank2]) {
        buf.setCaret(blank);
        await tester.pump();
        await tester.pump();
        expect(_blankDrawsAt(tester, blank), isNot(isTrue),
            reason: '分隔符不进落点表 ⇒ 空行槽要么不覆盖它（null）、要么覆盖了也不画（false）');
        expect(_someBlockShowsCaret(tester), isFalse,
            reason: '★★ 块**不该**认领分隔符那一格（改前：块在这里画一根"块之前"'
                '＋ 一根刻度 = 用户看到的"一个刻度两个光标"）');
        expect(_textBars(tester), 0, reason: '这一格一根竖条都不该有');
      }
    });

    testWidgets('★★ ② 真行（`甲⏎⏎⏎⏎\$\$` 的第二个空行）⇒ 空行自己画 1 根，块不画',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(kTwoBlanks);
      await _mount(tester, buf);

      final int open = kTwoBlanks.indexOf(r'$$');
      final int nearBlock = open - 1; // 贴着块的那一行（真行）
      final int earlier = nearBlock - 1; // 更早那一行

      for (final int row in <int>[earlier, nearBlock]) {
        buf.setCaret(row);
        await tester.pump();
        await tester.pump();
        expect(_blankDrawsAt(tester, row), isTrue,
            reason: '★★ 真行（有行盒）⇒ 它自己画。改前：贴着块那一行被"让位"掉，'
                '而块的条又画在块边缘 ⇒ 要么两根、要么一根画错地方');
        expect(_someBlockShowsCaret(tester), isFalse,
            reason: '块的行首是它自己的 `\$\$`（= $open），不是这一行 ⇒ 块不该在这里画');
      }
    });

    testWidgets('★★ ③ 真行打了字（`甲⏎⏎w⏎\$\$`）⇒ 文字层 1 根，块不画',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(kTyped);
      await _mount(tester, buf);

      final int w = kTyped.indexOf('w');
      final int afterW = w + 1; // `w` 后面那一格 = 这一行的行尾
      expect(isParagraphSeparator(kTyped, afterW), isFalse,
          reason: '前置：这是真行尾，不是分隔符');

      buf.setCaret(afterW);
      await tester.pump();
      await tester.pump();
      expect(_textBars(tester), 1,
          reason: '★ 这一行有内容 ⇒ 文字层画它自己的行尾光标（正好 1 根）');
      expect(_someBlockShowsCaret(tester), isFalse,
          reason: '★★ 改前：块也认领这一格 ⇒ 文字 1 根 ＋ 块 1 根 ＋ 刻度 = 三根'
              '（用户 2026-11-01 那两张图）');
    });
  });
}
