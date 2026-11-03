// P7（2026-11-04）：**喂给 IME 的光标矩形**不许依赖"盒子与计算谁先跑"。
//
// 现场：同一份缓冲区、同一偏移 0 ——
//   · 新加载 ⇒ `onCaretRect` 报 **null**（空行槽的盒子还没进表，计算就跑了）
//   · 抖动一下光标（换值再换回来）⇒ 先报 `140.3`、再报 `95.6`（连算两次给两个值）
//   ⇒ 帧末回调的注册顺序决定结果，而且**之后没有任何东西重算**。
//
// 修法：空行槽帧末上报盒子时，若那正是光标所在的槽 ⇒ **当场重算一次**（闭环）。
// 改前必红：①②（新加载那条一个非空矩形都没有）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/doc_view.dart';

import '../support/math_fonts.dart';

Future<({DocBuffer buf, List<Rect?> carets})> mount(
  WidgetTester t,
  String doc,
  int caret,
) async {
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  final List<Rect?> carets = <Rect?>[];
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DocView(buffer: buf, onCaretRect: carets.add),
      ),
    ),
  ));
  await t.pumpAndSettle();
  return (buf: buf, carets: carets);
}

Rect? lastNonNull(List<Rect?> rs) {
  for (var i = rs.length - 1; i >= 0; i--) {
    if (rs[i] != null) return rs[i];
  }
  return null;
}

void main() {
  setUpAll(() async {
    await loadMathFonts();
  });

  // 文首一个空行 + 一行行内公式：光标 0 落在空行槽上
  final String doc = '\n' r'$f^{\prime}$' '(x)\n\na\n';

  testWidgets('① 新加载（光标落在空行上）⇒ 必须报出非空的光标矩形',
      (WidgetTester t) async {
    final ({DocBuffer buf, List<Rect?> carets}) r = await mount(t, doc, 0);
    expect(r.carets, isNotEmpty, reason: 'onCaretRect 至少要被调一次');
    expect(lastNonNull(r.carets), isNotNull,
        reason: '改前：全是 null —— 空行槽的盒子还没上报就算完了');
  });

  testWidgets('② 新加载的值必须等于"抖动之后"的值（两条路同一个答案）',
      (WidgetTester t) async {
    final ({DocBuffer buf, List<Rect?> carets}) r = await mount(t, doc, 0);
    final Rect? fresh = lastNonNull(r.carets);

    // 抖动：换一个值再换回来（强制触发两次重算，此时盒子一定已经上报）
    r.buf.setCaret(1);
    await t.pumpAndSettle();
    r.buf.setCaret(0);
    await t.pumpAndSettle();
    final Rect? bounced = lastNonNull(r.carets);

    expect(fresh, isNotNull);
    expect(bounced, isNotNull);
    expect((bounced!.top - fresh!.top).abs(), lessThan(0.5),
        reason: '改前：新加载 null / 抖动后 140.3 与 95.6 两个值');
    expect((bounced.left - fresh.left).abs(), lessThan(0.5));
  });
}
