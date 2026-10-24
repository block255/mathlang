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
  // ③ §4.0' 挂件的边缘像素：**删除按可见墨迹走；会把挂件掏空 ⇒ 整个挂件走**
  //
  //    挂件 = 脚本（`^`/`_`）＋ 定宽 accent（`\hat` 一族）。判据只有一条，
  //    所以**不带"单字符/多字符"这种会随内容变的门槛**（内容变长，行为自然从"整个走"变成"逐字删"）。
  //    ★ 位点一个都不删 ⇒ 永远能点进挂件里打字（包括**下标的下标** `x_{a_i}`）。
  // ─────────────────────────────────────────────────────────────
  group('③ §4.0\' 挂件边缘：按墨迹走 + 不留半成品', () {
    group('定宽 accent（套在基座上 ⇒ 掏空会剩一顶悬空的帽子 ⇒ 整个走）', () {
      test(r'`\hat{x}` 右端两格（内容末尾 6 / 结构末尾 7）退格 ⇒ **整个** `\hat{x}`', () {
        final CaretSiteTable t = buildCaretSites(r'\hat{x}');
        for (final int rel in <int>[6, 7]) {
          final SmartEdit e = smartBackspace(t, rel);
          expect(e.from, 0, reason: 'rel=$rel');
          expect(e.to, 7, reason: 'rel=$rel：整个结构（含命令与收尾 `}`）');
        }
      });

      test(r'`\hat{x}` 左端两格（结构首 0 / 内容首 5）按 `Delete` ⇒ 整个 `\hat{x}`', () {
        final CaretSiteTable t = buildCaretSites(r'\hat{x}');
        for (final int rel in <int>[0, 5]) {
          final SmartEdit e = smartDelete(t, rel);
          expect(e.from, 0, reason: 'rel=$rel');
          expect(e.to, 7, reason: 'rel=$rel：里面只剩一个原子 ⇒ 删它会掏空 ⇒ 整个走');
        }
      });

      test(r'★ 左端**退格**删的是"挂件外面左边"那一个对象（左邻墨迹）', () {
        const String tex = r'a\hat{x}';
        final CaretSiteTable t = buildCaretSites(tex);
        final SmartEdit e = smartBackspace(t, 6); // 内容首（`{` 之后）
        expect(e.from, 0);
        expect(e.to, 1, reason: '删的是 `a` —— 与"从挂件外面退格"同一结果');
      });

      test(r'`Delete` 在右端两格 ⇒ 删**右边**那一个对象（`\hat{x}+1` 删 `+`）', () {
        final CaretSiteTable t = buildCaretSites(r'\hat{x}+1');
        for (final int rel in <int>[6, 7]) {
          final SmartEdit e = smartDelete(t, rel);
          expect(e.from, 7, reason: 'rel=$rel');
          expect(e.to, 8);
        }
      });

      test(r'★ 内容 ≥2 个原子时**逐字删**：`\hat{ab}` 右端退格只删 `b`（留 `\hat{a}`）', () {
        final CaretSiteTable t = buildCaretSites(r'\hat{ab}');
        final SmartEdit e = smartBackspace(t, 7); // 内容末尾（b 之后）
        expect(e.from, 6);
        expect(e.to, 7, reason: '删 `b` 不会掏空（还剩 `a`）⇒ 按墨迹走');
      });

      test(r'`\bar{y}` / 裸参数 `\hat x` 都对', () {
        expect(smartBackspace(buildCaretSites(r'\bar{y}'), 6).to, 7);
        // 裸参数：内容末尾 == 结构末尾 == tex 末尾（没有 `}` 可越）
        final SmartEdit bare = smartBackspace(buildCaretSites(r'\hat x'), 6);
        expect(bare.from, 0);
        expect(bare.to, 6);
      });

      test(r'★ **拉伸型** accent 不受影响：`\overline{AB}` 内容末尾退格只删 `B`', () {
        final CaretSiteTable t = buildCaretSites(r'\overline{AB}');
        final SmartEdit e = smartBackspace(t, 12); // 内容末尾（B 之后）
        expect(e.from, 11);
        expect(e.to, 12, reason: '拉伸型的两个位点**是分开的**（尾垫撑开了）⇒ 各管各的');
      });

      test(r'嵌套 `\hat{\bar{x}}`：三层是**同一根像素** ⇒ 取最外那一层', () {
        final CaretSiteTable t = buildCaretSites(r'\hat{\bar{x}}');
        final SmartEdit innerEnd = smartBackspace(t, 11); // 内层内容末尾
        final SmartEdit outside = smartBackspace(t, 13); // 公式内最外层末尾
        expect(innerEnd.from, outside.from);
        expect(innerEnd.to, outside.to);
        expect(innerEnd.from, 0);
        expect(innerEnd.to, 13, reason: '整个 `\\hat{\\bar{x}}`');
      });

      test(r'空的 `\hat{}`：两个方向都整个走（本来就空）', () {
        final CaretSiteTable t = buildCaretSites(r'\hat{}');
        for (final SmartEdit e in <SmartEdit>[
          smartBackspace(t, 5),
          smartDelete(t, 5),
        ]) {
          expect(e.from, 0);
          expect(e.to, 6, reason: '整个 `\\hat{}`');
        }
      });
    });

    group('脚本（挂在基座**旁边** ⇒ 掏空只剩基座 ⇒ 只删挂件）', () {
      test(r'`x_2` 右端退格 ⇒ 删掉挂件本身（`_2`），**基座留下**（用户选的「甲」）', () {
        final CaretSiteTable t = buildCaretSites(r'x_2');
        final SmartEdit e = smartBackspace(t, 3);
        expect(e.from, 1);
        expect(e.to, 3, reason: '`_2` 一起走（不能留悬空的 `_`）⇒ 剩 `x`');
      });

      // ★★ 2026-10-24（批 11）**这条分成了两格，理由**：用户实测「`\sum…i^{2}` 末尾退格，
      //   不是删 i 平方，只删了指数 2」—— 花括号形式下"内容末（`}` 之前）"与"对象之后"
      //   不是同一根像素（差 1px、层级也不同，与批 6/7 同一判据）⇒ 两者结果要分开。
      test(r'花括号 `x_{2}` **内容末**退格 ⇒ 只删内容 `2`（留合法的空组 `x_{}`，§4.1.1）', () {
        final CaretSiteTable t = buildCaretSites(r'x_{2}');
        final SmartEdit e = smartBackspace(t, 4); // 内容末尾（`}` 之前）
        expect(e.from, 3);
        expect(e.to, 4, reason: '在**指数/下标里面**删内容，§4.1.1 口径不变');
      });

      test(r'★ 花括号 `x_{2}` **对象之后**退格 ⇒ 整个 `x_{2}`（乙口径：字形 + 挂件 = 一个对象）', () {
        final CaretSiteTable t = buildCaretSites(r'x_{2}');
        final SmartEdit e = smartBackspace(t, 5); // 挂件末尾（`}` 之后 = 对象层）
        expect(e.from, 0);
        expect(e.to, 5, reason: '改前只删 `2`、留 `x_{}`；用户要的是"删掉整个 i 平方"');
      });

      test(r'`x_{2}` 在"内容首"（`2` 之前）按 `Delete` ⇒ 只删 `2`，留 `x_{}`', () {
        final CaretSiteTable t = buildCaretSites(r'x_{2}');
        final SmartEdit e = smartDelete(t, 3);
        expect(e.from, 3);
        expect(e.to, 4,
            reason: '花括号形式**不必**连 `_` 一起删（`{}` 是合法空组，§4.1.1）'
                '—— 这样还能就地重打一个新的下标');
      });

      test(r'★ 内容 ≥2 个原子时逐字删：`x_{23}` 右端退格只删 `3`', () {
        final CaretSiteTable t = buildCaretSites(r'x_{23}');
        final SmartEdit e = smartBackspace(t, 5); // 内容末尾
        expect(e.from, 4);
        expect(e.to, 5, reason: '左边最近的墨迹是 `3`');
      });

      test(r'★ 挂件**内部**逐字：`x_{2|3}` 退格删 `2`、`Delete` 删 `3`', () {
        final CaretSiteTable t = buildCaretSites(r'x_{23}');
        expect(smartBackspace(t, 4).from, 3);
        expect(smartDelete(t, 4).from, 4);
      });

      test(r'★ 基座与挂件之间（`x|_2`）退格 ⇒ 整个 `x_2`（连基座一起，绑定）', () {
        final CaretSiteTable t = buildCaretSites(r'x_2');
        final SmartEdit e = smartBackspace(t, 1);
        expect(e.from, 0);
        expect(e.to, 3, reason: '删基座必须连它的脚本一起走（否则留悬空 `_`）');
      });

      test(r'★ `x_{a_i}`（下标的下标）里，内容末尾退格删的是**内层** `i` 的挂件', () {
        // tex = x_{a_i}：0=x 1=_ 2={ 3=a 4=_ 5=i 6=}
        final CaretSiteTable t = buildCaretSites(r'x_{a_i}');
        final SmartEdit e = smartBackspace(t, 6); // 内层 `i` 之后
        expect(e.from, 4);
        expect(e.to, 6, reason: '删内层挂件 `_i` ⇒ 剩 `x_{a}` —— 编辑路径没有被封死');
      });
    });
  });
}
