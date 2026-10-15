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
}
