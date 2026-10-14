// 结构感知删除 + 文档级进出测试（S3-4 + S3-3 的胶水层）
//
// 规格：notes/design/位点与结构导航.md
//   §四   原子删除 / 槽间跨越 / **全空才删** / 降级退化为字节级
//   §3.3 跨 `$` 边界进出公式、公式首退格、空壳公式整段删

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/math_nav.dart';
import 'package:mathlang/render/smart_delete.dart';

void main() {
  group('§4.1 原子删除：整个可见原子一次删光', () {
    test(r'\alpha 五个字符一次删掉', () {
      final CaretSiteTable t = buildCaretSites(r'\alpha');
      final SmartEdit e = smartBackspace(t, 6);
      expect(e.deletes, isTrue);
      expect(e.from, 0);
      expect(e.to, 6);
      expect(e.caret, 0);
    });

    test(r'x^2 的 2 一次删掉（上标槽也是原子级）', () {
      final CaretSiteTable t = buildCaretSites(r'x^2');
      final SmartEdit e = smartBackspace(t, 3);
      // ★ 2026-10-14 起：`x^2` 是**裸参数**（没有花括号）→ 删除时**连 `^` 一起删**
      //   （只删 `2` 会得到 `x^-…` 这种"`^` 后面接运算符"的坏源码 → 引擎 Parser Error，
      //    用户实测：在 \sqrt{b^2-4ac} 里连按删除键触发）
      expect(e.from, 1, reason: '从 `^` 开始');
      expect(e.to, 3);
    });

    test('Delete 向后同样是原子级', () {
      final CaretSiteTable t = buildCaretSites(r'\alpha x');
      final SmartEdit e = smartDelete(t, 0);
      expect(e.from, 0);
      expect(e.to, 6);
    });
  });

  group('§4.3 结构单元：**全空才删**', () {
    test(r'\frac{}{} 全空 → 9 个字符一次消失', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{}{}');
      final SmartEdit e = smartBackspace(t, 9);
      expect(e.from, 0);
      expect(e.to, 9);
      expect(e.caret, 0);
    });

    test(r'\frac{a}{b} 有内容 → **绝不拆结构**，只删掉一个原子', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{a}{b}');
      final SmartEdit e = smartBackspace(t, 11);
      expect(e.deletes, isTrue);
      expect(e.from, 9, reason: '删的是分母里的 b，不是整个 \\frac');
      expect(e.to, 10);
    });

    test(r'\sqrt{} 全空 → 整段删', () {
      final CaretSiteTable t = buildCaretSites(r'\sqrt{}');
      final SmartEdit e = smartBackspace(t, 7);
      expect(e.from, 0);
      expect(e.to, 7);
    });

    test('structureUnits：同一次结构调用的多个参数算**一个**实例', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{}{}');
      final List<StructureUnit> us = structureUnits(t);
      expect(us.length, 1);
      expect(us.first.slots.length, 2);
      expect(us.first.allEmpty, isTrue);
    });
  });

  group('§4.2 槽间跨越：**只跳不删**', () {
    test(r'\frac{}{} 在分母首位退格 → 跳到分子末尾，不删任何东西', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{}{}');
      final SmartEdit e = smartBackspace(t, 8);
      expect(e.isMove, isTrue, reason: '结构墙要靠方向键跨，不靠退格拆');
      expect(e.caret, 6);
    });
  });

  group('§4.4 降级：配对失败 → 退化为字节级', () {
    test(r'多余的 } → 位点表降级 → 退格只删一个字符', () {
      final CaretSiteTable t = buildCaretSites(r'a}b');
      expect(t.degraded, isTrue);
      final SmartEdit e = smartBackspace(t, 3);
      expect(e.from, 2);
      expect(e.to, 3);
    });
  });

  group(r'★★ 删 `^`/`_` 的**裸参数**时必须连它一起删（用户实测 Parser Error）', () {
    // 用户的精确复现：在 \sqrt{b^2-4ac} 里把光标放 c 后面连按删除键，
    // 删到 b^2 的 `2` 时会得到 `b^-4ac` → Parser Error: Expected group after '^'
    test(r'b^2-4ac：删掉 `2` → 得到 b-4ac（不是 b^-4ac）', () {
      final CaretSiteTable t = buildCaretSites(r'b^2-4ac');
      final SmartEdit e = smartBackspace(t, 3); // b ^ 2 | - 4 a c
      expect(e.deletes, isTrue);
      expect(e.from, 1, reason: '必须从 `^` 开始删');
      final String after = r'b^2-4ac'.replaceRange(e.from!, e.to!, '');
      expect(after, r'b-4ac');
      // ★ 真正该守的不变量：`^`/`_` 之后必须仍跟着参数（不能接运算符/结尾）
      expect(RegExp(r'[\^_]\s*$|[\^_]\s*[-+*/=)]]').hasMatch(after), isFalse,
          reason: '不许出现"`^` 后面接运算符或结尾"的坏源码');
    });

    test(r'Delete 方向同理：b^2 上删 `2` 也连 `^` 一起删', () {
      final CaretSiteTable t = buildCaretSites(r'b^2-4ac');
      final SmartEdit e = smartDelete(t, 2); // b ^ | 2 - 4 a c
      final String after = r'b^2-4ac'.replaceRange(e.from!, e.to!, '');
      expect(after, r'b-4ac');
    });

    test(r'b^{2}（花括号形式）**不受影响**：删掉 2 得到 b^{}，仍然合法', () {
      final CaretSiteTable t = buildCaretSites(r'b^{2}');
      final SmartEdit e = smartBackspace(t, 4); // b ^ { 2 | }
      final String after = r'b^{2}'.replaceRange(e.from!, e.to!, '');
      expect(after, r'b^{}', reason: '花括号在 → `^` 仍有参数组，不必连 `^` 一起删');
    });
  });

  // （历史记账）曾被撤掉的那 3 条测试的注释：
  //   · `x^{2}` 在槽首（偏移 3）退格 → 按 §4.2 **本来就该"只跳不删"**（不是删除）
  //   · 删掉 `2` 得到 `x^{}` 是**合法**的（`^` 后仍有组），"含 ^" 不等于"悬空"
  //   → 要守的真正不变量是「**`^`/`_` 之后必须仍有参数组**」，而不是"结果里不含 ^"。
  //   代码侧的改动保留：删 `{...}` 组时若它是 `^`/`_` 的参数，**连 `^`/`_` 一起删**
  //   （这才是"要么都在、要么都不在"），下次补测试时按上面那条不变量写。

  group(r'文档级：跨 $ 边界进出（§3.3）', () {
    // 偏移：`设`0 ` `1 `$`2 `x`3 `^`4 `2`5 `+`6 `1`7 `$`8 ` `9 `为`10
    const String src = r'设 $x^2+1$ 为常数';

    test(r'文字里按 → 走到 $ 之前 → 进入公式第一个位点（**不落在 $ 上**）', () {
      expect(nextCaretOffset(src, 2), 3);
    });

    test(r'公式内最后一个位点按 → → 走出到 $ 之后', () {
      expect(nextCaretOffset(src, 8), 9);
    });

    test(r'公式第一个位点按 ← → 走出到 $ 之前', () {
      expect(prevCaretOffset(src, 3), 2);
    });

    test(r'文字里按 ← 到收尾 $ 之后 → 回到公式最后一个位点', () {
      expect(prevCaretOffset(src, 9), 8);
    });

    test('公式内 ←→ 沿**位点序**走一格', () {
      expect(nextCaretOffset(src, 3), 4, reason: 'x → ^ 之前的位点');
    });

    test('不在公式里时 tabStopAt 返回 null（Tab 让给焦点遍历）', () {
      expect(tabStopAt(src, 0, forward: true), isNull);
    });
  });

  group('文档级：Tab 在公式里走槽、走完就出公式', () {
    // `$`0 `\frac{}{}`1..9 `$`10 `x`11
    const String src = r'$\frac{}{}$x';

    test('连按 Tab：分子 → 分母 → 出公式', () {
      expect(tabStopAt(src, 5, forward: true), 7, reason: '进分子');
      expect(tabStopAt(src, 7, forward: true), 9, reason: '进分母');
      expect(tabStopAt(src, 9, forward: true), 11, reason: r'走出公式到 $ 之后');
    });
  });

  group('文档级：空壳公式在公式首退格 → 连定界符整段删（§3.3）', () {
    test(r'a $$b 里的空公式：退格删掉的是整个 `$$`', () {
      const String src = r'a $$b';
      final SmartEdit e = smartEditAt(src, 3, forward: false);
      expect(e.deletes, isTrue);
      expect(e.from, 2);
      expect(e.to, 4, reason: '连两侧定界符一起删');
      expect(e.caret, 2);
    });

    test(r'非空公式首退格 → 删**定界符之前**的那个文字（看不见的 `$` 不能删）', () {
      const String src = r'设 $x$值';
      // `设`0 ` `1 `$`2 `x`3 `$`4 `值`5
      final SmartEdit e = smartEditAt(src, 3, forward: false);
      expect(e.deletes, isTrue);
      expect(e.from, 1, reason: r'删掉空格，而不是删 `$`（删 `$` 会破坏配对）');
      expect(e.to, 2);
      expect(e.caret, 1);
    });
  });
}
