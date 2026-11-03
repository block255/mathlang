// 2026-11-03 晚（表批 B · 落格）：**粘进表内**——剥壳取格、当前格为左上角、
// 整格覆盖、超界裁剪 + 状态栏说明。
//
// 改前（用户实测）：局部片段粘进表里会把 `\begin{matrix}…\end{matrix}` **原样插进格子**
// ⇒ 外面那张表被拆散，屏幕上变成"一堆散字 + 一个新矩阵"。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/env_table.dart';
import 'package:mathlang/lang/paste_context.dart';

const String _doc = '\$\$\n\\begin{pmatrix}a&b\\\\c&d\\end{pmatrix}\n\$\$';

/// 文档里 `a` 的偏移（第一个格的内容）。
int _cellA(String doc) => doc.indexOf('}a') + 1;

void main() {
  group('粘进表内（落格）', () {
    test('2×2 落到左上角 ⇒ 四格都被覆盖，壳与分隔符不动', () {
      final int a = _cellA(_doc);
      final PasteDecision d = decidePaste(
        doc: _doc,
        caret: a,
        selStart: a,
        selEnd: a,
        payload: r'$\begin{bmatrix}1&2\\3&4\end{bmatrix}$',
      );
      expect(d.apply, PasteApply.tableCells);
      expect(d.note, contains('2 行 × 2 列'));
      final String after =
          _doc.replaceRange(d.replaceFrom!, d.replaceTo!, d.payload);
      expect(after, '\$\$\n\\begin{pmatrix}1&2\\\\3&4\\end{pmatrix}\n\$\$',
          reason: after);
      // 光标落在最后一格内容之后
      expect(after[d.at! - 1], '4', reason: '光标应在 4 之后：${d.at}');
    });

    test('载荷比表大 ⇒ 裁剪 + 状态栏说明', () {
      final int a = _cellA(_doc);
      final PasteDecision d = decidePaste(
        doc: _doc,
        caret: a,
        selStart: a,
        selEnd: a,
        payload: r'$\begin{bmatrix}1&2&3\\4&5&6\\7&8&9\end{bmatrix}$',
      );
      expect(d.apply, PasteApply.tableCells);
      expect(d.note, contains('裁剪'), reason: d.note);
      final String after =
          _doc.replaceRange(d.replaceFrom!, d.replaceTo!, d.payload);
      expect(after, '\$\$\n\\begin{pmatrix}1&2\\\\4&5\\end{pmatrix}\n\$\$',
          reason: after);
    });

    test(r'从中间格起 ⇒ 从那一格往右下铺，左上角的格不动', () {
      final int b = _doc.indexOf('&b') + 1;
      final PasteDecision d = decidePaste(
        doc: _doc,
        caret: b,
        selStart: b,
        selEnd: b,
        payload: r'$\begin{bmatrix}X&Y\\Z&W\end{bmatrix}$',
      );
      expect(d.apply, PasteApply.tableCells);
      final String after =
          _doc.replaceRange(d.replaceFrom!, d.replaceTo!, d.payload);
      // 从 (0,1) 起只放得下一列 ⇒ 载荷第 2 列被裁掉；行方向也只有 1 行
      expect(after, '\$\$\n\\begin{pmatrix}a&X\\\\c&Z\\end{pmatrix}\n\$\$',
          reason: after);
      expect(d.note, contains('裁剪'), reason: d.note);
    });

    test('落点不在表内 ⇒ 不走落格（正文/公式照旧）', () {
      const String doc = r'前 $\frac{a}{b}$ 后';
      final PasteDecision d = decidePaste(
        doc: doc,
        caret: 1,
        selStart: 1,
        selEnd: 1,
        payload: r'$\begin{bmatrix}1&2\end{bmatrix}$',
      );
      expect(d.apply, isNot(PasteApply.tableCells), reason: d.apply.name);
    });

    test('cases 载荷不参与格分配（整块环境）', () {
      final int a = _cellA(_doc);
      final PasteDecision d = decidePaste(
        doc: _doc,
        caret: a,
        selStart: a,
        selEnd: a,
        payload: r'$\begin{cases}x\\y\end{cases}$',
      );
      expect(d.apply, isNot(PasteApply.tableCells), reason: d.apply.name);
    });

    test('cellGridOf：裸载荷也能切', () {
      expect(cellGridOf(r'a&b\\c&d'),
          <List<String>>[<String>['a', 'b'], <String>['c', 'd']]);
      expect(cellGridOf(r'\begin{matrix}a&b\end{matrix}'), isNotNull);
      expect(cellGridOf(r'\frac{a}{b}'), isNull);
    });
  });
}
