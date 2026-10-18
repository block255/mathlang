// 数语引擎 · **行间公式段 / 行间模板**的守卫（2026-10-18）
//
// 用户拍板的两条口径（**别再重开**）：
//   ① **`cases` / `aligned` 走行间** —— 它们天生是"一段推导/一组分支"，
//      和空槽占位一样："删得只剩占位框我们也依然画出来，只是提醒用户要去填"。
//   ② **行内保持平权** —— **不接受"行内多项式当成一个整体"**：
//      行内公式必须**由内容产生**（面板符号自动建壳 / `/` 成式 / 词触发 / 粘贴包裹），
//      所以**没有**"先造一个空的行内壳再往里写"这条路（`Alt+=` 已撤）。
//
// 判据（全域，不是抽查）：
//   · 行间插入 ⇒ 文档里是 `$$\n<tex>\n$$`、`$` 成对、块模型认成 `BlockType.math`；
//   · **行内仍是主要地位** ⇒ 库里 `insertAs == display` 的项只能是"天生一段"的那几个
//     （`cases` / `aligned` / `行间公式`），其余**全部** inline；
//   · 光标在行内公式里请求行间 ⇒ **不许劈开 `$…$`**（新块落在公式外）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/block.dart';
import 'package:mathlang/lang/symbol_insert.dart';
import 'package:mathlang/lang/symbol_library.dart';

SymbolLibrary _realLibrary() =>
    SymbolLibrary.fromJson(File('assets/symbols.json').readAsStringSync());

/// 每行的 `$` 是否成对（`$$` 也被算作两个，所以"围栏独占一行"会被这条一起守住）
bool _balanced(String doc) {
  for (final String line in doc.split('\n')) {
    var n = 0;
    for (var i = 0; i < line.length; i++) {
      if (line[i] == '\\') {
        i++;
        continue;
      }
      if (line[i] == r'$') n++;
    }
    if (n.isOdd) return false;
  }
  return true;
}

