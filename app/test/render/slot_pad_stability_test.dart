// 守卫测试：**空槽垫子的"有无"与"光标可见性"无关**（2026-10-18 用户实测的排版闪动）。
//
// 背景：空槽占位是"注进 TeX 的字形"（`kSlotPadGlyph = 'M'` + 零高宽度垫），**会改版面宽度**。
//   修复前：`renderMathTex(tex, caretRel: 光标不可见 ? -1 : rel)` —— 光标闪烁"灭"的那一帧
//   垫子整段消失 ⇒ 每秒重排两次 ⇒ 用户看到"虚线框若隐若现 + 排版闪动"，`aligned` 里还表现为
//   "两侧填上内容后等号对不齐"。
//   修复后：`caretRel`（逻辑位置）与 `showCursor`（视觉可见性）分开。
//
// 另两条同批的判据：
//   ① 当前槽的垫子墨色必须**不可见**（原先用淡蓝 `#E3F2FD`，白底上会露出一个淡蓝 M）；
//   ② **多行环境的格子不画占位框**（用户拍板：格子自己就是落点，画框会把"渲染提示"变成域）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/slot_marks.dart';

int countPads(String tex) {
  // 空槽（#FFFFFF）与当前槽（#FEFEFE）用的是同一个垫子串 ⇒ 按垫子本体数，别按墨色数
  return RegExp(RegExp.escape(kSlotPadInner)).allMatches(tex).length;
}

void main() {
  group('空槽垫子只看位置、不看可见性', () {
    // ★ 靶子是**可选槽**：`\sqrt[]{x}` 的次数位是空的（`[` 在 5、`]` 在 6、内容区间 [6,6)）。
    //   必填槽（空的分母 / 被开方数）的垫子本来就恒在、与光标无关 —— 会闪的正是可选槽：
    //   `_shouldDrawEmptySlot` 对可选槽的判据是"光标在这个结构里"，而修复前那个位置
    //   在闪烁"灭"的相位会被算成 -1 ⇒ 垫子整段消失 ⇒ 宽度变 ⇒ 重排。
    const String sqrtOpt = r'\sqrt[]{x}';
    const int caretInOpt = 6;

    test('showCursor=false 与 true 的垫子数量相同，且都为 1', () {
      final String noCursor =
          renderMathTex(sqrtOpt, caretRel: caretInOpt, showCursor: false);
      final String withCursor =
          renderMathTex(sqrtOpt, caretRel: caretInOpt, showCursor: true);
      expect(countPads(noCursor), 1, reason: '光标不可见时，次数位的垫子也必须留着（否则整行重排）');
      expect(countPads(withCursor), countPads(noCursor),
          reason: '可见性不能改变垫子（它改宽度 ⇒ 会重排）');
    });

    test('光标离开这个结构 ⇒ 可选槽的垫子确实不注（既定行为不变）', () {
      expect(countPads(renderMathTex(sqrtOpt, caretRel: -1)), 0);
    });

    test('垫子墨色不可见：tex 里不该出现淡蓝 #E3F2FD', () {
      final String t = renderMathTex(sqrtOpt, caretRel: caretInOpt);
      expect(t.toUpperCase().contains('E3F2FD'), isFalse,
          reason: '当前槽垫子用淡蓝墨 ⇒ 白底上露出一个淡蓝 M');
    });
  });

  group('多行环境不画占位框', () {
    test(r'aligned 的格子不注入垫子', () {
      const String aligned = r'\begin{aligned}&=\\&=\end{aligned}';
      // 第一格（`&` 之前）是空的：caretRel 落在格子起点
      final String t = renderMathTex(aligned, caretRel: 15);
      expect(countPads(t), 0, reason: '格子里注垫子会改列宽 ⇒ 等号对不齐');
    });

    test(r'cases 的格子不注入垫子', () {
      const String cases = r'\begin{cases}&\\&\end{cases}';
      final String t = renderMathTex(cases, caretRel: 13);
      expect(countPads(t), 0);
    });
  });
}
