// 反馈 8 守卫：**粘合位点的光标按脚本档画**（画/插同源）。
//
// 现象（用户原话）：「我如果点在 f 和下标减号之间，虽然光标高度看来显然是跟在 f 后面的，
//   但是打出来的导数撇是这个很低的高度而且很小」。
// 根因：那一格是**粘合位点**（`CaretSite.glue`）——数据上属于主行 ⇒ 竖条按主行画；
//   而插入被 `neutralPoint` 规则①/② 挪进**脚本内容开头** ⇒ 撇落进脚本层（矮、低）。
// 口径：画/插同源 ⇒ 粘合位点按脚本档画（`caretVisualLevel`）。
//
// 改前必红：①②（改前 depth=0、script=false）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/math_nav.dart';

({int depth, bool script}) _level(String tex, int rel) =>
    caretVisualLevel(buildCaretSites(tex).snap(rel));

void main() {
  group('8 · 粘合位点的视觉层级', () {
    test('① `f_1` 的粘合位点（基座与下标之间）⇒ 脚本档、深 1', () {
      final CaretSite s = buildCaretSites(r'f_1').snap(1);
      expect(s.glue, isTrue, reason: '这一格必须被标成粘合位点');
      expect(_level(r'f_1', 1), (depth: 1, script: true));
    });

    test('② `x^{2}` 的粘合位点 ⇒ 脚本档、深 1', () {
      expect(_level(r'x^{2}', 1), (depth: 1, script: true));
    });

    test('③ 脚本内容里（`f_1` 的 `1` 之后）⇒ 脚本档、深 1', () {
      expect(_level(r'f_1', 2), (depth: 1, script: true));
    });

    test('④ 主行普通位置 ⇒ 不脚本、深 0', () {
      expect(_level(r'x+y', 2), (depth: 0, script: false));
      expect(_level(r'x', 1), (depth: 0, script: false));
    });

    test('⑤ 分式槽里 ⇒ 深 1，但**不是**脚本档（那是另一个结构）', () {
      expect(_level(r'\frac{a}{b}', 7), (depth: 1, script: false));
    });

    test('⑥ 同一基座的两个脚本之间（`x_1^2` 的 `_1` 与 `^2` 之间）⇒ 脚本档', () {
      // `x_1^2`：x=0 _=1 1=2 ^=3 2=4 ⇒ `^` 之前那一格是 3
      expect(_level(r'x_1^2', 3), (depth: 1, script: true));
    });
  });
}