void main() {
  group('① 符号库口径：行内是主要地位', () {
    test('★ `display` 只能是"天生一段"的那三项', () {
      final SymbolLibrary lib = _realLibrary();
      final List<String> display = <String>[
        for (final SymbolItem i in lib.items)
          if (i.isDisplay) i.id,
      ];
      expect(display.toSet(), <String>{'cases', 'aligned'},
          reason: '2026-10-18：`displaymath` 已从网格撤掉 —— 行间公式是**排版动作**，'
              '改由符号面板筛选行的文字按钮提供（用户拍板）');
    });

    test('★ 绝大多数项仍是 inline（display 占比 < 5%）', () {
      final SymbolLibrary lib = _realLibrary();
      final int n = lib.items.length;
      final int d = lib.items.where((SymbolItem i) => i.isDisplay).length;
      expect(n, greaterThan(50));
      expect(d, lessThan(n * 0.05), reason: '行内是主要地位（用户口径）');
    });

    test('「行间公式」**不再占网格**（2026-10-18 起是筛选行的文字按钮）', () {
      final SymbolLibrary lib = _realLibrary();
      final List<SymbolItem> items = lib.inCategory(group: '结构');
      expect(items.where((SymbolItem i) => i.id == 'displaymath'), isEmpty,
          reason: '行间公式是**排版动作**，不是符号；入口是面板筛选行右侧的按钮（Key: panel-insert-display）');
    });
  });

  group('② 行间插入：形态与块结构', () {
    test('★ 空的「行间公式」⇒ 三行围栏，光标落在围栏之间那一行', () {
      final SymbolInsertResult r = applySymbolInsert(
        doc: 'ab',
        caret: 1,
        selStart: 1,
        selEnd: 1,
        tex: '',
        template: true,
        display: true,
      );
      expect(r.doc.contains('\$\$\n\n\$\$'), isTrue, reason: r.doc);
      expect(_balanced(r.doc), isTrue);
      // 光标应在"$$\n"之后 = 空行的行首
      expect(r.caret, r.doc.indexOf(r'$$') + 3);
    });

    test('★ `cases` 行间插入 ⇒ 围栏独占行、块模型认成 math', () {
      final SymbolInsertResult r = applySymbolInsert(
        doc: '甲乙丙',
        caret: 3,
        selStart: 3,
        selEnd: 3,
        tex: r'\begin{cases}&\\&\end{cases}',
        template: true,
        display: true,
      );
      final List<String> lines = r.doc.split('\n');
      expect(lines.contains(r'$$'), isTrue, reason: r.doc);
      expect(_balanced(r.doc), isTrue, reason: r.doc);
      // 块模型必须认出这是公式块（不是"LaTeX 当正文"）
      final BlockIndex idx = BlockIndex.parse(r.doc);
      expect(idx.blocks.any((Block b) => b.type == BlockType.math), isTrue,
          reason: r.doc);
      // 光标必须**在围栏之内**（`cases` 没有 `{}` 空槽 ⇒ 落 tex 末尾，仍在块内）
      final int open = r.doc.indexOf('\$\$\n');
      final int close = r.doc.indexOf('\n\$\$', open);
      expect(close, greaterThan(open), reason: r.doc);
      expect(r.caret, inInclusiveRange(open + 3, close),
          reason: '光标要在公式块内部：${r.doc}');
    });

    test('★ `aligned` 同样走行间', () {
      final SymbolInsertResult r = applySymbolInsert(
        doc: '',
        caret: 0,
        selStart: 0,
        selEnd: 0,
        tex: r'\begin{aligned}&=\\&=\end{aligned}',
        template: true,
        display: true,
      );
      expect(r.doc.startsWith('\$\$\n'), isTrue, reason: r.doc);
      expect(r.doc.endsWith('\n\$\$'), isTrue, reason: r.doc);
    });

    test('★ 全域：每一条 display 项插到"每个可达位置"都不劈开美元符', () {
      final SymbolLibrary lib = _realLibrary();
      const List<String> docs = <String>[
        '',
        '段落甲。',
        '中间 \$x^2\$ 有公式。',
        '\$\$\nx=1\n\$\$',
        '# 标题\n\n正文',
        '- 列表项 \$a\$',
      ];
      for (final SymbolItem item in lib.items.where((SymbolItem i) => i.isDisplay)) {
        for (final String doc in docs) {
          for (var at = 0; at <= doc.length; at++) {
            final SymbolInsertResult r = applySymbolInsert(
              doc: doc,
              caret: at,
              selStart: at,
              selEnd: at,
              tex: item.tex,
              template: item.isTemplate,
              display: item.isDisplay,
            );
            expect(_balanced(r.doc), isTrue,
                reason: '${item.id} @ $at on "${doc.replaceAll('\n', r'\n')}"'
                    ' ⇒ "${r.doc.replaceAll('\n', r'\n')}"');
            expect(r.caret, inInclusiveRange(0, r.doc.length));
          }
        }
      }
    });

    test('★ 光标在**行内公式里**请求行间 ⇒ 新块落在公式外（不劈开定界符）', () {
      const String doc = r'甲 $\alpha$ 乙';
      // 光标在 `$…$` 内部（tex 里）
      final int inside = doc.indexOf(r'\alpha');
      final SymbolInsertResult r = applySymbolInsert(
        doc: doc,
        caret: inside,
        selStart: inside,
        selEnd: inside,
        tex: r'\begin{cases}&\\&\end{cases}',
        template: true,
        display: true,
      );
      expect(r.doc.contains(r'$\alpha$'), isTrue,
          reason: '原行内公式必须完好：${r.doc}');
      expect(_balanced(r.doc), isTrue, reason: r.doc);
      expect(r.mode, SymbolInsertMode.wrapNewInlineMath,
          reason: '行间不与行内混 ⇒ 走"新建壳"这条路');
    });
  });

  group('③ 行内不受影响（存量语义不漂）', () {
    test('同一个模板 display=false ⇒ 仍是行内壳', () {
      final SymbolInsertResult r = applySymbolInsert(
        doc: '甲乙丙',
        caret: 1,
        selStart: 1,
        selEnd: 1,
        tex: r'\begin{cases}&\\&\end{cases}',
        template: true,
      );
      expect(r.doc.contains(r'$\begin{cases}'), isTrue, reason: r.doc);
      expect(r.doc.contains('\$\$\n'), isFalse);
      expect(r.mode, SymbolInsertMode.wrapNewInlineMath);
    });
  });
}
