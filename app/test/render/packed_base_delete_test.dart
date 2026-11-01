// 反馈 14a（2026-10-30）守卫：**删掉"被包装的基座"不许把对象变成空主体**。
//
// 用户实测（图 14）：组合数/排列数的主体会被单独删掉 ⇒ 剩 `\mathrm{}_{n}^{m}`
//   ⇒ 屏幕上出现一个**虚线框**。用户原话："按道理这里不应该是个框，而应该类似于
//   求和符号积分符号那样的结构主体符号"。
// 口径（切割 §3.1）：`\mathrm{C}_{n}^{m}` = **一个对象**（墨迹 + 挂件），
//   基座被"只换字体的包装"包着时也是基座 ⇒ 与 `x^{2}` 的 `x` 同级 ⇒ 整对象一起走。
//
// 改前必红：①②（改前只删 `C`，留下空主体）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/math_nav.dart';
import 'package:mathlang/render/smart_delete.dart';

String? _deleted(String tex, int rel) {
  final SmartEdit e = smartBackspace(buildCaretSites(tex), rel);
  if (!e.deletes) return null;
  return tex.substring(e.from!, e.to!);
}

/// 正向 Delete 删掉的原文（`null` = 没删）。
String? _deletedFwd(String tex, int rel) {
  final SmartEdit e = smartDelete(buildCaretSites(tex), rel);
  if (!e.deletes) return null;
  return tex.substring(e.from!, e.to!);
}

void main() {
  const String c = r'\mathrm{C}_{n}^{m}'; // len 18

  test('① 对象之后按退格 ⇒ 整个组合数一起走（改前只删 `C`）', () {
    expect(_deleted(c, c.length), c);
  });

  test('② 在 `C` 之后（内容末）按退格 ⇒ 也整块走（否则基座变空）', () {
    expect(_deleted(c, 9), c);
  });

  test('③ 对照：`x^{2}` 行为不变（裸基座本来就整块删）', () {
    expect(_deleted(r'x^{2}', 5), r'x^{2}');
  });

  test('④ 没有挂件的包装不扩：`\\mathrm{C}` 退格只删它自己', () {
    expect(_deleted(r'\mathrm{C}', 9), r'\mathrm{C}');
  });

  test('⑤ 包装里还有别的字符时不扩（不是"唯一内容"）', () {
    // `\mathrm{AB}` 里的 `B` 后面没有挂件 ⇒ 走通则
    expect(_deleted(r'\mathrm{AB}_{n}', 10), 'B');
  });

  // ★★ 2026-11-01（反馈 14b）：14a 只做了**退格**方向，正向 `Delete` 全线漏 ——
  //   探针实测（改前）：`Del` 在 0..8 任意位置都只删 `[8,9)` 那个 `C` ⇒ 空主体。
  test('⑥ 正向 Delete：任意位置都整块走（与 14a 对称）', () {
    for (int rel = 0; rel <= 8; rel++) {
      expect(_deletedFwd(c, rel), c, reason: 'Del@$rel 必须整块走');
    }
  });

  test('⑦ 选区正好是 `C` ⇒ 扩到整个对象（区间删除那条路）', () {
    const String doc = r'$n=\mathrm{C}_{n}^{m}$';
    final int at = doc.indexOf('C');
    final ({int start, int end})? r = expandPackedBaseInDoc(doc, at, at + 1);
    expect(r, isNotNull);
    expect(doc.substring(r!.start, r.end), c);
  });

  test('⑧ 选区本来就是整个对象 ⇒ 不重复扩', () {
    const String doc = r'$n=\mathrm{C}_{n}^{m}$';
    final int at = doc.indexOf(r'\mathrm');
    expect(expandPackedBaseInDoc(doc, at, at + c.length), isNull);
  });

  test(r'⑨ 没有挂件时：选区 C ⇒ 扩到 `\mathrm{C}`（批 36「删空别留幽灵」同一条）', () {
    const String doc = r'$\mathrm{C}$';
    final int at = doc.indexOf('C');
    final ({int start, int end})? r = expandPackedBaseInDoc(doc, at, at + 1);
    expect(r, isNotNull);
    expect(doc.substring(r!.start, r.end), r'\mathrm{C}');
  });

  test('⑩ 选区跨出数学段 ⇒ 不扩', () {
    const String doc = r'$n=\mathrm{C}_{n}^{m}$';
    final int at = doc.indexOf('C');
    expect(expandPackedBaseInDoc(doc, at, doc.length), isNull);
  });
}
