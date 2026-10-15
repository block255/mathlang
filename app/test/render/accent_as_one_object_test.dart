// ★★ 两条「用户实测抓出来」的回归（2026-10-15 晚第二轮）：
//
//  ① **空壳公式落在行首** ⇒ 整行被当成行间公式块 ⇒ `Parser Error: Can't use function '$'`
//     （用户实测：在 `$\overline{AB}$` 的**末端位**按删除键 ⇒ 整个 accent 走、留下 `$$`，
//       而那一行后面还跟着 `$\hat{x}$ $\bar{y}$` ⇒ 整行当 tex ⇒ `$` 落进数学模式）
//     精确复现：`kEditSample + '$\overline{AB}$ $\hat{x}$ $\bar{y}$'` 上
//       `Delete @201..207`（7 个偏移）· `Backspace @215/@216`（2 个）—— 共 9 个。
//  ② **形状固定的 accent**（`\hat` `\bar` …）当**一个字符**：内容末尾 == 结构末尾（同一根像素）
//     ⇒ 那里退格删**整个** `\hat{x}`（而不是留下 `\hat{}`），与"从外面删"同一结果。
//     （用户实测：「点底下和点整体的判定很难分清」）

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/block.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/math_nav.dart';
import 'package:mathlang/render/smart_delete.dart';
import 'package:mathlang/spike/s3_edit/s3_edit_page.dart';

const String kInserted = r'$\overline{AB}$ $\hat{x}$ $\bar{y}$';

Future<EditViewState> _mountEdit(WidgetTester tester, DocBuffer buf) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  final EditViewState st = tester.state<EditViewState>(find.byType(EditView));
  st.focusInput();
  await tester.pump();
  return st;
}

