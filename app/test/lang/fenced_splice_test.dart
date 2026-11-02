// 2026-11-02 · `spliceFencedInline` 的纯函数守卫（接缝「乙」）
//
// 判据：合并围栏之后 **零新增字符**、**没有 `$$`、没有新增 `\n`**、光标落在正确位置。
// 改前红：旧路径 `applySymbolInsert` 会产出 `$$\n…` / 掉行（见提交说明的探针证据）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/fenced_splice.dart';

void main() {
  test('左邻公式 ⇒ 合并围栏', () {
    const String doc = r'$\lim$($\frac{a}{b}$)';
    final int from = doc.indexOf('(');
    final FencedSplice s = spliceFencedInline(
      doc: doc,
      from: from,
      to: doc.length,
      fenced: r'$(\frac{a}{b})^{}$',
      template: true,
    )!;
    expect(s.doc, r'$\lim(\frac{a}{b})^{}$');
    expect(s.mergedLeft, isTrue);
    expect(s.mergedRight, isFalse);
    expect(s.leftSpace, isFalse);
    expect(s.doc, isNot(contains(r'$$')));
    expect(s.doc, isNot(contains('\n')));
    expect(s.doc[s.caret - 1], '{');
    expect(s.doc[s.caret], '}');
  });

  test('右邻公式 ⇒ 合并围栏', () {
    const String doc = r'($\alpha$)$x$';
    final int to = doc.indexOf(')') + 1;
    final FencedSplice s = spliceFencedInline(
      doc: doc,
      from: 0,
      to: to,
      fenced: r'$(\alpha)^{}$',
      template: true,
    )!;
    expect(s.doc, r'$(\alpha)^{}x$');
    expect(s.mergedRight, isTrue);
    expect(s.mergedLeft, isFalse);
    expect(s.doc, isNot(contains(r'$$')));
  });

  test('两侧都是公式 ⇒ 一起合并', () {
    const String doc = r'$a$($\alpha$)$b$';
    final int from = doc.indexOf('(');
    final int to = doc.indexOf(')') + 1;
    final FencedSplice s = spliceFencedInline(
      doc: doc,
      from: from,
      to: to,
      fenced: r'$(\alpha)^{}$',
      template: true,
    )!;
    expect(s.doc, r'$a(\alpha)^{}b$');
    expect(s.mergedLeft, isTrue);
    expect(s.mergedRight, isTrue);
    expect(s.doc, isNot(contains(r'$$')));
  });

  test('左邻是文字 ⇒ 只插不并（本来就没有双美元）', () {
    const String doc = r'ln($\frac{a}{b}$)';
    final FencedSplice s = spliceFencedInline(
      doc: doc,
      from: 2,
      to: doc.length,
      fenced: r'$(\frac{a}{b})^{}$',
      template: true,
    )!;
    expect(s.doc, r'ln$(\frac{a}{b})^{}$');
    expect(s.mergedLeft, isFalse);
    expect(s.leftSpace, isFalse);
    expect(s.doc, isNot(contains(r'$$')));
  });

  test('文首括号 ⇒ 直接放', () {
    const String doc = r'($\alpha$)';
    final FencedSplice s = spliceFencedInline(
      doc: doc,
      from: 0,
      to: doc.length,
      fenced: r'$(\alpha)^{}$',
      template: true,
    )!;
    expect(s.doc, r'$(\alpha)^{}$');
    expect(s.mergedLeft, isFalse);
    expect(s.mergedRight, isFalse);
  });

  test('撇（template=false）⇒ 光标在载荷之后、收尾美元符之前', () {
    const String doc = r'$\lim$($\alpha$)';
    final int from = doc.indexOf('(');
    final FencedSplice s = spliceFencedInline(
      doc: doc,
      from: from,
      to: doc.length,
      fenced: r'$(\alpha)^{\prime}$',
      template: false,
    )!;
    expect(s.doc, r'$\lim(\alpha)^{\prime}$');
    expect(s.doc[s.caret], r'$', reason: '光标在收尾美元符之前');
  });

  test('不是完整行内公式 ⇒ null（交给旧路径）', () {
    expect(
      spliceFencedInline(
        doc: r'$a$',
        from: 2,
        to: 3,
        fenced: r'x^{}',
        template: true,
      ),
      isNull,
    );
    expect(
      spliceFencedInline(
        doc: r'$a$',
        from: 2,
        to: 3,
        fenced: r'$x$y$',
        template: true,
      ),
      isNull,
    );
  });
}
