// ★★ 2026-10-24（批 4c · G1）：**组内容里退格，删字母，不许碰定界符**
//
// 用户实测（原话）：「我在 sinx 四个字母里任意两个字母之间点删除都说公式不完整」。
// 打点后坐实：光标在 `\frac{x^{3}}{\left|{sinx}\right|}` 的 `i` 之后（doc 24 = tex 21），
//   `smartEditAt(doc, 24)` 返回 **[21,22) = tex[18..19) = `|`**（`\left` 后面那根定界符）
//   ⇒ `\left{sinx}\right|` ⇒ KaTeX 报 `[公式不完整]`。
//   而且删的总是**同一根** `|` ⇒ 所以在任意两个字母之间退格都报同一个错。
//
// 根因：`smartBackspace` 走到 `_objectLeftOf` 时把"同层左边最近的那一项"判成了**定界符**。
// 修法（**安全网**，不碰任何既有口径）：要删的那一项是**纯语法**（`|` `{}` `^` `_` `\left`…）
//   而光标左边紧贴一个普通字母/数字 ⇒ 改删那个字。
//   ★ `\alpha` 整词、`b^2` 裸参数连删、挂件边缘、算子作用域 —— 它们的 obj 都不是"纯语法"
//     ⇒ 一律照旧（有既有守卫钉着）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/math_nav.dart';
import 'package:mathlang/render/smart_delete.dart';

/// 在**文档**里退格一次（与真实按键同一条路径：`smartEditAt` 走 `mathRegionAt`）
String _backspaceInDoc(String tex, int texOffset) {
  final String doc = '\$\$\n$tex\n\$\$';
  final SmartEdit e = smartEditAt(doc, 3 + texOffset, forward: false);
  return e.deletes ? doc.replaceRange(e.from!, e.to!, '') : doc;
}

void main() {
  const String tex = r'\frac{x^{3}}{\left|{sinx}\right|}';

  test('★★ 在 sinx 的每一处退格 ⇒ 都只删一个字母，定界符一个不动', () {
    // `\left|` 13-17，`|` 18，`{` 19，s 20 i 21 n 22 x 23，`}` 24
    const List<int> offsets = <int>[21, 22, 23, 24];
    const List<String> want = <String>[
      r'\frac{x^{3}}{\left|{inx}\right|}',
      r'\frac{x^{3}}{\left|{snx}\right|}',
      r'\frac{x^{3}}{\left|{six}\right|}',
      r'\frac{x^{3}}{\left|{sin}\right|}',
    ];
    for (var i = 0; i < offsets.length; i++) {
      final String got = _backspaceInDoc(tex, offsets[i]);
      expect(got, '\$\$\n${want[i]}\n\$\$',
          reason: '在 tex[${offsets[i]}] 退格（第 ${i + 1} 处）');
      // ★ 定界符必须还在（这就是改前坏掉的地方：`\left{sinx}` 少了 `|`）
      expect(got.contains(r'\left|'), isTrue,
          reason: '改前这里会变成 `\\left{sinx}\\right|`（定界符被删）');
      expect(got.contains(r'\right|'), isTrue);
    }
  });

  test('★ 对照：不在公式里（文字层）仍然只删一个字符', () {
    const String doc = '甲乙丙';
    final SmartEdit e = smartEditAt(doc, 2, forward: false);
    expect(e.deletes, isTrue);
    expect(doc.replaceRange(e.from!, e.to!, ''), '甲丙');
  });

  test('★ 既有口径没被带坏：`\\alpha` 整词、`b^2` 裸参数连删', () {
    final SmartEdit a = smartEditAt(r'$\alpha$', 3 + 5, forward: false);
    expect(r'$\alpha$'.replaceRange(a.from!, a.to!, ''), r'$$',
        reason: '`\\alpha` 要整词删，不许只剩 `\\alph`');
    final SmartEdit b = smartEditAt(r'$b^2$', 3 + 3, forward: false);
    expect(r'$b^2$'.replaceRange(b.from!, b.to!, ''), r'$b$',
        reason: '裸参数 `^2` 要连 `^` 一起删，不许留 `b^`');
  });
}
