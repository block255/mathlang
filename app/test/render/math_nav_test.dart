// 数学段导航的文档级测试（2026-10-15）
//
// 本次新增的是「甲」方案：**`→` 跳过"数学段内的末尾位点"，`←` 不跳**（有意不对称）。
//
// 为什么要有这条不对称（用户实测 + 探针）：
//   `tex.length` 那个位点（= 闭合 `$` 所在那一格）与 `closeEnd`（公式之后）
//   **在屏幕上是同一根像素** —— 收尾 `$` 不可见。于是：
//     · 用户按 `→` 会以为"没反应"（其实挪了，看不出来）
//     · 在它上面断块会把公式劈开（`$` 配成单数 → 整行退化成源码）
//   ⇒ `→`（"出去"）= 一步出公式；`←`（"进去"）= 停在公式末尾继续改这段数学。
//
// 依据：notes/design/位点与结构导航.md §3.3 + 2026-10-15 的「甲」决定。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/math_nav.dart';

/// `文字。$\frac{a}{b}$尾`
///   文0 字1 。2 $3 \4 f5 r6 a7 c8 {9 a10 }11 {12 b13 }14 $15 尾16
const String kDoc = r'文字。$\frac{a}{b}$尾';

final int kTexStart = kDoc.indexOf(r'\frac'); // 4
final int kAfterB = kDoc.indexOf('b}') + 1; // 14（分母内容末尾）
final int kContentEnd = kDoc.indexOf('b}') + 2; // 15（闭合 `$` 那一格 = tex 末尾）
final int kCloseEnd = kContentEnd + 1; // 16（公式之后）
final int kOpenDollar = kTexStart - 1; // 3

