// 2026-11-13：**选区的单位与半边定界符**（render 层，纯函数）。
//
// 改前红：
//   · 双击 `\left|` 那根竖线 ⇒ 只选中 `\left|` 这半个（`MathNode` 把它当独立对象）
//     ⇒ 打字/删除只剩孤立的 `\right|`（红字）；
//   · 三击行间块 ⇒ 选区含 `$$` 与首尾换行（与 11-03 §七「围栏不参与选区」冲突）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/selection_range.dart';

void main() {
  group('双击半边定界符 ⇒ 整对', () {
    const String doc = r'$a+\left|f\right|+b$';

    test(r'双击 `\left|` 的竖线 ⇒ 选中整对（改前：只选 `\left|`）', () {
      final ({int start, int end}) r = wordRangeAt(doc, 8); // 那根 `|`
      expect(doc.substring(r.start, r.end), r'\left|f\right|',
          reason: '实际 [${r.start},${r.end}) = <${doc.substring(r.start, r.end)}>');
    });

    test(r'双击 `\right|` 的竖线 ⇒ 同上', () {
      final ({int start, int end}) r = wordRangeAt(doc, 16);
      expect(doc.substring(r.start, r.end), r'\left|f\right|');
    });

    test(r'点 `\right|` 上报的落点（token 末尾 17）⇒ 也整对', () {
      // 真实点击那根竖线时，命中给的是**这一个 token 的末尾**（17），不是 token 内部。
      final ({int start, int end}) r = wordRangeAt(doc, 17);
      expect(doc.substring(r.start, r.end), r'\left|f\right|');
    });

    test('双击内容里的字 ⇒ 仍只选那个字（不扩到整对）', () {
      final ({int start, int end}) r = wordRangeAt(doc, 9);
      expect(doc.substring(r.start, r.end), 'f');
    });
  });

  group('三击行间块 ⇒ 只选可见内容（围栏不参与选区）', () {
    final String doc = <String>[r'$$', 'f(x)=x', r'$$', ''].join('\n');

    test(r'选区 = 可见内容，不含 `$$` / 首尾换行', () {
      final ({int start, int end}) r = unitRangeAt(doc, doc.indexOf('x'));
      expect(doc.substring(r.start, r.end), 'f(x)=x',
          reason: '实际 [${r.start},${r.end}) = <${doc.substring(r.start, r.end)}>');
      expect(doc.substring(r.start, r.end).contains('\n'), isFalse);
    });

    test('普通文字三击仍选整行（老行为不许改坏）', () {
      const String d = '甲乙 丙丁\n第二行\n';
      final ({int start, int end}) r = unitRangeAt(d, 1);
      expect(d.substring(r.start, r.end), '甲乙 丙丁');
    });
  });
}
