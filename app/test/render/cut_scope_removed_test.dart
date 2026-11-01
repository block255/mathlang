// 反馈 3（2026-10-30 · 口径 §3.1–3.2）守卫：**切割只看墨迹/挂件/显式成对边界**。
//
// 用户实测（改前）：`\lim_{x\to0}\frac{D(x)-1}{x}w` 在 `w` 后按一次退格 ⇒ **删掉 30 个字符**
//   （整条 `\lim…w`）；用户原话：「不应该是点一次删 w、一次删分式、一次删极限符号吗」。
// 口径（2026-11-01 用户拍板）：「算子的操作对象到哪儿结束」是**语义推断**（画不出边界）
//   ⇒ 不许当整体；「整体」只由选区产生（双击 / 三击 / 拖选）。
//
// 改前必红：第 1 条（一次删掉 `\lim…w` 整条）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/smart_delete.dart';

String? _deleted(String tex, int rel) {
  final SmartEdit e = smartBackspace(buildCaretSites(tex), rel);
  if (!e.deletes) return null;
  return tex.substring(e.from!, e.to!);
}

void main() {
  test(r'① `\lim…\frac{}{}w` 在 `w` 后 ⇒ 只删 `w`', () {
    const String tex = r'\lim_{x\to0}\frac{D(x)-1}{x}w';
    expect(_deleted(tex, tex.length), 'w',
        reason: '改前删的是整条 `\\lim…w`（30 个字符）');
  });

  test(r'② 再退一格（`w` 已删）⇒ 删整个分式（它有分数线 = 看得见的边界）', () {
    const String tex = r'\lim_{x\to0}\frac{D(x)-1}{x}';
    expect(_deleted(tex, tex.length), r'\frac{D(x)-1}{x}');
  });

  test(r'③ 再退一格（分式已删）⇒ 删 `\lim_{x\to0}`（字形 + 它的下限 = 一个对象）', () {
    const String tex = r'\lim_{x\to0}';
    expect(_deleted(tex, tex.length), tex);
  });

  test(r'④ `\sin 2x` ⇒ 只删 `x`（`sin` 不是整体：三字母就是三个原子）', () {
    const String tex = r'\sin 2x';
    expect(_deleted(tex, tex.length), 'x');
  });
}