void main() {
  group('★ `→`：不停在看不见的边界上', () {
    test('从分母末尾出发 → **一步出公式**（不是先停在 15）', () {
      expect(nextCaretOffset(kDoc, kAfterB), kCloseEnd,
          reason: '★ 原先会先停在 $kContentEnd（与 $kCloseEnd 同像素）→ 用户以为"没反应"，'
              '在那里按 Enter 还会把公式劈开');
      expect(nextCaretOffset(kDoc, kAfterB), isNot(kContentEnd));
    });

    test('就算光标已经在 15（点击/`←` 到达的）→ 按 `→` 也出公式', () {
      expect(nextCaretOffset(kDoc, kContentEnd), kCloseEnd);
    });

    test('★ 整条 `→` 扫描路径里**不出现**那个位点，但**必须出现** closeEnd', () {
      final List<int> visited = <int>[];
      var o = 0;
      while (o < kDoc.length) {
        final int n = nextCaretOffset(kDoc, o);
        visited.add(n);
        if (n <= o) break;
        o = n;
      }
      expect(visited, isNot(contains(kContentEnd)),
          reason: '`→` 允许停在 tex 末尾那个位点 → 手感上就是"按了没反应"');
      expect(visited, contains(kCloseEnd), reason: '`→` 必须能走出公式');
    });

    test('从文字进公式仍然正常（入口不受影响）', () {
      // 光标在开 `$` 之前 → `→` 进公式的第一个位点
      expect(nextCaretOffset(kDoc, kOpenDollar), kTexStart);
    });
  });

  group('★ `←`：故意**不**跳过（"我要改这段数学"的正当入口）', () {
    test('从公式后面按 `←` → 进到公式末尾（tex 末尾）', () {
      expect(prevCaretOffset(kDoc, kCloseEnd), kContentEnd,
          reason: r'这里必须停在 tex 末尾 —— 否则 `←` 会跳到最后一个原子**之前**，'
              '等于整段公式被跳过，想接着改还得再按几下');
    });

    test(r'从公式末尾继续 `←` → 逐个位点往回走，最后走出到开 `$` 之前', () {
      expect(prevCaretOffset(kDoc, kContentEnd), kAfterB);
      expect(prevCaretOffset(kDoc, kTexStart), kOpenDollar);
    });
  });

  group('对称性说明（写进测试，免得以后被"顺手统一"掉）', () {
    test('进/出的不对称是**有意**的：`→` 出 = 一步，`←` 进 = 停在末尾', () {
      expect(nextCaretOffset(kDoc, kAfterB), kCloseEnd);
      expect(prevCaretOffset(kDoc, kCloseEnd), kContentEnd);
      expect(kContentEnd, isNot(kCloseEnd),
          reason: '两个偏移本来就是两个不同的插入点：一个写进数学、一个写进正文（见设计稿 §3.3）');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // ★★ §4.0 通则（2026-10-15 改口径）：**删除目标 = 与光标【同层】的、紧邻的那一个渲染对象**
  //    · 文字里一个对象 = 一个字符
  //    · 公式**外侧**（或公式内的**主行层**）紧邻的是那个**结构** ⇒ **整个结构走**（内容一起）
  //    · 公式**里面某一层**（如分母槽）里 ⇒ 删的是**那一层**的对象
  //    · `$` / `$$` **不属于任何层** ⇒ 永远不是删除目标
  //
  //    两段由来（都是用户实测）：
  //    ① 光标停在分式**后面**按退格，原先只删掉了那个**看不见**的收尾 `$`
  //       → `\frac{}{}` 的编码爆出来（§3.3 原先的删除规则只有"公式首"一行）。
  //    ② ★ 光标停在分式**整体**后面按删除，原先只删掉分母里的 `b`、出现空位框 ——
  //       用户原话：「并不是像预期那样删除了整个 `a/b`」⇒ 判据原先**不带层级**。
  //    ★★ 特别注意「公式末尾」与「公式之后」：`$` 不可见 ⇒ 两者**是同一根像素** ⇒
  //       必须给出**同一个结果**（§3.3）。
  // ─────────────────────────────────────────────────────────────
  group(r'★ §4.0：删除目标 = 与光标同层的、紧邻的那一个渲染对象', () {
    test(r'Backspace 在公式**之后** → 删掉公式里那个对象（整个分式），不碰看不见的 `$`', () {
      final e = smartEditAt(kDoc, kCloseEnd, forward: false);
      expect(e.deletes, isTrue);
      expect(kDoc.substring(e.from!, e.to!), r'\frac{a}{b}',
          reason: '★ 被删的是**公式里的那个结构**，定界符一个都不许碰');
    });

    test('Delete 在公式**之前** → 同样删掉公式里第一个对象（整个分式）', () {
      final e = smartEditAt(kDoc, kOpenDollar, forward: true);
      expect(e.deletes, isTrue);
      expect(kDoc.substring(e.from!, e.to!), r'\frac{a}{b}');
    });

    test('★ 公式**内**末尾（= 公式之后，同一根像素）退格 → **同一个结果**', () {
      final e = smartEditAt(kDoc, kContentEnd, forward: false);
      expect(e.deletes, isTrue);
      expect(kDoc.substring(e.from!, e.to!), r'\frac{a}{b}',
          reason: '同一根像素必须同一种行为（否则用户无法预期）');
    });

    test('★ 公式**内**开头删除 → 同样是那一个对象（整个分式）', () {
      final e = smartEditAt(kDoc, kTexStart, forward: true);
      expect(e.deletes, isTrue);
      expect(kDoc.substring(e.from!, e.to!), r'\frac{a}{b}');
    });

    test(r'★ 光标在**分母里** `b` 之后退格 → 只删 `b`（出现空位框），分式还在', () {
      final e = smartEditAt(kDoc, kAfterB, forward: false);
      expect(e.deletes, isTrue);
      expect(kDoc.substring(e.from!, e.to!), 'b',
          reason: '★ 用户原话：「在 b 后面点删除就删 b 出现空位框」—— 层内删除只碰那一层');
    });

    test('紧贴公式**左边**退格 → 删的是左边那个文字（公式不动）', () {
      final e = smartEditAt(kDoc, kOpenDollar, forward: false);
      expect(e.deletes, isTrue);
      expect(kDoc.substring(e.from!, e.to!), '。',
          reason: '光标左边紧邻的可见对象是文字「。」，不是公式');
    });

    test('紧贴公式**右边**删除 → 删的是右边那个文字（公式不动）', () {
      final e = smartEditAt(kDoc, kCloseEnd, forward: true);
      expect(e.deletes, isTrue);
      expect(kDoc.substring(e.from!, e.to!), '尾');
    });

    // ★★ 全域不变量：这一类 bug 就是"某个偏移没人管"漏出来的，
    //    与光标归属那次同一个教训 —— 所以用同一把尺子量：
    //    **任意偏移上按任意一个删除键之后，每一行的 `$` 都必须仍然成对。**
    test(r'★★ 全域不变量：任意偏移按 Backspace/Delete 后，每行 `$` 仍成对', () {
      const List<String> docs = <String>[
        kDoc, // 文字。$\frac{a}{b}$尾
        r'文字。$\frac{}{}$$\frac{}{}$尾', // 相邻公式（源码里拼出 `$$`）
        r'$x$',
        r'$$',
        r'文字 $$\frac{}{}$$ 尾',
        r'文字 $x^2+1$ 与 $\frac{a}{b}=\sqrt{2}$ 结束', // 本仓样本里的真实句子
      ];
      for (final String doc in docs) {
        for (var o = 0; o <= doc.length; o++) {
          for (final bool fwd in <bool>[false, true]) {
            final e = smartEditAt(doc, o, forward: fwd);
            if (!e.deletes) continue;
            final String after =
                doc.substring(0, e.from!) + doc.substring(e.to!);
            for (final String line in after.split('\n')) {
              expect(r'$'.allMatches(line).length.isEven, isTrue,
                  reason: '★ 在偏移 $o 按 ${fwd ? "Delete" : "Backspace"} 之后定界符不成对\n'
                      '文档：「$doc」\n删掉的是「${doc.substring(e.from!, e.to!)}」\n'
                      '结果：「$after」');
            }
          }
        }
      }
    });

    test(r'★★ 行间公式：光标紧贴块尾退格，也不许删掉围栏的 `$$`', () {
      const String doc = '文字\n\n\$\$\nx = 1\n\$\$\n\n尾\n';
      final int closeEnd = doc.indexOf('尾') - 2; // 收尾 `$$` 之后（那个 `\n` 处）
      for (final int o in <int>[closeEnd - 1, closeEnd, closeEnd + 1]) {
        final e = smartEditAt(doc, o, forward: false);
        if (!e.deletes) continue;
        final String after = doc.substring(0, e.from!) + doc.substring(e.to!);
        for (final String line in after.split('\n')) {
          expect(r'$'.allMatches(line).length.isEven, isTrue,
              reason: '偏移 $o 退格之后 `\$\$` 围栏被破坏了：\n$after');
        }
      }
    });
  });
}
