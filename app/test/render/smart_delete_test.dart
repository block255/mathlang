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

  group('§4.0/§4.3 结构单元：在**它自己那一层**上被整体删', () {
    test(r'\frac{}{} 全空 → 9 个字符一次消失', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{}{}');
      final SmartEdit e = smartBackspace(t, 9); // tex 末尾 = 主行层
      expect(e.from, 0);
      expect(e.to, 9);
      expect(e.caret, 0);
    });

    // ★★ 2026-10-15 改口径（用户实测）：**主行层紧邻结构 ⇒ 整个结构一起走**。
    //    旧规格写的是"有内容 → 绝不拆结构，只删一个原子"—— 那正是用户报的那条：
    //    「点分式整体后面删 → 只删了分母里的 b，出现空位框，并不是像预期那样删除了整个 a/b」。
    test(r'\frac{a}{b} 在**分式整体之后**退格 → 整个分式走（含内容）', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{a}{b}');
      final SmartEdit e = smartBackspace(t, 11); // tex 末尾 = 主行层
      expect(e.from, 0, reason: '整段，从 `\\frac` 起');
      expect(e.to, 11);
      expect(e.caret, 0);
    });

    test(r'★ 反过来：光标在**分母里** `b` 之后退格 → 只删 `b`，分式还在', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{a}{b}');
      final SmartEdit e = smartBackspace(t, 10); // 分母槽内、b 之后
      expect(e.from, 9, reason: '层内删除只碰那一层');
      expect(e.to, 10);
    });

    test(r'\sqrt{} 全空 → 在结构层位点（tex 末尾）整段删', () {
      final CaretSiteTable t = buildCaretSites(r'\sqrt{}');
      final SmartEdit e = smartBackspace(t, 7);
      expect(e.from, 0);
      expect(e.to, 7);
    });

    // ★★ 空槽**不是**可删对象：里面退格只移动（2026-10-15 用户拍板）——
    //    这条同时是「删不掉根号」的正解：根号要从**结构层位点**删，
    //    而不是靠"空槽里连坐删结构"（那会把 `\frac{a}{}` 的分子一起带走）。
    test(r'★ 空槽里退格 = **只移动**，绝不连坐删掉结构', () {
      final CaretSiteTable t = buildCaretSites(r'\sqrt{}');
      final SmartEdit e = smartBackspace(t, 6); // 空槽里唯一的位点
      expect(e.isMove, isTrue, reason: '空槽里退格等同方向键');
      expect(e.caret, 0);
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

  // ─────────────────────────────────────────────────────────────
  // 文档级：空壳 / 公式首的边界语义（§3.3 + §4.6）
  // ─────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────
  // ★★ §4.0 通则的两个全域不变量（学"光标归属表"那套：全域断言，不逐例抽查）
  // ─────────────────────────────────────────────────────────────
  group('★★ 全域不变量：任何位点上删除都不留"悬空脚本"/不越层', () {
    const List<String> corpus = <String>[
      r'b^2',
      r'b^{2}',
      r'x_1^2',
      r'a_{i}',
      r'x^{2n}+1',
      r'\frac{a}{b}',
      r'\frac{x^2}{y_1}',
      r'\sqrt{b^2-4ac}',
      r'\sum_{i=1}^{n}a_i',
      r'\frac{\sqrt{x}}{y}',
    ];

    /// 悬空脚本 = `^`/`_` 后面直接是**结尾 / 运算符 / 右括号** ——
    /// 引擎会当场报 `Parser Error: Expected group after '^'`（用户实测抓过）。
    final RegExp dangling = RegExp(r'[\^_]\s*($|[-+*/=)])');

    test('每个位点 × 两个方向：`^`/`_` 之后必须仍有参数', () {
      for (final String tex in corpus) {
        final CaretSiteTable t = buildCaretSites(tex);
        for (final int rel in t.offsets) {
          for (final bool forward in <bool>[false, true]) {
            final SmartEdit e =
                forward ? smartDelete(t, rel) : smartBackspace(t, rel);
            if (!e.deletes) continue;
            final String after = tex.replaceRange(e.from!, e.to!, '');
            expect(dangling.hasMatch(after), isFalse,
                reason: '$tex 在 rel=$rel ${forward ? "Delete" : "Backspace"} '
                    '之后得到 `$after`（悬空脚本会让渲染当场炸）');
          }
        }
      }
    });

    test(r'透明包装（`\text{}`）里没有可见原子时，删的是包装自己 —— 不留"删不掉的陷阱"', () {
      final CaretSiteTable t = buildCaretSites(r'\text{}');
      final SmartEdit e = smartBackspace(t, 7);
      expect(e.from, 0);
      expect(e.to, 7);
    });

    test(r'透明包装里有内容时，删的是**内容里**的对象（裸组同理）', () {
      final CaretSiteTable t = buildCaretSites(r'\text{ab}');
      final SmartEdit e = smartBackspace(t, 9);
      expect(e.deletes, isTrue);
      expect(r'\text{ab}'.substring(e.from!, e.to!), 'b');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // ★★ §4.7：**算子 + 它的作用域 = 一个操作对象**（2026-10-15 新增）
  //    算子的内容边界由**数学的结合力**界定（规则与例子见 `scope_table_test.dart`；
  //    本组只验**删除侧的接线**）
  // ─────────────────────────────────────────────────────────────
  group('§4.7 算子 + 作用域 = 一个操作对象', () {
    void expectDeleted(String tex, int rel, String want,
        {bool forward = false}) {
      final CaretSiteTable t = buildCaretSites(tex);
      final SmartEdit e = forward ? smartDelete(t, rel) : smartBackspace(t, rel);
      expect(e.deletes, isTrue, reason: '「$tex」@$rel $e');
      expect(tex.substring(e.from!, e.to!), want);
    }

    test(r'`\sin 2x` 末尾退格 → 整个 `\sin 2x`', () {
      const String tex = r'\sin 2x';
      expectDeleted(tex, tex.length, tex);
    });

    test(r'`\sin 2x+y` 里 `2x` 之后退格 → `\sin 2x`（`+y` 不动）', () {
      expectDeleted(r'\sin 2x+y', 7, r'\sin 2x');
    });

    test(r'`\sum_{i=1}^{n}a_i b_i` 末尾退格 → 整个求和式（含上下限与内容）', () {
      const String tex = r'\sum_{i=1}^{n}a_i b_i';
      expectDeleted(tex, tex.length, tex);
    });

    test(r'`\sin x\cdot y` 里 `x` 之后退格 → `\sin x`（显式乘号断开）', () {
      expectDeleted(r'\sin x\cdot y', 6, r'\sin x');
    });

    test(r'`2\sin x` 末尾退格 → 只删 `\sin x`（`2` 不进来）', () {
      const String tex = r'2\sin x';
      expectDeleted(tex, tex.length, r'\sin x');
    });

    test(r'`Delete` 在操作对象左端 → 整个对象（对称的另一面）', () {
      expectDeleted(r'2\sin x', 1, r'\sin x', forward: true);
    });

    test(r'★ 无值算子：`\sin` 末尾退格 → 删算子自己（不算"整个作用域"）', () {
      const String tex = r'\sin';
      expectDeleted(tex, tex.length, tex);
    });
  });
}
