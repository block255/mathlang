// 反馈 1（2026-10-30 · R9）守卫：**组合串（拼音串）不许跟着光标闪烁消失**。
//
// 病灶：`caretOffset` 在闪烁灭时被传成 null ⇒ `CaretPlacement` 为 null ⇒
//   `caretOwnedBy(pl,…)` 恒 false ⇒ 组合串那条分支整条塌掉 ⇒ 拼音每 530 ms 消失一次。
// 口径（与 2026-10-18 空槽垫子同一条药方）：**位置归位置、可见性归可见性** ——
//   组合串的插入点取"不吃闪烁"的 `slotCaretOffset`。
//
// 改前必红：`caret: null` 那条断言拿不到 "hao"。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/inline_math_text.dart';

Future<String> _plain(
  WidgetTester t, {
  required int? caret,
  required int slot,
  String source = 'abc',
  String composing = 'hao',
}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: InlineMathText(
        source: source,
        caretOffset: caret,
        slotCaretOffset: slot,
        composingText: composing,
        textStyle: const TextStyle(fontSize: 16),
      ),
    ),
  ));
  await t.pumpAndSettle();
  final Text w = t.widget<Text>(find.byType(Text).first);
  return w.textSpan?.toPlainText() ?? '';
}

void main() {
  testWidgets('① 闪烁亮 / 灭：组合串都在（位置也一致）', (WidgetTester t) async {
    final String on = await _plain(t, caret: 2, slot: 2);
    final String off = await _plain(t, caret: null, slot: 2);
    expect(on.contains('hao'), isTrue, reason: '闪烁亮时组合串必须在');
    expect(off.contains('hao'), isTrue, reason: '闪烁灭时组合串不许消失（R9）');
    // 位置不变：拼音紧随光标插入点（"ab" 之后）
    expect(off.indexOf('hao'), 2, reason: '组合串必须仍在插入点，不许挪位置');
  });

  testWidgets('② 行内公式后面的组合串同样不吃闪烁', (WidgetTester t) async {
    const String src = r'$x$后文';
    final String on = await _plain(t, caret: 3, slot: 3, source: src, composing: 'ni');
    final String off =
        await _plain(t, caret: null, slot: 3, source: src, composing: 'ni');
    expect(on.contains('ni'), isTrue);
    expect(off.contains('ni'), isTrue, reason: '公式后面的组合串也不许被闪烁吃掉');
  });
}
