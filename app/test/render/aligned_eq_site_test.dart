// ★★★ 2026-10-24（批 19 · F1-a）：`aligned` 的等号**没有独立位**，它属于第 2 列的开头。
//
// 用户 2026-10-23 反馈 F1：「局部输入后，对齐推导等号对不齐」+ 截图四行全左端对齐。
// 真因（探针）：模板 `&=\\&=` 的位点是 `0, 15(&), 16(=), 17(\\), 19(&), 20(=), 21(…)`；
//   `&` **紧跟**的那个 `=`（16 / 20）之前**不是填点** —— 在那里打字，内容会插到 `=` 前头
//   ⇒ 那一行的"左式 / 等号 / 右式"三列错位 ⇒ 各行等号对不齐。
//
// 口径（用户 2026-10-24 拍板「窄口径」）：只让**方向键**跳过 `&=` 的 `=` 之前那一格；
//   点击仍能落（位点保留），与"粘合位点"同一口径。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/env_cells.dart';
import 'package:mathlang/render/math_nav.dart';

const String kTex = r'\begin{aligned}&=\\&=\end{aligned}';
final String kDoc = '${r'$$'}${'\n'}$kTex${'\n'}${r'$$'}';

/// 从内容首开始一路 `→`，返回**段内相对偏移**序列（碰到出公式就停）
List<int> walkForward({int? startRel}) {
  final MathRegion r = mathRegionAt(kDoc, kDoc.indexOf(kTex))!;
  var off = startRel == null ? r.openStart : r.abs(startRel);
  final List<int> seq = <int>[];
  for (var k = 0; k < 40; k++) {
    final int rel = r.rel(off);
    if (rel >= 0) seq.add(rel); // 段首那个 `-3`（开 `$` 之前）不算"内容里的停靠点"
    final int next = nextCaretOffset(kDoc, off);
    if (next <= off) break;
    if (!(next >= r.openStart && next <= r.closeEnd)) break;
    off = next;
  }
  return seq;
}

void main() {
  test(r'★ `→` 序列里**不许出现** `&=` 的 `=` 之前那一格（16 / 20）', () {
    final List<int> seq = walkForward();
    expect(seq.contains(16), isFalse, reason: r'16 = `&` 后那个 `=` 之前（不是填点）：$seq');
    expect(seq.contains(20), isFalse, reason: r'20 = 第二行同一个位置：$seq');
  });

  test(r'★ 但**必须**能停在 `=` 之后（17 / 21）——那才是右格填点', () {
    final List<int> seq = walkForward();
    expect(seq.contains(17), isTrue, reason: r'17 = 第 1 行右格（`=` 之后）：$seq');
    expect(seq.contains(21), isTrue, reason: r'21 = 第 2 行右格：$seq');
  });

  test(r'★ 停靠顺序：左格(15) → 右格(17) → 第二行左格(19) → 第二行右格(21)', () {
    final List<int> seq = walkForward();
    expect(seq.take(6).toList(), <int>[0, 15, 17, 19, 21, 34],
        reason: '实际序列：$seq');
  });

  test(r'★ `←` 对称：从右格(17)退出 ⇒ 直接回左格(15)，不经过 16', () {
    final MathRegion r = mathRegionAt(kDoc, kDoc.indexOf(kTex))!;
    final int back = r.rel(prevCaretOffset(kDoc, r.abs(17)));
    expect(back, 15, reason: '实际=$back');
  });

  test('★ 对照：普通 `a=b` 里等号前后都是合法停靠点（这条规则不许外溢）', () {
    const String doc = r'$a=b$';
    final MathRegion r = mathRegionAt(doc, 1)!;
    final List<int> seq = <int>[];
    var off = r.openStart;
    for (var k = 0; k < 10; k++) {
      seq.add(r.rel(off));
      final int next = nextCaretOffset(doc, off);
      if (next <= off) break;
      if (next < r.openStart || next > r.closeEnd) break;
      off = next;
    }
    expect(seq.contains(1), isTrue, reason: r'`=` 之前仍要停（`a|=`）：$seq');
    expect(seq.contains(2), isTrue, reason: r'`=` 之后仍要停（`a=|b`）：$seq');
  });

  test(r'★★ 点右格 ⇒ 落点要在 `=` **之后**（否则点一下再打字就把 `=` 推走）', () {
    // 用户实测：点"对齐推导右格"落在 `=` 之前，打 `x` 得到 `&x=` ⇒ 内容进第 2 列 ⇒ 等号不齐
    final int? start = envCellOffset(kTex, const EnvCellHit(0, 1, atEnd: false));
    expect(start, 17, reason: r'格(0,1) 的内容是 `=` ⇒ 内容首应为 17（`=` 之后），实际 $start');
    final int? end = envCellOffset(kTex, const EnvCellHit(0, 1, atEnd: true));
    expect(end, 17, reason: '该格 `=` 之后没有内容 ⇒ 末尾也是 17，实际 $end');
    // 左格（真的空）不受影响：内容首仍是 `&` 的位置 15
    expect(envCellOffset(kTex, const EnvCellHit(0, 0, atEnd: false)), 15);
  });

  test(r'★★ 点击落点归一：`&=` 的 `=` 之前 ⇒ 一律挪到 `=` 之后（与方向键一致）', () {
    expect(normalizeAlignedEqOffset(kTex, 16), 17,
        reason: r'改前点这里会停在 `=` 前（与"创建时落点"不一致 ⇒ 同一位置两种行为）');
    expect(normalizeAlignedEqOffset(kTex, 20), 21, reason: '第二行同理');
    for (final int rel in <int>[0, 15, 17, 19, 21, 34]) {
      expect(normalizeAlignedEqOffset(kTex, rel), rel, reason: 'rel=$rel 不该被挪');
    }
  });
}
