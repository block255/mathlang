// normalize 测试（S3-5 · 设计稿 §七）
//
// ★ 规格特别点名："**多余花括号这条最容易写错，必须单测**" —— 所以这里逐条钉死。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/normalize.dart';

void main() {
  group('① 空结构回收：全空的结构单元整段删', () {
    // ★★ 2026-10-20（T-A F8，用户拍板"乙"）：口径变了 —— **光标还落在里面的空结构不回收**
    //   （刚插的模板在失焦那一刻不许被吞掉，见 `normalize_keep_caret_structure_test.dart`）。
    //   所以这一组原来的用例一律把光标挪到**结构之外**，继续钉"真正的空壳照旧回收"。
    test(r'\frac{}{} → 光标在外面 ⇒ 删光', () {
      final NormalizeResult r = normalizeTex(r'\frac{}{}+y', 11);
      expect(r.tex, r'+y');
      expect(r.changed, isTrue);
    });

    test(r'x+\frac{}{}+y → 只删中间那个结构（前后文字不动）', () {
      final NormalizeResult r = normalizeTex(r'x+\frac{}{}+y', 0);
      expect(r.tex, r'x++y');
    });

    test(r'\sqrt{} → 光标在外面 ⇒ 删光', () {
      expect(normalizeTex(r'\sqrt{}+1', 9).tex, r'+1');
    });

    test(r'\frac{a}{} → **有内容就不动**（只回收全空的）', () {
      final NormalizeResult r = normalizeTex(r'\frac{a}{}', 0);
      expect(r.tex, r'\frac{a}{}', reason: '分子非空 → 绝不拆结构（与 §4.3 一致）');
      expect(r.changed, isFalse);
    });

    test('嵌套：**两轮**回收（先删里面的根号，外层随之变空再删）', () {
      // 光标放在整段**之前**（不在任何空结构里；★ 贴着结构末尾算"还在它身上"，所以不能放末尾）
      final NormalizeResult r = normalizeTex(r'x+\frac{\sqrt{}}{}', 1);
      expect(r.tex, r'x+');
      expect(r.changes, 2,
          reason: '第一轮：分子里的 \\sqrt{} 全空 → 删；第二轮：\\frac{}{} 这才变全空 → 删');
    });
  });

  group('② 多余花括号：**只在去掉后仍是单原子时**去', () {
    test(r'x^{2} → x^2 ✅', () {
      final NormalizeResult r = normalizeTex(r'x^{2}', 1);
      expect(r.tex, r'x^2');
    });

    test(r'x_{i} → x_i ✅', () {
      expect(normalizeTex(r'x_{i}', 1).tex, r'x_i');
    });

    test(r'x^{2n} → **不动** ❌（两个原子）', () {
      final NormalizeResult r = normalizeTex(r'x^{2n}', 1);
      expect(r.tex, r'x^{2n}', reason: '★ 规格点名的易错点：多原子绝不能去括号');
      expect(r.changed, isFalse);
    });

    test(r'x^{\alpha} → x^\alpha ✅（命令算一个原子）', () {
      expect(normalizeTex(r'x^{\alpha}', 1).tex, r'x^\alpha');
    });

    test(r'x^{\frac{a}{b}} → 不动（结构不是"单原子"）', () {
      final NormalizeResult r = normalizeTex(r'x^{\frac{a}{b}}', 1);
      expect(r.tex, r'x^{\frac{a}{b}}');
    });

    test(r'\frac{2}{3} → 不去括号（只处理 ^/_ 的参数）', () {
      final NormalizeResult r = normalizeTex(r'\frac{2}{3}', 0);
      expect(r.tex, r'\frac{2}{3}');
    });
  });

  group('★ 不得让光标乱跳', () {
    test('删除空结构后，光标跟着**左移**（落在删除点，不在文中乱飞）', () {
      // ★ 2026-10-20（F8 之后）：光标在**结构之后**才可能触发回收
      //   （在结构里面的话空结构会被保住，见 `normalize_keep_caret_structure_test.dart`）
      const String src = r'ab\frac{}{}cd';
      final NormalizeResult r = normalizeTex(src, src.length); // 光标在末尾
      expect(r.tex, 'abcd');
      expect(r.caret, 4, reason: '删掉 9 个字符 ⇒ 光标左移 9（落回 `abcd` 末尾）');
    });

    test('删除位置**之前**的光标不受影响', () {
      const String src = r'ab\frac{}{}cd';
      final NormalizeResult r = normalizeTex(src, 1);
      expect(r.caret, 1);
    });

    test('去花括号后光标跟着内容走（不能偏出内容）', () {
      const String src = r'x^{2}';
      final NormalizeResult r = normalizeTex(src, 4); // 光标在 2 之后（`}` 之前）
      expect(r.tex, r'x^2');
      expect(r.caret, 3, reason: '原来在 2 之后 → 现在也在 2 之后');
    });
  });

  group('幂等与克制', () {
    test('再跑一次不再变化', () {
      final NormalizeResult once = normalizeTex(r'x^{2}+\frac{}{}', 1);
      final NormalizeResult twice = normalizeTex(once.tex, once.caret);
      expect(twice.tex, once.tex);
      expect(twice.changed, isFalse);
    });

    test('本来干净的 tex 一动不动', () {
      for (final String tex in <String>[
        r'\frac{a}{b}',
        r'x^2+1',
        r'\alpha+\beta',
        r'\sqrt[3]{x}',
      ]) {
        final NormalizeResult r = normalizeTex(tex, 0);
        expect(r.tex, tex, reason: 'tex=$tex');
        expect(r.changed, isFalse);
      }
    });

    test('降级表（配对失败）里什么都不做', () {
      final NormalizeResult r = normalizeTex(r'a}b', 1);
      expect(r.tex, r'a}b');
      expect(r.changed, isFalse);
    });
  });
}
