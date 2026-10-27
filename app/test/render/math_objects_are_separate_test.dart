// ★★ 同地位原则的守卫：**一个行内数学段不是一个"整体公式"**（2026-10-15 用户提出）
//
// 用户原话：「按照我们数学语言与文本同地位的理念，**简单的多项式结构按道理应该不会被认定为一个整体的公式**」。
// 起因：§6.5 的第一版给"光标所在的那一整段公式"刷了一层淡色底 —— 用户一眼看出来，因为
//   `$\frac{a}{b}=\sqrt{2}$` 在他眼里是**三个对象**（分式 / `=` / 根号），**不是一整个公式**。
//
// 本文件把这条原则**钉成不变量**（而不只是"把底色撤掉"）：
//   · `$…$` 只是**渲染提示**：不是对象、不是层级（§3.3 的「同权」精确边界）
//   · 段内的对象**各自独立**：分式、`=`、根号、原子…… 每一个都能被**单独**删掉
//   · ★ **没有任何一个位点上的删除会一次吃掉整段**（除了本来就只有"一个对象"的情形）
//
// 它同时守住"渲染提示 ≠ 对象"这件事的两个面：**删除粒度**（本文件）与**视觉**（不许整段底色）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/smart_delete.dart';

/// `\frac{a}{b}=\sqrt{2}` —— 用户举的那个"简单多项式结构"
///   `\frac{a}{b}` = [0,11) · `=` = [11,12) · `\sqrt{2}` = [12,20)
const String kTex = r'\frac{a}{b}=\sqrt{2}';

Future<EditViewState> _mountEdit(WidgetTester tester, DocBuffer buf) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: EditView(buffer: buf)),
    ),
  ));
  final EditViewState st = tester.state<EditViewState>(find.byType(EditView));
  st.focusInput();
  await tester.pump();
  return st;
}

void main() {
  group('★★ 段内对象各自独立：三个对象，不是一个整体', () {
    void expectDeletes(int rel, String want, {bool forward = false}) {
      final CaretSiteTable t = buildCaretSites(kTex);
      final SmartEdit e = forward ? smartDelete(t, rel) : smartBackspace(t, rel);
      expect(e.deletes, isTrue, reason: 'rel=$rel $e');
      expect(kTex.substring(e.from!, e.to!), want,
          reason: 'rel=$rel ${forward ? "Delete" : "Backspace"} 应当只删 `$want`，实际 $e');
    }

    test(r'★ 分式：整体之后退格 → **只删分式**（`=` 与根号都在）', () {
      expectDeletes(11, r'\frac{a}{b}');
    });

    test(r'★ `=`：它自己就是一个对象（左边界退格 / 右边界 Delete 都只删它）', () {
      expectDeletes(12, '='); // 光标在 `=` 之后 → 退格删左邻
      expectDeletes(11, '=', forward: true); // 光标在 `=` 之前 → Delete 删右邻
    });

    test(r'★ 根号：末尾退格 → **只删根号**（前面的分式与 `=` 都在）', () {
      expectDeletes(20, r'\sqrt{2}');
    });

    test(r'★ 根号**里面**（`2` 之后）退格 → 只删 `2`（根号留着）', () {
      expectDeletes(19, '2');
    });

    test(r'★★ 全域：**没有任何位点上的删除会一次吃掉整段**', () {
      final CaretSiteTable t = buildCaretSites(kTex);
      for (final int rel in t.offsets) {
        for (final bool forward in <bool>[false, true]) {
          final SmartEdit e =
              forward ? smartDelete(t, rel) : smartBackspace(t, rel);
          if (!e.deletes) continue;
          final int len = e.to! - e.from!;
          expect(len, lessThan(kTex.length),
              reason: '在 rel=$rel 按 ${forward ? "Delete" : "Backspace"} 竟然一次删掉了整段 '
                  '`$kTex`（${e.from}..${e.to}）—— 那就等于把它当成了一个"整体公式"');
        }
      }
    });
  });

  group('★ 端到端：在真实编辑面上验证"各自独立"', () {
    testWidgets(r'光标在 `=` 之后退格 → **只有 `=` 消失**（缓冲区其余一字不动）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('设 \$$kTex\$ 为常数');
      await _mountEdit(tester, buf);
      await tester.pumpAndSettle();

      final int eq = buf.buf.indexOf('=');
      buf.setCaret(eq + 1);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(buf.buf, '${r'设 $\frac{a}{b}\sqrt{2}$ 为常数'}\n',
          reason: '★ 只该删掉 `=`；实际：${buf.buf}');
    });

    testWidgets(r'光标在根号**整体**之后退格 → **只有根号消失**', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('设 \$$kTex\$ 为常数');
      await _mountEdit(tester, buf);
      await tester.pumpAndSettle();

      // 公式 tex 的末尾（= 根号之后；与"公式之后"同一根像素）
      final int texEnd = buf.buf.indexOf(r'\sqrt{2}') + r'\sqrt{2}'.length;
      buf.setCaret(texEnd);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(buf.buf, '${r'设 $\frac{a}{b}=$ 为常数'}\n',
          reason: '★ 只该删掉根号；实际：${buf.buf}');
    });
  });
}
