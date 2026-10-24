// ★★★ 2026-10-24（批 21）：**行间块的边界竖条归谁** —— 不许出现"两个光标"。
//
// 用户实测（三个行间块挨着的那一段）："我在中间这块点，有时候会出现同时存在两个光标的情况"。
// 真因：**紧挨着的两个行间块**让同一个偏移**同时**属于 A 的"块之后"与 B 的"块之前"
//   ⇒ 两块各画一根竖条。旧判据是 `< / >`（比大小）⇒ 连离得**更远**的空白也同时满足两块。
//
// ★ 边界用的是单元自己认领的区间 `acceptFrom` / `acceptTo`（不是 `renderBase ± 1`）：
//   行间块认领的是**整片源码**（`$$` 围栏与行尾都算，见文档里 ③-C 那条），
//   所以"块前/块后"那两格就是 `acceptFrom` / `acceptTo`。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/editor/doc_view.dart';

void main() {
  // 一个行间块认领 [11, 22]：11 = 块前那一格，22 = 块后那一格
  const int acceptFrom = 11;
  const int acceptTo = 22;

  test('★ 紧贴块的两格：各归本块（不多不少）', () {
    final ({bool before, bool after}) b = blockEdgeClaim(
        caret: acceptFrom,
        acceptFrom: acceptFrom,
        acceptTo: acceptTo,
        sharesLeftCell: false);
    expect(b.before, isTrue);
    expect(b.after, isFalse);

    final ({bool before, bool after}) a = blockEdgeClaim(
        caret: acceptTo,
        acceptFrom: acceptFrom,
        acceptTo: acceptTo,
        sharesLeftCell: false);
    expect(a.after, isTrue);
    expect(a.before, isFalse);
  });

  test('★★ 共享那一格（左邻是另一块）⇒ 本块不画"块之前"（让给左边那块）', () {
    final ({bool before, bool after}) shared = blockEdgeClaim(
        caret: acceptFrom,
        acceptFrom: acceptFrom,
        acceptTo: acceptTo,
        sharesLeftCell: true);
    expect(shared.before, isFalse, reason: '改前：两块各画一根 ⇒ 屏幕两根光标');
    expect(shared.after, isFalse);
  });

  test('★ 离得**远**的空白（既不相邻也不共享）⇒ 两块都不画', () {
    // 旧判据（`caret > end` / `caret < start`）在这里会**同时**为真 ⇒ 两根竖条
    for (final int caret in <int>[acceptFrom - 3, acceptTo + 3]) {
      final ({bool before, bool after}) c = blockEdgeClaim(
          caret: caret,
          acceptFrom: acceptFrom,
          acceptTo: acceptTo,
          sharesLeftCell: false);
      expect(c.before || c.after, isFalse, reason: 'caret=$caret');
    }
  });

  test('★ 块内（`acceptFrom < caret < acceptTo`）⇒ 走数学层，不画边界条', () {
    for (final int caret in <int>[acceptFrom + 1, acceptTo - 1]) {
      final ({bool before, bool after}) c = blockEdgeClaim(
          caret: caret,
          acceptFrom: acceptFrom,
          acceptTo: acceptTo,
          sharesLeftCell: false);
      expect(c.before || c.after, isFalse, reason: 'caret=$caret');
    }
  });

  test('★★ 共享那一格**只有一个块画光标**（用户：点两个分段中间出现两根）', () {
    // A 的 acceptTo = B 的 acceptFrom = 同一个偏移 ⇒ 两块都认领 ⇒ 两个 MathWithCaret 都 showCaret
    expect(
        blockShowsCaret(
            caret: acceptFrom,
            acceptFrom: acceptFrom,
            acceptTo: acceptTo,
            sharesLeftCell: true),
        isFalse,
        reason: '共享格让给左边那块 ⇒ 本块不画（改前：两块都画 ⇒ 屏幕两根光标）');
    // 左邻不是行间块 / 光标不在那一格 ⇒ 照常画
    expect(
        blockShowsCaret(
            caret: acceptFrom,
            acceptFrom: acceptFrom,
            acceptTo: acceptTo,
            sharesLeftCell: false),
        isTrue);
    expect(
        blockShowsCaret(
            caret: acceptTo,
            acceptFrom: acceptFrom,
            acceptTo: acceptTo,
            sharesLeftCell: true),
        isTrue,
        reason: '共享的是"块之前"，"块之后"不受影响');
    expect(
        blockShowsCaret(
            caret: null,
            acceptFrom: acceptFrom,
            acceptTo: acceptTo,
            sharesLeftCell: true),
        isFalse);
  });

  // ★★★ 批 25：**光标不在这块的区间里 ⇒ 一律 false**（改前的判据只判 `caret != null`，
  //   于是文档里只要有一个光标，每个公式块的 showCaret 都是 true）。
  test('★★ 光标**不在**本块区间 ⇒ 不画（区间判据，批 25）', () {
    for (final int caret in <int>[acceptFrom - 1, acceptTo + 1, 0, 999]) {
      expect(
          blockShowsCaret(
              caret: caret,
              acceptFrom: acceptFrom,
              acceptTo: acceptTo,
              sharesLeftCell: false),
          isFalse,
          reason: 'caret=$caret 在本块 [11,22] 之外');
    }
    // 闭区间两端仍归本块（块之前 / 块之后那两格，③-C 定的口径）
    expect(
        blockShowsCaret(
            caret: acceptFrom,
            acceptFrom: acceptFrom,
            acceptTo: acceptTo,
            sharesLeftCell: false),
        isTrue);
    expect(
        blockShowsCaret(
            caret: acceptTo,
            acceptFrom: acceptFrom,
            acceptTo: acceptTo,
            sharesLeftCell: false),
        isTrue);
    // 区间内部照常
    expect(
        blockShowsCaret(
            caret: acceptFrom + 5,
            acceptFrom: acceptFrom,
            acceptTo: acceptTo,
            sharesLeftCell: true),
        isTrue,
        reason: '共享规则只影响 acceptFrom 那一格');
  });
}
