// `\text{…}` 是**外来兼容容器**（我们自己打汉字走拆段/裸汉字，从不会生成它）：
// 保留它不动，但**删里面的东西要干脆** —— 不许出现"按了 ⌫ 屏幕上什么都没变"的死按。
//
// ★ 用户 2026-10-25 实测与拍板：
//   · 组**末尾**连按 ⌫：`：` `注` `旁` 三下删完 ✓（这一半本来就是好的）；
//   · 删空之后**第 4 下**：只"跳到 `\text` 前面"，而空 `\text{}` 宽度为零 ⇒ **同一像素** ⇒ 感觉卡住。
//   用户原话："接受外来的这个，但是删它里面的东西时，能够干脆地符合直觉地删干净就可以了吧"。
//
// ★ 判据（本文件的钉子）：**每一次删除都必须干掉一个"看得见的东西"，或者干脆什么都不做；
//   绝不许"删掉一段零宽存储、屏幕上毫无变化"**。实现上：删掉包装里最后一点内容时，
//   **同一次按键**把整条 `\text{…}` 一起回收（空包装不许留给下一次按键）。
//
// ★ 对照口径（可见容器照旧"只跳不删"）：`\frac{}{}` / `\sqrt{}` 的分子首按 ⌫ 仍然只跳。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/smart_delete.dart';

const String _line =
    r'= \lim\limits_{x\to0} b^{x^{2}} (e^{x^2 \ln\frac{a}{b}} - 1) \quad (\text{旁注：} x\to0 \text{ 时 } x^2 \ln\frac{a}{b} \to 0)';

String _apply(String tex, SmartEdit e) =>
    e.deletes ? tex.replaceRange(e.from!, e.to!, '') : tex;

