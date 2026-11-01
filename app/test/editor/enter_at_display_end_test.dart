// 行间块**末尾**按 Enter：只许多**一**行，且光标必须看得见（2026-11-01 用户实测）。
//
// 现场（用户两图）：光标停在公式末尾（`)` 之后、收尾 `$$` 之前）按 Enter ——
//   屏幕上多出**两行**，光标落在第一个空行上；再按一次又叠一层（"双下行"）。
// 根因：`_enter` 的"结构内部"分支要求 `c != le`，而"公式末尾"恰好是**行末**
//   ⇒ 掉进通用路径 ⇒ 载荷 `\n\n` 被 `insert_guard` 整体推到公式之后 ⇒ 一次按键两行。
// 修法：把"行间块最后一行行末"也算结构内部（`displayTexEnd`），落点问行表不再手算 `at+2`。
//
// 改前必红：①（`$$` 后 2 个换行 → **4** 个）

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/math_caret.dart';

Future<void> _mount(WidgetTester t, DocBuffer buf) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  t.state<EditViewState>(find.byType(EditView)).focusInput();
  await t.pumpAndSettle();
}

/// 场上**看得见**的竖条数（尺寸 > 1 的光标色 Container ＋ 公式层竖条）。
/// ⚠️ 不能只按颜色数：场上有一个 0×0 的"光标色"占位盒。
int _visibleCarets(WidgetTester t) {
  var n = 0;
  for (final Element e in find
      .byWidgetPredicate((Widget w) =>
          w is Container && w.color == const Color(kCaretColorValue))
      .evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize && ro.size.height > 1) n++;
  }
  for (final Element e in find.byType(MathWithCaret).evaluate()) {
    final MathWithCaret w = e.widget as MathWithCaret;
    if (!w.showCaret) continue;
    final dynamic st = (e as StatefulElement).state as dynamic;
    if (st.debugCaretBar != null) n++;
  }
  return n;
}

void main() {
  const String doc = '前\n'
      '\$\$\n\\ \\ \\ =\\lim_{x\\to0}(xsin\\frac{1}{x})\n\$\$\n\n'
      '\$\$\n\\ \\ \\ =\\lim_{t\\to\\infty}\\frac{sint}{t}\n\$\$\n后\n';

  testWidgets('① 公式末尾按 Enter：块后只多**一**行', (WidgetTester t) async {
    final DocBuffer buf = DocBuffer(doc);
    await _mount(t, buf);
    final int close = buf.buf.indexOf(r'$', buf.buf.indexOf(r'\frac{1}{x}'));
    // 块后原本 2 个换行（k=2：只有段距）
    int nl(String s) {
      var k = 0;
      // ★ 收尾 $$ 占 close..close+1，换行从 close+2 起
      while (close + 2 + k < s.length && s[close + 2 + k] == '\n') {
        k++;
      }
      return k;
    }

    expect(nl(buf.buf), 2, reason: '前提：块后原本 2 个换行');
    buf.setCaret(close - 1); // ★ 真·公式末尾（`)` 之后、收尾 `$$` 之前）
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(nl(buf.buf), 3, reason: '一次 Enter 只许多一行（改前是 4 —— 双下行）');
  });

  testWidgets('② 按完之后光标必须看得见（恰好一根）', (WidgetTester t) async {
    final DocBuffer buf = DocBuffer(doc);
    await _mount(t, buf);
    final int close = buf.buf.indexOf(r'$', buf.buf.indexOf(r'\frac{1}{x}'));
    buf.setCaret(close - 1);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(_visibleCarets(t), 1, reason: 'Enter 之后必须恰好一根竖条（不能消失、不能两根）');
  });
}


