// B（2026-11-01，用户实测）：**基座是裸组时，"对象之后"退格要整块走**。
//
// 现场：`{f^{\prime}}_{+}` 的"对象之后"按退格 ⇒ 只删掉组里的 `\prime`，留下 `{f^{}}_{+}`
//   （同一族的 `{f^{2}}_{+}` 只删 `2`、`{f}_{+}` 只删 `f`）。
//
// 根因（2026-11-01 16:4x 探针坐实，行为场 + 区域表）：
//   ① "对象之后"先由 `_attachmentEdgeAt` 退到**挂件起点**（`smart_delete.dart` §4.0' 那一支）；
//   ② 在那一格，`_objectLeftOf` 把**裸组**当"透明包装"，返回组里**最后一个原子**；
//   ③ 于是删的是 `\prime`，不是"基座 + 全部挂件"。
//   探针证据：`backspace@16` 与 `backspace@12` 是**同一段** ⇒ 走的就是这条递归；
//   区域表显示 16 那一格的 innermost region 仍是外层 `[0,16)`，`path` 为空 ——
//   所以不是 A 的前置条件（`path.isEmpty`）挡住了，是"透明包装"那一支抢先。
//
// 修法（一行判据）：透明包装分支加"**后面没跟脚本**"——裸组后面紧跟 `^`/`_` 时，
//   它是**某个对象的基座**，要按 §4.0 取"基座 + 紧跟的脚本"整块。
//
// 改前必红：①②③④⑧（改前分别是 `\prime` / `2` / `f` / `\prime` / `x`）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/smart_delete.dart';

/// 退格删掉的原文（`null` = 没删）。
String? _deleted(String tex, int rel) {
  final SmartEdit e = smartBackspace(buildCaretSites(tex), rel);
  if (!e.deletes) return null;
  return tex.substring(e.from!, e.to!);
}

void main() {
  const String gPrime = r'{f^{\prime}}_{+}'; // 组基座 + 撇 + 下标
  const String gSquare = r'{f^{2}}_{+}'; // 组基座 + 数字上标 + 下标
  const String gPlain = r'{f}_{+}'; // 组基座 + 只有下标
  const String bare = r'f^{\prime}_{+}'; // 对照：裸基座（A 已覆盖）

  test('① 组基座 + 撇 + 下标：「对象之后」退格 ⇒ 整块走', () {
    expect(_deleted(gPrime, gPrime.length), gPrime);
  });

  test('② 组基座 + 数字上标：「对象之后」退格 ⇒ 整块走', () {
    expect(_deleted(gSquare, gSquare.length), gSquare);
  });

  test('③ 组基座 + 只有下标：「对象之后」退格 ⇒ 整块走', () {
    expect(_deleted(gPlain, gPlain.length), gPlain);
  });

  test('④ 粘合位点（基座与 `_` 之间）与「对象之后」同结果', () {
    // gPrime 里 `_` 在 12；裸基座 `f^{\prime}_{+}` 的同一格（10）已经是整块，
    // 组基座这一格必须对齐（平权：基座形态不影响手感）。
    expect(_deleted(gPrime, 12), _deleted(gPrime, gPrime.length));
    expect(_deleted(gPrime, 12), gPrime);
  });

  test(r'⑤ 对照：裸基座 f^{\prime}_{+} 仍然整块（A 不回退）', () {
    expect(_deleted(bare, bare.length), bare);
  });

  test(r'⑥ 对照：花括号形式 x_{2} 整块；裸参数 x_2 只删挂件（「甲」）', () {
    expect(_deleted(r'x_{2}', 5), r'x_{2}');
    expect(_deleted(r'x_2', 3), r'_2');
  });

  test('⑦ 对照：没有挂件的裸组仍然逐字删（透明包装不变）', () {
    expect(_deleted(r'{ab}', 4), 'b');
  });

  test(r'⑧ 组对象后面还有内容时，只删那个对象（改前只删组里的 x）', () {
    expect(_deleted(r'{x}^{2}+1', 7), r'{x}^{2}');
  });
}
