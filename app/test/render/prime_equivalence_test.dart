// 裸撇（`'`）与 `^{\prime}` **必须等价** —— 口径「撇是脚本」（2026-11-01）。
//
// 为什么单独钉：`c16cd74` 之后**新打的**撇一律写 `^{\prime}`，但还有两个来源会留下裸撇：
//   ① 今天之前打的 / 导入的老文档；② 面板从正文侧插入（见 prime_typing_test ⑤）。
// 现状（探针实测）：裸撇在模型里是**普通原子** ⇒ `f_{-}'` 的对象之后退格只删掉 `'`，
//   把 `f_{-}` 留在原地 —— 一个对象被劈成两半；而 `f_{-}^{\prime}` 同一位点是整块删。
// ⇒ 同一个东西两种行为 = 行内行间之外的第二套标准，必须消除。
//
// 改前必红：①②③④⑤

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/smart_delete.dart';

String? _deleted(String tex, int rel) {
  final SmartEdit e = smartBackspace(buildCaretSites(tex), rel);
  if (!e.deletes) return null;
  return tex.substring(e.from!, e.to!);
}

void main() {
  test(r"① 裸撇 f' 的对象之后 ⇒ 整块走", () {
    expect(_deleted(r"f'", 2), r"f'");
  });

  test(r"② 先下标再撇 f_{-}' ⇒ 整块走（用户现场）", () {
    expect(_deleted(r"f_{-}'", 6), r"f_{-}'");
  });

  test(r"③ 先撇再下标 f'_{+} ⇒ 整块走", () {
    expect(_deleted(r"f'_{+}", 6), r"f'_{+}");
  });

  test(r"④ 连打两个撇 f'' ⇒ 整块走", () {
    expect(_deleted(r"f''", 3), r"f''");
  });

  test(r'⑤ 与脚本撇等价：两种写法的删除结果长度相同', () {
    final String? bare = _deleted(r"f_{-}'", 6);
    final String? script = _deleted(r'f_{-}^{\prime}', 14);
    expect(bare, r"f_{-}'");
    expect(script, r'f_{-}^{\prime}');
    expect(bare!.length, 6);
    expect(script!.length, 14);
    // 真正的等价判据：都是"把整个对象删掉"，即删掉之后左边不剩基座。
    expect(bare, startsWith('f'));
    expect(script, startsWith('f'));
  });

  test('⑥ 对照：「甲」与花括号形式都不受影响', () {
    expect(_deleted(r'x_2', 3), r'_2'); // 甲：裸参数只删挂件
    expect(_deleted(r'x_{2}', 5), r'x_{2}'); // 花括号：整块
    expect(_deleted(r'a+b^{2}', 7), r'b^{2}'); // 只删那个对象
  });
}
