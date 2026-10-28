// 批 23（③ 剩下一半）：块与块之间"空一行"时的**双光标** —— 口径是「空行让位」。
//
// 用户实测（2026-10-24 20:0x 第二组图）：`aaa` + 三个行间块，**块与块之间空一行**
// （`$$\n…\n$$\n\n$$\n…`）。屏幕上两根竖条：
//   · 一根在**页面左边的行首** = 空行自己的文本光标（`_BlankSlot`）；
//   · 一根在**块的左缘** = 块的"块之前"边界条（`doc_view` 的 `beforeBlock`）。
//
// 根因（不是"多画了一根"，是**两个主人**）：行间块认领 `sliceStart - 1`，
// 而那个位置**正是空行自己的换行** ⇒ 空行行首 == 下一块的 `acceptFrom` ⇒ 同一格两根。
//
// 口径：**一个偏移只画一根** ⇒ 让块画（"块之前"条贴块左缘，正好表示"要进这块"）。
// 守卫两半，缺一不可：
//   ① 与下一块 `acceptFrom` 同一格的空行 ⇒ **不画**（改前必红）；
//   ② 空行**没有**相邻行间块 ⇒ **照常画**（防"过度让位"把普通空行的光标弄没）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';

/// 用户那份形状的最小化：段落 + 两个行间块，**块之间空一行**。
const String kDoc = '甲\n\n\$\$\na\n\$\$\n\n\$\$\nb\n\$\$\n';

/// 空行后面跟的是**普通段落**（没有相邻行间块）。
/// ★ 2026-10-28：必须是**两个**空行（`甲⏎⏎⏎乙`）—— 一个空行是**段落分隔符**
///   （零高度、不是位置），它不画光标；真行是 `3`。
const String kPlain = '甲\n\n\n乙\n';

/// 连续**两个**空行 + 一个行间块（空行槽覆盖两行）。
/// ★ 2026-10-28：改成**三个**空行（`甲⏎⏎⏎⏎$$`）—— 第一个是分隔符，真行才是后两个。
const String kTwoBlanks = '甲\n\n\n\n\$\$\na\n\$\$\n';

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

void main() {
  group('批 23 · 空行与"下一块"抢同一格', () {
    testWidgets(r'★ ① 块与块之间空一行：空行**不画**，由块画（改前必红）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(kDoc);
      await _mount(tester, buf);

      // 两个空行的行首：第一段之后、两块之间
      final int blank1 = kDoc.indexOf('\n\n') + 1;
      final int blank2 = kDoc.indexOf('\n\n', blank1 + 1) + 1;
      final int openA = kDoc.indexOf(r'$$');
      // ★ 四个 `$$`：A 开 / A 收 / B 开 / B 收 ⇒ B 的开围栏是**第三个**
      final int closeA = kDoc.indexOf(r'$$', openA + 2);
      final int openB = kDoc.indexOf(r'$$', closeA + 2);
      // 前置条件：块认领的正是空行那一格（否则这条用例根本没打中病灶）
      expect(openA - 1, blank1, reason: '块 A 的 acceptFrom 必须等于空行行首');
      expect(openB - 1, blank2, reason: '块 B 的 acceptFrom 必须等于空行行首');

      buf.setCaret(blank1);
      await tester.pump();
      await tester.pump();
      expect(_blankDrawsAt(tester, blank1), isFalse,
          reason: '空行行首 == 块 A 的 acceptFrom ⇒ 这一格让给块画；'
              '若为 true = 屏幕上会同时出现"空行光标"和"块之前"两根竖条');
      expect(_someBlockShowsCaret(tester), isTrue,
          reason: '让位之后必须**真的有人画** —— 块 A 的"块之前"边界条');

      buf.setCaret(blank2);
      await tester.pump();
      await tester.pump();
      expect(_blankDrawsAt(tester, blank2), isFalse,
          reason: '两块之间那个空行同理（这是用户截图里的第二根）');
      expect(_someBlockShowsCaret(tester), isTrue);
    });

    testWidgets('② 空行后面是普通段落 ⇒ 空行**照常画**（防过度让位）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(kPlain);
      await _mount(tester, buf);

      final int blank = kPlain.indexOf('\n\n') + 2; // ★ 第 2 个空行才是真行（第 1 个是分隔符）
      buf.setCaret(blank);
      await tester.pump();
      await tester.pump();
      expect(_blankDrawsAt(tester, blank), isTrue,
          reason: '空行没有相邻行间块 ⇒ 必须自己画；若为 false = "光标消失"');
      expect(_someBlockShowsCaret(tester), isFalse,
          reason: '这段文档里没有行间块，不该有块来抢');
    });

    testWidgets('③ 连续两个空行：只有**贴着块**那一行让位，前一行照旧自己画',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(kTwoBlanks);
      await _mount(tester, buf);

      final int open = kTwoBlanks.indexOf(r'$$');
      final int nearBlock = open - 1; // 贴着块的空行（== acceptFrom）
      final int earlier = nearBlock - 1; // 更早那个空行
      expect(nearBlock, kTwoBlanks.indexOf('\n\n') + 3,
          reason: '前置：这段文档里贴块的空行是第三个空行（第一个是段落分隔符）');

      buf.setCaret(earlier);
      await tester.pump();
      await tester.pump();
      expect(_blankDrawsAt(tester, earlier), isTrue,
          reason: '远离块的那一行空行仍归空行槽画');

      buf.setCaret(nearBlock);
      await tester.pump();
      await tester.pump();
      expect(_blankDrawsAt(tester, nearBlock), isFalse,
          reason: '贴着块的那一行让位给块');
    });
  });
}