void main() {
  group('现场：把 `\\text{旁注：}` 从头删到底', () {
    test('★ 从组末尾连按 ⌫：每一下都要么删掉可见内容，要么整体回收包装', () {
      final String tex = _line;
      final int groupAt = tex.indexOf(r'\text{旁注：}');
      expect(groupAt, greaterThan(0));
      // 光标停在 `：` 之后（`}` 之前）
      int rel = groupAt + r'\text{旁注：'.length;
      String cur = tex;
      final List<String> steps = <String>[];
      for (var press = 1; press <= 4; press++) {
        final CaretSiteTable t = buildCaretSites(cur);
        // 逐次重算光标位置（每次删掉几个字符就要往左挪几个）
        final SmartEdit e = smartBackspace(t, rel);
        expect(e.isNone || e.deletes || e.caret != rel, isTrue,
            reason: '第 $press 下：既没删东西、光标也没动 ⇒ 死按');
        if (e.isNone) {
          steps.add('第 $press 下：none');
          break;
        }
        if (!e.deletes) {
          // 只移动是允许的，但**这一下在屏幕上必须真的动**（跨度 > 0）
          // 空 `\text{}` 宽度为零 ⇒ 从组内跳到组外 = 同一像素
          final int moved = (e.caret - rel).abs();
          expect(moved, greaterThan(0));
          final String between =
              moved > 0 ? cur.substring(rel, e.caret).trim() : '';
          expect(between.isNotEmpty, isTrue,
              reason: '第 $press 下：从 $rel 跳到 ${e.caret}，中间全是不可见字符'
                  '（「${cur.substring(rel < e.caret ? rel : e.caret, rel < e.caret ? e.caret : rel)}」）'
                  '⇒ 屏幕上没有任何变化 = 死按');
          rel = e.caret;
          steps.add('第 $press 下：移动 → ${e.caret}');
          continue;
        }
        final String gone = cur.substring(e.from!, e.to!);
        steps.add('第 $press 下：删「$gone」');
        cur = _apply(cur, e);
        rel = e.caret;
        // 下一步的 rel 已在 cur 里
      }
      // 4 下之内必须**已经把这一条 `\text{…}` 收掉**（不留幽灵），
      // 而且每一步都删掉了东西（没有死按）、并且确实有一次是"连包装一起回收"。
      expect(cur.contains('旁'), isFalse,
          reason: '四下之后 `旁` 还在：${steps.join(" · ")}');
      expect(cur.contains(r'(\text{'), isFalse,
          reason: '那个 `(` + `\\text{…}` 应当已经删掉了：${steps.join(" · ")}');
      expect(steps.any((String s) => s.contains(r'删「\text{')), isTrue,
          reason: '应当有一次按键把整条包装回收掉：${steps.join(" · ")}');
      expect(steps.any((String s) => s.contains('删「(')), isTrue,
          reason: '收掉包装之后那一下应当继续删可见对象 `(`：${steps.join(" · ")}');
      expect(steps.any((String s) => s.contains('none')), isFalse,
          reason: '不许出现"按了没反应"：${steps.join(" · ")}');
      // ignore: avoid_print
      print('  步骤：${steps.join(" · ")}');
    });

    test('★ 空 `\\text{}`（外来文档）按 ⌫ ⇒ 一下带走"空包装 + 左边那个可见对象"', () {
      const String tex = r'\quad (\text{} x\to0)';
      final CaretSiteTable t = buildCaretSites(tex);
      final int inside = tex.indexOf(r'\text{}') + r'\text{'.length;
      final SmartEdit e = smartBackspace(t, inside);
      expect(e.deletes, isTrue,
          reason: '空包装上按 ⌫ 必须删掉东西（否则屏幕上毫无变化 = 死按）');
      final String gone = tex.substring(e.from!, e.to!);
      expect(gone.contains(r'\text{}'), isTrue,
          reason: '这一下必须把空包装带走（否则它会一直留在文档里），实际删的是「$gone」');
      expect(gone.contains('('), isTrue,
          reason: '这一下还必须带走左边那个**可见**对象 `(`（否则屏幕上没有变化），'
              '实际删的是「$gone」');
    });
  });

  group('对照：可见容器照旧"只跳不删"', () {
    test('`\\frac{}{}` 的分子首按 ⌫ ⇒ 只移动（可见结构不透明）', () {
      const String tex = r'\frac{}{}';
      final CaretSiteTable t = buildCaretSites(tex);
      final SmartEdit e = smartBackspace(t, 6);
      expect(e.deletes, isFalse, reason: '可见容器（有分数线）不许被 ⌫ 拆');
      expect(e.isNone, isFalse);
    });

    test('`\\sqrt{}` 的被开方数首按 ⌫ ⇒ 只移动', () {
      const String tex = r'\sqrt{}';
      final CaretSiteTable t = buildCaretSites(tex);
      final SmartEdit e = smartBackspace(t, 6);
      expect(e.deletes, isFalse, reason: '可见容器（有根号）不许被 ⌫ 拆');
    });
  });

  group('安全：透明不等于乱删', () {
    test('`\\textcolor{色}{\\text{}}` 上按 ⌫ 不许把颜色参数吃掉', () {
      const String tex = r'\textcolor{#FF0000}{\text{}}x';
      final CaretSiteTable t = buildCaretSites(tex);
      final int inside = tex.indexOf(r'\text{}') + r'\text{'.length;
      final SmartEdit e = smartBackspace(t, inside);
      if (e.deletes) {
        final String gone = tex.substring(e.from!, e.to!);
        expect(gone.contains('#FF0000'), isFalse,
            reason: '不许删到颜色参数，实际删「$gone」');
        expect(gone.startsWith('\$'), isFalse,
            reason: '不许删到 `\\textcolor` 的命令名，实际删「$gone」');
      }
    });

    test('`\\text{甲}\\text{乙}`：删甲时不许把乙一起带走', () {
      const String tex = r'\text{甲}\text{乙}';
      final CaretSiteTable t = buildCaretSites(tex);
      final SmartEdit e = smartBackspace(t, 7); // 甲之后
      expect(e.deletes, isTrue);
      final String gone = tex.substring(e.from!, e.to!);
      expect(gone.contains('乙'), isFalse, reason: '实际删「$gone」');
    });
  });
}