void main() {
  // ─────────────────────────────────────────────────────────────
  // 一、① 空壳落在行首：块模型不许把整行判成行间公式
  // ─────────────────────────────────────────────────────────────
  group(r'① 行首 `$$`（空壳公式）不许把整行变成"行间公式块"', () {
    test(r'`$$ $\hat{x}$` 是**段落**，不是 math 块', () {
      final BlockIndex idx = BlockIndex.parse(r'$$ $\hat{x}$ $\bar{y}$');
      expect(idx.blocks.single.type, isNot(BlockType.math),
          reason: '空壳 + 后面还有别的行内公式 ⇒ 只是普通段落');
    });

    test(r'真正的行间公式**照旧**：整行 `$$` 与同行闭合 `$$x$$`', () {
      expect(BlockIndex.parse('\$\$\nx\n\$\$').blocks.single.type, BlockType.math);
      expect(BlockIndex.parse(r'$$x=1$$').blocks.single.type, BlockType.math);
      // 行首有空格也算
      expect(BlockIndex.parse(r'  $$x=1$$').blocks.single.type, BlockType.math);
    });

    test(r'★ 空壳那一段按**行内空公式**走：tex 为空、且不吞掉后面的行内公式', () {
      const String doc = r'$$ $\hat{x}$';
      final MathRegion? r = mathRegionAt(doc, 1);
      expect(r, isNotNull, reason: r'`$$` 的第一个 `$` 之后应当是公式内容起点');
      expect(r!.tex, isEmpty);
      expect(r.closeEnd, 2);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 二、① 端到端：**全域扫偏移**，删一次之后页面里不许出现 Parser Error
  //     （这就是用户那条路径的最小不变量版本）
  // ─────────────────────────────────────────────────────────────
  group('① 端到端：任何偏移上删一次，都不许把公式渲染搞炸', () {
    testWidgets('样本 + accent 那一行 × 两个方向', (WidgetTester tester) async {
      final String doc = kEditSample + kInserted;
      final List<String> bad = <String>[];
      for (final bool forward in <bool>[true, false]) {
        for (var o = 0; o <= doc.length; o++) {
          final DocBuffer buf = DocBuffer(doc);
          await _mountEdit(tester, buf);
          buf.setCaret(o);
          await tester.pump();
          tester.takeException();

          await tester.sendKeyEvent(
              forward ? LogicalKeyboardKey.delete : LogicalKeyboardKey.backspace);
          await tester.pump();

          final bool errText =
              find.textContaining('Parser Error').evaluate().isNotEmpty;
          if (errText) {
            bad.add('${forward ? 'Delete' : 'Backspace'} @$o');
          }
        }
      }
      expect(bad, isEmpty,
          reason: '这些偏移删一次之后页面上出现 `Parser Error`：$bad');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 三、② 形状固定的 accent = **一个字符**（内容末尾 == 结构末尾）
  // ─────────────────────────────────────────────────────────────
  group('② 定宽 accent（`\\hat` `\\bar` `\\dot` …）：内容末尾与结构末尾同一结果', () {
    /// 段内相对偏移：`$\hat{x}$` 的 tex = `\hat{x}`，内容末尾 = 6、结构末尾 = 7
    test(r'`\hat{x}` 内容末尾退格 ⇒ **整个** `\hat{x}`（不是留 `\hat{}`）', () {
      final CaretSiteTable t = buildCaretSites(r'\hat{x}');
      final SmartEdit e = smartBackspace(t, 6);
      expect(e.deletes, isTrue);
      expect(e.from, 0);
      expect(e.to, 7, reason: '整个结构（含命令与收尾 `}`）');
    });

    test(r'`\hat{x}` 结构末尾退格 ⇒ 同一个结果（同一根像素必须同一行为）', () {
      final CaretSiteTable t = buildCaretSites(r'\hat{x}');
      final SmartEdit inner = smartBackspace(t, 6);
      final SmartEdit outer = smartBackspace(t, 7);
      expect(inner.from, outer.from);
      expect(inner.to, outer.to);
    });

    test(r'`Delete` 同理：内容末尾 ⇒ 删**右边那一个同层对象**（`\hat{x}+1` 删 `+`）', () {
      final CaretSiteTable t = buildCaretSites(r'\hat{x}+1');
      final SmartEdit e = smartDelete(t, 6); // 内容末尾
      expect(e.deletes, isTrue);
      expect(e.from, 7);
      expect(e.to, 8, reason: '越过整个 accent 之后，删的是 `+`');
    });

    test(r'★ 花括号形式与裸参数形式都对：`\bar{y}` / `\hat x`', () {
      expect(smartBackspace(buildCaretSites(r'\bar{y}'), 6).to, 7);
      // 裸参数：`\hat x` 的内容末尾 == 结构末尾 == tex 末尾（没有 `}` 可越）
      expect(smartBackspace(buildCaretSites(r'\hat x'), 6).to, 6);
      expect(smartBackspace(buildCaretSites(r'\hat x'), 6).from, 0);
    });

    test('★ **拉伸型** accent 不受影响：`\\overline{AB}` 内容末尾退格只删 `B`', () {
      final CaretSiteTable t = buildCaretSites(r'\overline{AB}');
      final SmartEdit e = smartBackspace(t, 12); // 内容末尾（B 之后）
      expect(e.from, 11);
      expect(e.to, 12, reason: '拉伸型的两个位点**是分开的**（尾垫撑开了）⇒ 各管各的');
    });

    test('★ 左端**故意不合并**：`\\hat{x}` 内容首位点按 `Delete` 仍只删里面的 `x`', () {
      final CaretSiteTable t = buildCaretSites(r'\hat{x}');
      final SmartEdit e = smartDelete(t, 5); // 内容首（`{` 之后）
      expect(e.from, 5);
      expect(e.to, 6, reason: '这是"点进去改字"的入口，必须留着');
    });

    test(r'嵌套 `\hat{\bar{x}}`：三层其实是**同一根像素** ⇒ 一路重映射到最外', () {
      final CaretSiteTable t = buildCaretSites(r'\hat{\bar{x}}');
      // 内层 `\bar` 内容末尾 = 11；内层结构末尾 12；外层（`\hat`）结构末尾 13
      // —— 装饰都不占宽、`{`/`}` 不可见 ⇒ 三者的**像素完全相同**
      // ⇒ 按「同一根像素 ⇒ 同一行为」，退格应当得到**最外那一层**的结果（整个走）
      final SmartEdit innerEnd = smartBackspace(t, 11);
      final SmartEdit outside = smartBackspace(t, 13); // 公式内最外层末尾
      expect(innerEnd.from, outside.from);
      expect(innerEnd.to, outside.to);
      expect(innerEnd.from, 0);
      expect(innerEnd.to, 13, reason: '整个 `\\hat{\\bar{x}}`');
    });
  });
}
