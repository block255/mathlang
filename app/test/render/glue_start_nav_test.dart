// ★★ 2026-10-24（批 5 · H1）：**从"粘合位点"出发，`→` 不许先走一格"屏幕没动"的位置**
//
// 用户实测：「点 `x` 与 `3` 之间，然后点右箭头，**点两下**才到 `3` 右边，
// 你是不是把 x 后面和 3 前面显示成一样的了」—— 确实一样：
// 粘合位点 `[1]`（`x` 之后）与脚本第一个位点 `[3]`（`3` 之前）**同一根像素**。
//
// 改前实测（探针日志，2026-10-24）：
//   `→ 序列 从 1 出发: [1, 3, 4, 5, 6]`   ← 1→3 屏幕上一点没动
// 改后应当是：`[1, 4, 5, 6]`。
//
// ★ 金表不许漂：从 0 出发的序列仍为 `[0, 3, 4, 5, 6]`（2026-10-15 用户扫出来的口径）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/math_nav.dart';

const String tex = r'x^{3}+1';
const String source = r'$x^{3}+1$';

List<int> sweepForward(int fromRelPattern) {
  final MathRegion r = mathRegionAt(source, 1)!;
  final List<int> out = <int>[];
  int cur = r.contentStart + fromRelPattern;
  out.add(cur - r.contentStart);
  for (var k = 0; k < 8; k++) {
    final int next = nextCaretOffset(source, cur);
    if (next >= r.closeEnd || next == cur) break;
    cur = next;
    out.add(cur - r.contentStart);
  }
  return out;
}

void main() {
  test('★ 位点表：`x^{3}+1` 里 `x` 之后是粘合位点，`3` 之前是普通位点', () {
    final MathRegion r = mathRegionAt(source, 1)!;
    expect(r.tex, tex);
    // 索引表（探针实测）：0 / 1(glue) / 3 / 4 / 5 / 6 / 7
    final List<int> stops = <int>[];
    int cur = r.contentStart;
    for (var k = 0; k < 8; k++) {
      stops.add(cur - r.contentStart);
      final int next = nextCaretOffset(source, cur);
      if (next >= r.closeEnd || next == cur) break;
      cur = next;
    }
    expect(stops, <int>[0, 3, 4, 5, 6], reason: '金表：从 0 出发的 `→` 序列不许漂');
  });

  test('★★ H1：从粘合位点 `[1]` 出发，一下就到 `3` 右边（4），不再停在 3', () {
    final MathRegion r = mathRegionAt(source, 1)!;
    final int from = r.abs(1);
    final int to = nextCaretOffset(source, from);
    expect(to, r.abs(4),
        reason: '改前是 3（与 1 同一根像素，用户说的"点两下"）');
  });

  test('H1 续：粘合位点之后一路照旧（4 → 5 → 6）', () {
    expect(sweepForward(1), <int>[1, 4, 5, 6]);
  });

  test('H1 反例：从普通位点出发的行为一点没变（0 / 3 / 4）', () {
    expect(sweepForward(0), <int>[0, 3, 4, 5, 6]);
    expect(sweepForward(3), <int>[3, 4, 5, 6]);
    expect(sweepForward(4), <int>[4, 5, 6]);
  });

  test('★ 挂件里"点进去改"仍然可以：`→` 从 3 出发照旧走向 4（没被吃掉）', () {
    final MathRegion r = mathRegionAt(source, 1)!;
    expect(nextCaretOffset(source, r.abs(3)), r.abs(4));
  });
}
