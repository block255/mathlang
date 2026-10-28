// 删除把"一段删空" / 文末删末字 / 行首标记被拆坏（2026-10-28 用户手测；先红后绿）
//
// ★★ 入口必须是 **`smartEditAt`** —— 那是界面真正走的路（`edit_view.dart:1085`
//   `_applyEdit(smartEditAt(_buf.buf, _buf.caret, …))`）。
//   `DocBuffer.deleteBackward()` 是**死路径**（lib/ 里没人调它），用它写的守卫等于
//   测用户永远走不到的路 —— 2026-10-28 第一版守卫就是这么写错的，已作废重写。
//
// 用户现象：
//   ① 把中间那一段的字删光 ⇒ **多出一个空行**（本该只剩一个空行、光标在行首）；
//   ② 在文末最后一行的行尾删光 ⇒ **光标掉到下一行**；
//   ③ 标题删光内容后再退格 ⇒ **爆出一个 `#`**（`_headingRe` 要求 `#` 后必须有空格，
//      删掉那个空格 ⇒ 块降级 ⇒ `#` 变成可见正文）。
//
// 口径：
//   · 空段落 = **1 行**（"1 个 `\n` = 1 行"，段界那个 `\n` 不算行）；
//   · 行首标记（`# ` / `- ` / `> ` / `---`）是**存储细节**，永远不许漏成正文 ——
//     删到它就整块处置（标题降级为正文、分隔线整行去掉），一步撤销。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/blank_runs.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_nav.dart';
import 'package:mathlang/render/smart_delete.dart';

/// 把一次删除落到缓冲区上
({String buf, int caret}) _apply(String src, int offset, {bool forward = false}) {
  final SmartEdit e = smartEditAt(src, offset, forward: forward);
  if (e.isNone) return (buf: src, caret: offset);
  return (
    buf: src.replaceRange(e.from!, e.to!, ''),
    caret: e.caret,
  );
}

/// 段间那串空行占几行（与版面同一把尺子）
double _blankRows(String buf) =>
    extraBlankHeight(blankRunAfter(buf, 1).length, lineHeight: 38.4) / 38.4;

