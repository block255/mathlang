// ★★★ 2026-11-01（用户拍板「甲」）：**normalize 不再改写脚本的花括号**。
//
// 历史：2026-10-14 起 normalize ② 会把「单原子脚本参数」的花括号拆掉（`x^{2}` → `x^2`，
//   理由只是"源码整洁"）。但 `}` 虽然零宽，**占一个偏移** —— 一拆，
//   「下标/上标末尾」与「对象之后」就并成同一个偏移 ⇒ **那个光标位置永久消失**。
//   2026-10-17「`\lim_{x\to0}` 的 `n` 之后点不到」是第一次咬人；
//   2026-11-01「`$f_-$` 的『对象之后』消失、点不到 α 之前那一格」是第二次。
//   期间还打了四条例外 (a)(b)(c)(d) 和反向补丁 ③ —— 全是围着这条规则转。
// ⇒ 2026-11-01 用户拍板：**② 与 ③ 一起撤**（花括号是用户看不见的存储细节，
//   不许为"源码好看"牺牲可编辑性；平权 推论④ / 原则 2）。
//
// 本文件钉的是**撤掉之后**的口径：
//   ① 花括号**一律不拆**（`x^{2}` 保持 `x^{2}`）；
//   ② 反向也**不再补**（`x^2` 保持 `x^2`；老文档的那些位点仍然缺，这是接受的代价）；
//   ③ normalize 只剩「空结构回收」，且必须**幂等**、**不动光标**。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/normalize.dart';

void main() {
  group('① 不再拆花括号（撤 ②）', () {
    test(r'段中：x^{2}+1 保持 x^{2}+1', () {
      expect(normalizeTex(r'x^{2}+1', 1).tex, r'x^{2}+1');
    });

    test(r'结构槽尾：\frac{x^{3}}{y} 保持', () {
      expect(normalizeTex(r'\frac{x^{3}}{y}', 0).tex, r'\frac{x^{3}}{y}');
    });

    test(r'根号内容尾：\sqrt{x^{2}} 保持', () {
      expect(normalizeTex(r'\sqrt{x^{2}}', 0).tex, r'\sqrt{x^{2}}');
    });

    test(r'定界符组：\left(x^{2}\right) 保持', () {
      const String tex = r'\left(x^{2}\right)';
      expect(normalizeTex(tex, 0).tex, tex);
    });

    test(r'cases 格子：x^{2}\\ 保持', () {
      const String tex = '\\begin{cases}x^{2}\\\\y\\end{cases}';
      expect(normalizeTex(tex, 0).tex, tex);
    });

    test(r'多原子本来就不动：x^{2n} 保持', () {
      expect(normalizeTex(r'x^{2n}', 1).tex, r'x^{2n}');
    });
  });

  group('② 也不再补花括号（撤 ③）', () {
    test(r'老形态 \frac{x^3}{y} 原样保留（不再补成 x^{3}）', () {
      final NormalizeResult r = normalizeTex(r'\frac{x^3}{y}', 0);
      expect(r.tex, r'\frac{x^3}{y}');
      expect(r.changed, isFalse, reason: '只做空结构回收 ⇒ 这次没有可做的事');
    });

    test(r'\sqrt{x^2} 原样保留', () {
      expect(normalizeTex(r'\sqrt{x^2}', 0).tex, r'\sqrt{x^2}');
    });

    test(r'连写脚本原样：x^2_1', () {
      const String tex = r'x^2_1';
      expect(normalizeTex(tex, 0).tex, tex);
    });
  });

  group('③ 幂等 + 光标不动', () {
    test(r'跑两次无变化', () {
      final NormalizeResult once = normalizeTex(r'x^{2}+1', 1);
      final NormalizeResult twice = normalizeTex(once.tex, once.caret);
      expect(twice.tex, once.tex);
      expect(twice.changed, isFalse);
    });

    test('光标保持（没有编辑时）', () {
      final NormalizeResult r = normalizeTex(r'\frac{x^{3}}{y}', 13);
      expect(r.tex, r'\frac{x^{3}}{y}');
      expect(r.caret, 13);
    });
  });

  group('④ 空结构回收还在（唯一保留的规则）', () {
    test(r'光标不在里面时：a+\\frac{}{}+b ⇒ 空结构被回收', () {
      expect(normalizeTex(r'a+\frac{}{}+b', 0).tex.contains(r'\frac'), isFalse);
    });

    test(r'光标在里面时保住（2026-10-20 T-A F8 口径）', () {
      const String tex = r'\frac{}{}';
      expect(normalizeTex(tex, 6).tex, tex);
    });
  });
}
