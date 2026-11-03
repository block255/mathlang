// 2026-11-03（表批 B）：**局部表片段粘到正文 ⇒ 按行落成行内公式**。
//
// 用户拍板：拖选是线性的，片段常常不是想要的矩阵形状 ⇒ 正文里不再"造一个新矩阵"。
// 只认**中性 `bmatrix`**（局部片段的标记）；整表复制保留原类型，照旧是矩阵。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/paste_context.dart';

PasteDecision _atText(String payload) => decidePaste(
      doc: '前文此处',
      caret: 2,
      selStart: 2,
      selEnd: 2,
      payload: payload,
    );

void main() {
  group('局部表片段（bmatrix 载荷）粘到正文', () {
    test(r'⇒ 按行落成行内公式，`&` 变空格', () {
      final PasteDecision d =
          _atText(r'$\begin{matrix}b&c\\d&e\end{matrix}$');
      expect(d.apply, PasteApply.tableLines);
      expect(d.payload, r'$b\ c$' '\n' r'$d\ e$', reason: d.payload);
      expect(d.note, isNotNull);
    });

    test('一行两格 ⇒ 一行落成一条行内公式', () {
      final PasteDecision d = _atText(r'$\begin{matrix}a&b\end{matrix}$');
      expect(d.apply, PasteApply.tableLines);
      expect(d.payload, r'$a\ b$', reason: d.payload);
    });

    test('整表（bmatrix，用户那份就是）⇒ 照旧 asIs（还是一个矩阵）', () {
      final PasteDecision d =
          _atText(r'$\begin{bmatrix}a&b\\c&d\end{bmatrix}$');
      expect(d.apply, PasteApply.asIs);
    });

    test('普通公式载荷不受影响', () {
      final PasteDecision d = _atText(r'$\frac{a}{b}$');
      expect(d.apply, PasteApply.asIs);
    });

    test('落点在**数学里** ⇒ 不走"按行"（正文专用）', () {
      const String doc = r'行 $\frac{a}{b}$ 尾';
      final PasteDecision d = decidePaste(
        doc: doc,
        caret: doc.indexOf('frac') + 2,
        selStart: doc.indexOf('frac') + 2,
        selEnd: doc.indexOf('frac') + 2,
        payload: r'$\begin{matrix}b&c\\d&e\end{matrix}$',
      );
      expect(d.apply, isNot(PasteApply.tableLines), reason: d.apply.name);
    });
  });
}
