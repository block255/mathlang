// 批 38（2026-10-26）：**分页符那一行 + 每一页底部的剩余白**都要能看见光标、能点。
//
// 用户 20261026 实测两条：
//   ①「原页分页后，原页留下的下面那片空白没有点击判定」；
//   ②「在文末按 Enter 到下一个空行，也不显示光标（虽然继续打字还是可以打出来）」。
// 探针（已删）实测：
//   `甲\n<!-- pagebreak -->\n`         ⇒ 偏移 2..21 **一根光标条都没有**（分页符行 19 格全死）
//   `甲\n<!-- pagebreak -->\n\n\n`     ⇒ 全部 0（分页符后面那页没有单元 ⇒ 文末槽不建）
//   对照 `甲\n\n\n`（没分页符）        ⇒ 2..4 各 1 根（正常）
// 根因：
//   · `doc_view._buildUnits` 对分页符块直接 `continue` ⇒ **它不产单元** ⇒ 没有命中盒、没有认领；
//   · 页尾槽原来只在**末页**建，且要求 `prevUnit != null` ⇒ 「分页符之后的空页」整页无槽。
//
// 口径（用户 2026-10-26 拍板 **甲-1**）：
//   · **末页**那片白 = "文末那片空白"，点它 = 起一行空行（既有口径，本次只放宽成立条件）；
//   · **非末页**那片白 = **接缝带**，点它**只落光标、不改文档**（⇒ 不会重排、不会翻页）；
//   · 接缝带里的位置（含分页符那 19 格）由这个槽认领光标条。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

/// 2 页：第 1 页「甲 + 分页符」，第 2 页「乙」
const String kSeam = '甲\n<!-- pagebreak -->\n乙\n';

/// 2 页，第 2 页是**空页**（分页符之后什么都没有，只有空行）
const String kEmptyTail = '甲\n<!-- pagebreak -->\n\n\n';

/// 3 页
const String kThree = '甲\n<!-- pagebreak -->\n乙\n<!-- pagebreak -->\n丙\n';

Future<DocBuffer> _mount(WidgetTester tester, String doc) async {
  // ★ 视口要够高：三页 A4（约 3×1123px + 页间距）都要在视口里，否则下面的页不建 widget
  tester.view.physicalSize = const Size(900, 5200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

/// 可见光标条 = `Container(width: 1.5)`（文本层 / 空行槽 / 接缝槽都是这个形状）
int _bars(WidgetTester tester) {
  var n = 0;
  for (final Widget w in tester.allWidgets) {
    if (w is! Container) continue;
    final BoxConstraints? c = w.constraints;
    if (c != null && c.minWidth == 1.5 && c.maxWidth == 1.5) n++;
  }
  return n;
}

Future<int> _barsAt(WidgetTester tester, DocBuffer buf, int off) async {
  buf.setCaret(off);
  await tester.pump();
  await tester.pump();
  return _bars(tester);
}

/// 所有空行/接缝槽的矩形（按屏幕从上到下排）
List<Rect> _slotRects(WidgetTester tester) {
  final List<Rect> out = <Rect>[];
  final Finder f = find.byWidgetPredicate(
      (Widget w) => w.runtimeType.toString() == '_BlankSlot');
  for (final Element e in f.evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize) {
      out.add(ro.localToGlobal(Offset.zero) & ro.size);
    }
  }
  out.sort((Rect a, Rect b) => a.top.compareTo(b.top));
  return out;
}

void main() {
  group('★ 全域：分页符那种文档，每个偏移都要看得见光标', () {
    testWidgets('★ 两页（第 1 页 = 甲 + 分页符）', (WidgetTester tester) async {
      final DocBuffer buf = await _mount(tester, kSeam);
      for (var off = 0; off <= kSeam.length; off++) {
        expect(await _barsAt(tester, buf, off), greaterThan(0),
            reason: '偏移 $off 一根光标条都没有（改前：分页符那 19 格全死）');
      }
    });

    testWidgets('★ 分页符后面是**空页**（用户"文末按 Enter"的那种）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _mount(tester, kEmptyTail);
      for (var off = 0; off <= kEmptyTail.length; off++) {
        expect(await _barsAt(tester, buf, off), greaterThan(0),
            reason: '偏移 $off（改前：分页符 19 格 + 后面空页全死）');
      }
    });

    testWidgets('★ 三页文档全域', (WidgetTester tester) async {
      final DocBuffer buf = await _mount(tester, kThree);
      for (var off = 0; off <= kThree.length; off++) {
        expect(await _barsAt(tester, buf, off), greaterThan(0),
            reason: '偏移 $off');
      }
    });
  });

  group('★ 页面底部那片白：中间页只落光标、末页起一行空行（用户 2026-10-26 拍板 甲-1）', () {
    testWidgets('★ 点第 1 页底部的空白 ⇒ 光标落到**分页符行首**，文档一字不变',
        (WidgetTester tester) async {
      final DocBuffer buf = await _mount(tester, kSeam);
      final String before = buf.buf;
      final List<Rect> slots = _slotRects(tester);
      expect(slots.length, greaterThanOrEqualTo(2),
          reason: '第 1 页也要有一个页尾槽（改前只有末页有）');
      await tester.tapAt(slots.first.center);
      await tester.pumpAndSettle();
      expect(buf.buf, before, reason: '中间页点空白**不许改文档**（否则会重排/翻页）');
      expect(buf.caret, kSeam.indexOf('<!--'),
          reason: '接缝带的第一个位置 = 分页符行首；实际落在 ${buf.caret}');
    });

    testWidgets('★ 点末页那片白 ⇒ 仍然"起一行空行"（既有口径不许被我改坏）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _mount(tester, '甲\n\n乙\n');
      final String before = buf.buf;
      final List<Rect> slots = _slotRects(tester);
      expect(slots, isNotEmpty);
      await tester.tapAt(slots.last.center);
      await tester.pumpAndSettle();
      expect(buf.buf.length, greaterThan(before.length),
          reason: '末页那片白 = 文末那片空白：点它要起一行空行（改前行为）');
      expect(buf.caret, buf.buf.length, reason: '光标落在新空行的行首');
    });

    testWidgets('★ 分页符行内每格**只有一根**光标条（不许页尾槽与单元叠两根）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _mount(tester, kSeam);
      final int pb = kSeam.indexOf('<!--');
      for (var off = pb; off < pb + '<!-- pagebreak -->'.length; off++) {
        expect(await _barsAt(tester, buf, off), 1, reason: '偏移 $off');
      }
    });
  });
}
