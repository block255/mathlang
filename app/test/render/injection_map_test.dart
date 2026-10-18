// 点击定位的偏移换算测试（`renderToSourceOffset`）
//
// ★ 守的就是用户实测报的那条："点不到灰框/蓝框的位置，进不去空分母"。
//   根因：空槽在**原始源码里没有原子** —— 凡按"数原子"换算法都会落错地方。
//   现在改成"按插入串反算"：点在插入串内部 ⇒ 返回该**插入点** = 空槽的偏移 ✓

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/injection_map.dart';
import 'package:mathlang/render/slot_marks.dart';

void main() {
  group('★ 点空槽占位框 → 必须映射回**空槽的偏移**', () {
    test(r'\frac{a}{}：分母空（区间 [9,9)），点占位框任意位置都落到 9', () {
      const String src = r'\frac{a}{}';
      final String marked = injectSlotMarks(src, caretRel: 6).tex;
      final int at = marked.indexOf(kEmptySlotTex);
      expect(at, greaterThan(0), reason: '分母是空的，应该被注入占位');
      for (var k = 0; k < kEmptySlotTex.length; k++) {
        expect(renderToSourceOffset(marked, at + k), 9,
            reason: '点在占位串内部第 $k 个字符 → 都应回到空槽偏移 9');
      }
    });

    test(r'\frac{}{}：当前槽（分子）→ 6，另一个空槽（分母）→ 8', () {
      const String src = r'\frac{}{}';
      // 光标放进分子（偏移 6）→ 分子是"当前槽"（另一种占位样式），分母是普通空槽
      final String marked = injectSlotMarks(src, caretRel: 6).tex;
      final int curAt = marked.indexOf(kCurrentSlotTex);
      final int emptyAt = marked.indexOf(kEmptySlotTex);
      expect(curAt, greaterThanOrEqualTo(0), reason: '分子应是当前槽');
      expect(emptyAt, greaterThanOrEqualTo(0), reason: '分母应是普通空槽');
      expect(renderToSourceOffset(marked, curAt + 2), 6, reason: '点当前槽 → 分子偏移 6');
      // ★★ 2026-10-18 晚：这条 skip 已解开（原来报 7，应为 8）。
      //   现在实测就是 8 —— 中间那批改动（占位串换成 `M` + 宽度垫、当前槽换 `#FEFEFE`）
      //   把当年那个"多算 1 个 shift"的成因一起带走了。
      expect(renderToSourceOffset(marked, emptyAt + 2), 8,
          reason: '点空槽 → 分母偏移 8');
    });
  });

  group('普通位置：映射不改变偏移（除了插入串之前的那点位移）', () {
    test('开头与结尾都对得上', () {
      const String src = r'\frac{a}{}';
      final String marked = injectSlotMarks(src, caretRel: 6).tex;
      expect(renderToSourceOffset(marked, 0), 0);
      expect(renderToSourceOffset(marked, marked.length), src.length,
          reason: '渲染 tex 的末尾 = 原始 tex 的末尾');
    });

    test('占位串之前的偏移不受影响（它插在后面）', () {
      const String src = r'\frac{a}{}';
      final String marked = injectSlotMarks(src, caretRel: 6).tex;
      final int at = marked.indexOf(kEmptySlotTex);
      for (var r = 0; r <= at; r++) {
        expect(renderToSourceOffset(marked, r), r,
            reason: '占位串之前，渲染偏移与原始偏移相同');
      }
    });
  });

  group('光标条：点它 → 映射回插入点', () {
    test(r'\frac{a}{} 把光标注入到分子附近 → 点它回到它的插入点', () {
      const String src = r'\frac{a}{}';
      final String marked = injectSlotMarks(src, caretRel: 6).tex;
      final CursorInjection ci = injectCursor(marked, 8);
      final int at = ci.tex.indexOf(kCursorTex);
      expect(at, greaterThanOrEqualTo(0));
      // ★ 注意：`injectCursor` 会先把偏移**吸附**到合法位点，所以插入点是吸附后的值，
      //   不是传进去的 8（实测吸附成 7）——这里断言"映射回包内即回到插入点"
      final int snapped = buildCaretSites(marked).snap(8).offset;
      expect(renderToSourceOffset(ci.tex, at + 2), snapped,
          reason: '点在光标条内部 → 回到它的插入点（吸附后的位点）');
    });
  });
}
