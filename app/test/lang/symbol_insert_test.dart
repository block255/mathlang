// 面板插入语义（S4-b）的守卫：**三种落法 + 模板光标进第一个空槽 + 一次编辑**。
//
// 用户 2026-10-17 确认、《界面与布局.md》§7：
//   ① 光标在数学段里（含紧邻）⇒ **并入**，不新建第二个 `$…$`；
//   ② 光标在纯文字里 ⇒ **自动建壳** `$…$`（"用户不写编码"）；
//   ③ 有选区 ⇒ **替换选区**（选区内已有数学段就不重复包）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/symbol_insert.dart';

void main() {
  group('② 在文字里点符号 ⇒ 自动建壳', () {
    test(r'中文中间插 `\alpha` ⇒ `$\alpha$`，光标在壳内末尾', () {
      const String doc = '前文后文';
      final SymbolInsertResult r = applySymbolInsert(
          doc: doc, caret: 2, selStart: 2, selEnd: 2, tex: r'\alpha', template: false);
      expect(r.mode, SymbolInsertMode.wrapNewInlineMath);
      expect(r.wrapped, isTrue);
      expect(r.doc, r'前文$\alpha$后文');
      expect(r.caret, 2 + r'$\alpha$'.length, reason: '符号 ⇒ 落在插入内容之后');
    });

    test('模板 ⇒ 光标进**第一个空槽**（分子）', () {
      final SymbolInsertResult r = applySymbolInsert(
          doc: 'ab', caret: 1, selStart: 1, selEnd: 1, tex: r'\frac{}{}', template: true);
      expect(r.doc, r'a$\frac{}{}$b');
      // `$\frac{}{}$` 里分子槽第一个位点的偏移 = 1（`$\` 之后）+ 6（`\frac{` 之后）
      expect(r.caret, 1 + 1 + firstSlotOffset(r'\frac{}{}'));
      expect(r.caret, greaterThan(1), reason: '必须落在壳内（不是壳外）');
      expect(r.doc.substring(r.caret - 1, r.caret), '{',
          reason: '光标应紧跟在分子的 `{` 之后');
    });
  });

  group('① 数学段里/紧邻 ⇒ 并入，不新建', () {
    test(r'`$x$` 之后点 `+` ⇒ `$x+$`（不是 `$x$+`）', () {
      const String doc = r'文字$x$尾巴';
      final int after = doc.indexOf(r'$', 3) + 1; // `$x$` 的之后那一格
      final SymbolInsertResult r = applySymbolInsert(
          doc: doc, caret: after, selStart: after, selEnd: after, tex: '+', template: false);
      expect(r.mode, SymbolInsertMode.mergeIntoMath, reason: '紧邻数学段 ⇒ 并入');
      expect(r.wrapped, isFalse);
      expect(r.doc, r'文字$x+$尾巴');
    });

    test(r'在公式**内部**点符号 ⇒ 就地插入（不改定界符）', () {
      const String doc = r'$x$';
      final SymbolInsertResult r = applySymbolInsert(
          doc: doc, caret: 2, selStart: 2, selEnd: 2, tex: r'\alpha', template: false);
      expect(r.mode, SymbolInsertMode.mergeIntoMath);
      expect(r.doc, r'$x\alpha$');
    });
  });

  group('③ 有选区 ⇒ 替换选区', () {
    test('文字选区被替换成"建壳的符号"', () {
      const String doc = '保留甲替换乙保留';
      final SymbolInsertResult r = applySymbolInsert(
          doc: doc, caret: 0, selStart: 3, selEnd: 6, tex: r'\pi', template: false);
      expect(r.mode, SymbolInsertMode.replaceSelection);
      expect(r.wrapped, isTrue);
      expect(r.doc, r'保留甲$\pi$保留');
    });

    test(r'选区**在公式里** ⇒ 只替换成 tex，不重复包', () {
      const String doc = r'$abc$';
      // 选中 `b`（在公式内）
      final SymbolInsertResult r = applySymbolInsert(
          doc: doc, caret: 0, selStart: 2, selEnd: 3, tex: r'\beta', template: false);
      expect(r.mode, SymbolInsertMode.replaceSelection);
      expect(r.wrapped, isFalse);
      expect(r.doc, r'$a\betac$', reason: '不该重复包壳（选区已在公式里）');
    });
  });

  group('★ 行边界规则照样生效（走 insert_guard，不绕过守门人）', () {
    test(r'在 `$$` 围栏行末尾插模板 ⇒ 不撑坏围栏（③④⑤ 生效）', () {
      const String src = '前文\n\n\$\$\nx=1\n\$\$\n\n后文';
      final int closingEnd = src.indexOf(r'$$', 6) + 2;
      final SymbolInsertResult r = applySymbolInsert(
        doc: src,
        caret: closingEnd,
        selStart: closingEnd,
        selEnd: closingEnd,
        tex: r'\frac{}{}',
        template: true,
      );
      // 不许出现 `$$$\frac…`（围栏被撑长）
      expect(r.doc.contains(r'$$\frac'), isFalse, reason: r.doc);
      expect(RegExp(r'^\$\$.+$', multiLine: true).hasMatch(r.doc), isFalse,
          reason: '围栏行必须仍然只有两个美元符号（实际文档见下）\n${r.doc}');
    });
  });
}
