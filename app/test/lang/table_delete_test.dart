// 2026-11-03「表」批：**矩形删除**（`planDelete` 的表分支）。
//
// 口径（§3.3）：删格 = 删每格**内容**，`&` / `\\` 保留（留空），**一步撤销**；
// **覆盖了全部格** ⇒ 按整表删（连壳），块里只剩空白就按 §七 回收围栏。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/delete_range.dart';

import 'table_test_pos.dart';

const String _pm = '\$\$\n\\begin{pmatrix}a&b\\\\c&d\\end{pmatrix}\n\$\$';
const String _cases = '\$\$\n\\begin{cases}a\\\\b\\\\c\\end{cases}\n\$\$';

String _apply(String doc, DeletePlan p) =>
    doc.replaceRange(p.from, p.to, p.replacement);

void main() {
  group('删格：清内容、留分隔符', () {
    test('选行 0 两格 ⇒ 只剩 `&`，行 1 原样', () {
      final int s = cellPos(_pm, 'a');
      final int e = cellPos(_pm, 'b') + 1;
      final DeletePlan p = planDelete(_pm, s, e);
      expect(_apply(_pm, p),
          '\$\$\n\\begin{pmatrix}&\\\\c&d\\end{pmatrix}\n\$\$');
      expect(p.clipboardText, r'$\begin{bmatrix}a&b\end{bmatrix}$',
          reason: p.clipboardText);
    });

    test('选区只到 `&`（第二格还没选）⇒ 两格都算盖住', () {
      final int s = cellPos(_pm, 'a');
      final int e = _pm.indexOf('&') + 1;
      final DeletePlan p = planDelete(_pm, s, e);
      expect(_apply(_pm, p),
          '\$\$\n\\begin{pmatrix}&\\\\c&d\\end{pmatrix}\n\$\$');
      expect(p.clipboardText, r'$\begin{bmatrix}a&b\end{bmatrix}$',
          reason: p.clipboardText);
    });

    test('单格（不跨格）⇒ 只删那格的内容，不扩', () {
      final int s = cellPos(_pm, 'c');
      final DeletePlan p = planDelete(_pm, s, s + 1);
      expect(_apply(_pm, p),
          '\$\$\n\\begin{pmatrix}a&b\\\\&d\\end{pmatrix}\n\$\$');
      expect(p.clipboardText, r'$c$', reason: p.clipboardText);
    });

    test('一步撤销：清两格压成**一次**替换，替换内容就是那个 `&`', () {
      final int s = cellPos(_pm, 'a');
      final int e = cellPos(_pm, 'b') + 1;
      final DeletePlan p = planDelete(_pm, s, e);
      expect(p.replacement, '&', reason: '分隔符原样留下');
      expect(p.from, cellPos(_pm, 'a'));
      expect(p.to, cellPos(_pm, 'b') + 1);
    });
  });

  group('覆盖全部格 ⇒ 整表删', () {
    test('连壳删掉，围栏按 §七 回收（整块移除）', () {
      final int s = cellPos(_pm, 'a');
      final int e = cellPos(_pm, 'd') + 1;
      final DeletePlan p = planDelete(_pm, s, e);
      expect(_apply(_pm, p), '', reason: '整块应当回收干净');
      expect(p.clipboardText, r'$\begin{pmatrix}a&b\\c&d\end{pmatrix}$',
          reason: p.clipboardText);
    });
  });

  group('行单位', () {
    test('cases 清前两行 ⇒ 空行留下（`\\\\` 保留）', () {
      final int s = cellPos(_cases, 'a');
      final int e = cellPos(_cases, 'b') + 1;
      final DeletePlan p = planDelete(_cases, s, e);
      expect(_apply(_cases, p),
          '\$\$\n\\begin{cases}\\\\\\\\c\\end{cases}\n\$\$',
          reason: _apply(_cases, p));
      expect(p.clipboardText, r'$\begin{cases}a\\b\end{cases}$',
          reason: p.clipboardText);
    });
  });
}