void main() {
  group('① 把中间一段删空（不许冒出多余的行）', () {
    test('A⏎⏎xy⏎⏎B⏎：删光 xy ⇒ A⏎⏎⏎B⏎，光标在那个空行行首', () {
      final ({String buf, int caret}) r = _apply('A\n\nxy\n\nB\n', 5);
      final ({String buf, int caret}) r2 = _apply(r.buf, r.caret);
      expect(r2.buf, 'A\n\n\nB\n', reason: '两个段界并置出来的多余换行要收掉');
      expect(r2.caret, 3, reason: '光标落在那个空行的行首');
      expect(_blankRows(r2.buf), 1.0, reason: '空段落 = 1 行');
    });

    test('只删半个词不受影响', () {
      final ({String buf, int caret}) r = _apply('A\n\nxyz\n\nB\n', 6);
      expect(r.buf, 'A\n\nxy\n\nB\n');
      expect(r.caret, 5);
    });
  });

  group('② 文末最后一行的行尾删光（光标不许下移）', () {
    test('A⏎⏎B⏎：删掉 B ⇒ A⏎⏎，光标在那一行（不是下一行）', () {
      final ({String buf, int caret}) r = _apply('A\n\nB\n', 4);
      expect(r.buf, 'A\n\n', reason: '末尾那串多余的换行要收掉');
      expect(r.caret, 2, reason: '光标停在原来 B 那一行（现在是空行）');
    });
  });

  group('③ 文首那一段删空（对称收掉）', () {
    test('xy⏎⏎B⏎：删光 xy ⇒ ⏎B⏎，1 个空行', () {
      final ({String buf, int caret}) r = _apply('xy\n\nB\n', 2);
      final ({String buf, int caret}) r2 = _apply(r.buf, r.caret);
      expect(r2.buf, '\nB\n');
      expect(r2.caret, 0);
    });
  });

  group('④ 行首标记不许被拆坏', () {
    test('空标题 "＃ ⏎" 再退格 ⇒ 整块降级为正文（绝不出现 ＃）', () {
      final ({String buf, int caret}) r = _apply('# \n', 2);
      expect(r.buf, '\n', reason: '整个标记 "# " 一起走，块降级成正文空行');
      expect(r.caret, 0);
      expect(r.buf.contains('#'), isFalse, reason: '**绝不许把 # 漏成正文**');
    });

    test('有内容的标题里删到标记 ⇒ 也是整块降级，内容保留', () {
      final ({String buf, int caret}) r = _apply('# abc\n', 2);
      expect(r.buf, 'abc\n');
      expect(r.caret, 0);
      expect(r.buf.contains('#'), isFalse);
    });

    test('向前删（Delete）落在标记上同样整块降级', () {
      final ({String buf, int caret}) r = _apply('# abc\n', 0, forward: true);
      expect(r.buf, 'abc\n');
      expect(r.buf.contains('#'), isFalse);
    });

    test('分隔线 "---" 删一个字符 ⇒ 整行去掉（不留 "--"）', () {
      final ({String buf, int caret}) r = _apply('A\n\n---\n\nB\n', 4);
      expect(r.buf, 'A\n\n\nB\n', reason: '整行（含它的换行）一起走');
      expect(r.buf.contains('-'), isFalse);
    });

    test('普通正文行内删字不受影响（没有标记）', () {
      // offset 6 = `xyz` 的 `z` 之前（offset 3 是段落边界那一格，那是另一条判据）
      final ({String buf, int caret}) r = _apply('A\n\nxyz\n\nB\n', 6);
      expect(r.buf, 'A\n\nxy\n\nB\n');
      expect(r.caret, 5);
    });
  });

  group('⑤ 反例：Enter 造出来的空行不许被顺手合并（基准 2 / 3）', () {    test('基准 2：A⏎ 得 A-空行-B，仍是 3 个换行、1 行', () {
      expect(_blankRows('A\n\n\nB\n'), 1.0);
      // 在那一格上退格：收掉这一行、回到 A 行末（基准 2 后半句）
      final ({String buf, int caret}) r = _apply('A\n\n\nB\n', 3);
      expect(r.buf, 'A\n\nB\n');
      expect(r.caret, 1);
    });

    test('基准 3：空行上再按 Enter ⇒ 2 行；再退格回到 1 行', () {
      expect(_blankRows('A\n\n\n\nB\n'), 2.0);
      final ({String buf, int caret}) r = _apply('A\n\n\n\nB\n', 4);
      expect(_blankRows(r.buf), 1.0);
    });
  });

  // ---------------------------------------------------------------- 版面层
  //
  // 上面断的是"字节 + 光标偏移"；这一组断**用户真正看到的东西**：光标落在哪一行。
  // 用真 `EditView` 渲染，再把 `smartEditAt` 的结果落进缓冲区（界面就是这么做的：
  // `edit_view.dart:1085 _applyEdit(smartEditAt(...))`）。

  group('⑥ 【版面】光标不下移 / 不多出一行', () {
    testWidgets('删空中间段：光标 y 与删之前相同', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('A\n\nxy\n\nB\n');
      await _mount(tester, buf);
      buf.setCaret(5);
      await tester.pump();
      await tester.pump();
      final double? before = _caretY(tester);
      for (var i = 0; i < 2; i++) {
        final ({String buf, int caret}) r = _apply(buf.buf, buf.caret);
        final SmartEdit e = smartEditAt(buf.buf, buf.caret, forward: false);
        if (!e.isNone) buf.replace(e.from!, e.to!, '');
        buf.setCaret(r.caret);
        await tester.pump();
      }
      final double? after = _caretY(tester);
      expect(before, isNotNull);
      expect(after, before, reason: '空段落占的是原来那一段那一行，不该往下掉');
    });

    testWidgets('文末删末字：光标 y 不变', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('A\n\nB\n');
      await _mount(tester, buf);
      buf.setCaret(4);
      await tester.pump();
      await tester.pump();
      final double? before = _caretY(tester);
      final SmartEdit e = smartEditAt(buf.buf, buf.caret, forward: false);
      expect(e.isNone, isFalse);
      buf.replace(e.from!, e.to!, '');
      buf.setCaret(e.caret);
      await tester.pump();
      await tester.pump();
      expect(_caretY(tester), before);
    });
  });
}

/// 挂一个真 `EditView`
Future<void> _mount(WidgetTester tester, DocBuffer buf) async {
  tester.view.physicalSize = const Size(900, 5200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
}

/// 光标竖条的 y（`Container(width:1.5)` 那一族）
double? _caretY(WidgetTester tester) {
  for (final Element e in find.byType(Container).evaluate()) {
    final Widget w = e.widget;
    if (w is! Container) continue;
    final BoxConstraints? c = w.constraints;
    if (c == null || c.minWidth != 1.5 || c.maxWidth != 1.5) continue;
    final RenderObject? ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize) {
      return ro.localToGlobal(Offset.zero).dy.roundToDouble();
    }
  }
  return null;
}
