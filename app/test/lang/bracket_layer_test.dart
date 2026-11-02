// 2026-11-02 · **括号对必须同层**（输入层守卫，R-甲7）
//
// 用户现场：`$\lim…(\frac…{2}$)` 是自然打出来的——`(` 在公式里、`)` 在公式外，
// 收尾 `$` 被夹在括号里面 ⇒ 按 `^` 只能写字面量。
//
// 判据（只认"紧贴公式边界"的闭合括号）：
//   · 开括号在数学里、`)` 打在正文（紧跟收尾 `$`）⇒ `)` 落进公式；
//   · 开括号在正文、`)` 打在数学里（紧跟收尾 `$`）⇒ `)` 落到公式之后；
//   · 中间夹着别的文字 ⇒ **不动**（搬了会变语义）。
//
// 改前红：A / B / E / F / G（旧代码一律"保持原位"）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/insert_guard.dart';

void main() {
  test('A 开在数学、闭在正文 ⇒ 落进公式（同一层）', () {
    const String doc = r'$\lim(\frac{a}{b}$';
    final int dollar = doc.lastIndexOf(r'$');
    final InsertPlan p = planInsert(doc, doc.length, ')');
    expect(p.offset, dollar, reason: '`)` 要落在收尾美元符之前（公式里）');
    expect(p.moved, isTrue);
  });

  test('B 开在正文、闭在数学 ⇒ 落到公式之后（同一层）', () {
    const String doc = r'($\frac{a}{b}$';
    final int dollar = doc.lastIndexOf(r'$');
    final InsertPlan p = planInsert(doc, dollar, ')');
    expect(p.offset, doc.length, reason: '`)` 要落在收尾美元符之后（正文）');
    expect(p.moved, isTrue);
  });

  test('C 正常形状不动：开在正文、闭也打在正文', () {
    const String doc = r'($a$';
    final InsertPlan p = planInsert(doc, doc.length, ')');
    expect(p.offset, doc.length);
    expect(p.moved, isFalse);
  });

  test('D 中间夹着文字时不动（搬了会变语义）', () {
    const String doc = r'$\lim(x$ + 1';
    final InsertPlan p = planInsert(doc, doc.length, ')');
    expect(p.offset, doc.length);
    expect(p.moved, isFalse);
  });

  test('E 嵌套：配对的是最外层未闭合的开括号', () {
    const String doc = r'$\lim(\sin(x)+1$';
    final InsertPlan p = planInsert(doc, doc.length, ')');
    expect(p.offset, doc.lastIndexOf(r'$'));
    expect(p.moved, isTrue);
  });

  test('F 全角括号', () {
    const String doc = r'$\lim（a$';
    final InsertPlan p = planInsert(doc, doc.length, '）');
    expect(p.offset, doc.lastIndexOf(r'$'));
    expect(p.moved, isTrue);
  });

  test('G 方括号', () {
    const String doc = r'$\lim[a$';
    final InsertPlan p = planInsert(doc, doc.length, ']');
    expect(p.offset, doc.lastIndexOf(r'$'));
    expect(p.moved, isTrue);
  });

  test('H 行间围栏不参与：括号规则不许把它当行内段', () {
    const String doc = '\$\$\na\n\$\$';
    final InsertPlan p = planInsert(doc, doc.length, ')');
    expect(p.why ?? '', isNot(contains('括号对必须同层')),
        reason: '行间围栏不能走"括号对同层"这条规则');
  });
}
