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
import 'package:mathlang/core/paragraph_break.dart';
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

/// 所有空行/接缝/文末槽的 (id, 矩形)，按屏幕从上到下排
///
/// `id` 是内部约定：`seam@p<n>` = 第 n 页的接缝槽；`blank@…` = 空行槽 / 文末槽。
/// 用 `dynamic` 读私有 widget 的公开字段（测试里读 id 比按几何猜稳）。
List<(String, Rect)> _slots(WidgetTester tester) {
  final List<(String, Rect)> out = <(String, Rect)>[];
  final Finder f = find.byWidgetPredicate(
      (Widget w) => w.runtimeType.toString() == '_BlankSlot');
  for (final Element e in f.evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize) continue;
    final String id = (e.widget as dynamic).id as String;
    out.add((id, ro.localToGlobal(Offset.zero) & ro.size));
  }
  out.sort(((String, Rect) a, (String, Rect) b) => a.$2.top.compareTo(b.$2.top));
  return out;
}

List<Rect> _slotRects(WidgetTester tester) =>
    <Rect>[for (final (String, Rect) s in _slots(tester)) s.$2];

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
      // ★ 批 47：落点回到**分页符行首**（= 那片空白对应的真实位置）；
      //   "打字跑到下一页"由插入侧规则⑥ 的行首例外解决，不再靠挪落点。
      expect(buf.caret, kSeam.indexOf('<!--'),
          reason: '应当落在分页符行首；实际落在 ${buf.caret}');
    });

    testWidgets('★ 点末页那片白 ⇒ 落**最下面那一行**（= 文末下一行），文档一个字都不变',
        (WidgetTester tester) async {
      // 用户 2026-10-27：「点击下部空白让光标落到文末下一个空行，符合直觉和操作习惯，
      //   但没必要和改文档冲突」⇒ **点击不改文档**（这条不变）。
      // ★★ 2026-10-28 用户纠正：文末下一行是**常驻行**（基准 4）⇒ 它本身就是一条空行、
      //   而且是最下面那一条 ⇒ 点白就落它（`buf.length`）。三级在这里合并成一条。
      final DocBuffer buf = await _mount(tester, '甲\n\n乙\n');
      final String before = buf.buf;
      final List<Rect> slots = _slotRects(tester);
      expect(slots, isNotEmpty);
      await tester.tapAt(slots.last.center);
      await tester.pumpAndSettle();
      expect(buf.buf, before, reason: '点击只移光标，不许改文档（改前会补一行空行）');
      expect(buf.caret, buf.buf.length, reason: '落最下面那一行（= 文末下一行）');
    });

    testWidgets('★ 分页符行内每格**只有一根**光标条（不许页尾槽与单元叠两根）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _mount(tester, kSeam);
      final int pb = kSeam.indexOf('<!--');
      for (var off = pb; off < pb + '<!-- pagebreak -->'.length; off++) {
        expect(await _barsAt(tester, buf, off), 1, reason: '偏移 $off');
      }
    });

    // ★★ 2026-10-26 用户手测追加（批 39）：页尾那几行**真空行**也要看得见光标。
    //   用户原话：「第一页的下部空白有点击判定但是点击光标只会落到文末的 c 后面，
    //   我在 c 后面按 enter，光标会消失（实际上是到空行了但是不显示）」。
    //   根因：接缝槽上一版只在"越过上一单元"时才画 ⇒ 自然分页时 `tapAt == acceptTo`
    //   ⇒ 页尾那几行空行整段死；而它们是**真实文档位置**，必须有人认领。
    testWidgets('★ 页尾的空行（分页符之前那几行）也要看得见光标', (WidgetTester tester) async {
      const String doc = '甲\n\n乙\n\n\n\n\n<!-- pagebreak -->\n丙\n';
      final DocBuffer buf = await _mount(tester, doc);
      final int firstBlank = doc.indexOf('乙') + 2;
      expect(doc[firstBlank], '\n', reason: '前置：这一格确实是乙下面的第一个空行');
      // ★ 2026-10-28（用户拍板"段间距不承接字符"）：`firstBlank` 就是**段落分隔符**
      //   （零高度、不是位置）⇒ 它不再画光标；真行从下一个起。
      expect(isParagraphSeparator(doc, firstBlank), isTrue,
          reason: '前置：乙下面第一个空行是段落分隔符');
      for (var off = firstBlank + 1; off <= firstBlank + 3; off++) {
        expect(await _barsAt(tester, buf, off), greaterThan(0),
            reason: '页尾空行偏移 $off 没有光标条（用户："光标会消失"）');
      }
    });

    // ★★ 2026-10-26 用户手测追加（批 38 的回归）：点中间页下部空白会**两根竖条**
    //   —— 一根在"这一页最后一行末尾"（那是接缝槽的落点，由单元自己画），
    //   另一根在下面那片空白的顶上（接缝槽又画了一根）。同一格像素两个主人。
    testWidgets('★ 点中间页下部空白 ⇒ **不许比落点那格多画一根**（自然分页那种页）',
        (WidgetTester tester) async {
      // 造一份"自然溢出"的文档（分页符造出来的页不会踩这个坑：那种页的最后一行后面
      // 紧跟分页符，落点 > acceptTo）
      final String doc =
          '${List<String>.filled(60, '一行文字').join('\n\n')}\n\n---\n\n尾段\n';
      final DocBuffer buf = await _mount(tester, doc);
      final (String, Rect)? seam = _slots(tester)
          .where(((String, Rect) s) => s.$1 == 'seam@p0')
          .cast<(String, Rect)?>()
          .firstOrNull;
      expect(seam, isNotNull, reason: '第 1 页要有接缝槽（id=seam@p0）');
      await tester.tapAt(seam!.$2.center);
      await tester.pumpAndSettle();
      final int afterClick = _bars(tester);
      final int caret = buf.caret;
      // ★ 判据：**点页面白不许额外多画一根** —— 落点那格本来有几根（单元 / 块边界条 /
      //   空行槽），点完还应该只有那几根。改前这里是 3（多出的那根来自接缝槽）。
      buf.setCaret(0);
      await tester.pump();
      await tester.pump();
      buf.setCaret(caret);
      await tester.pump();
      await tester.pump();
      final int direct = _bars(tester);
      expect(afterClick, direct,
          reason: '点页面白 ⇒ $afterClick 根，直接落到同一格 ⇒ $direct 根'
              '（caret=$caret；改前会多画一根）');
    });
  });
}
