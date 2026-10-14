// 数语引擎 · 「注入后的渲染 tex」→「原始源码」的偏移映射 + 命中原子表
//
// ★ 为什么必须有这个文件（2026-10-14 用户实测抓出，分两轮才定位干净）：
//   点击定位 `hitTestMathTex` 的判据是「**引擎叶盒数 == 传入的可见原子数**」，
//   不成立就**静默返回 null**（点不动、也不报错）。我们有两种注入，各自破坏它一次：
//
//   ① **空槽占位 `\square`** —— 它是个正常字形：**多 1 个盒、也多 1 个原子**
//      ⇒ 只要命中用"原始源码"的原子就没法对齐（第一轮修的就是这个：改用渲染 tex）
//   ② **光标条 `\cursor`** —— 它只有 **1.5px 宽**，而 `leaf_boxes` 的
//      `kMinLeafWidth = 2.0` 会把它的盒**过滤掉**；但它在原子表里**还在**
//      ⇒ 即便两边都用渲染 tex，仍然差 1 → **还是点不动**（第二轮才发现）
//
// 所以命中时要传一张**剔除了光标条的原子表**（见 [atomsForHitTest]），
// 再把命中下标里的**占位原子**减掉，换回原始原子 —— 注入只"插入"不删改，
// 去掉插入的那些之后与原始原子**一一对应**。
//
// **纯 Dart。**

import 'visible_atoms.dart';

/// 光标条的字面（`caret_sites.dart` 的注入串里那一段）
const String kCursorAtomText = r'\cursor';

/// 空槽占位的字面
const String kSlotMarkAtomText = r'\square';

/// **给命中测试用的原子表**：渲染 tex 的原子，但**剔除光标条**。
///
/// 理由见文件头 ②：光标条的盒会被最小宽度过滤掉，留在表里就永远差 1。
/// ⚠️ 已知代价：用户若在公式里**手写** `\cursor`，也会被剔除（罕见，且只是"点偏一格"）。
List<VisibleAtom> atomsForHitTest(String renderTex) => <VisibleAtom>[
      for (final VisibleAtom a in lexVisibleAtoms(renderTex))
        if (renderTex.substring(a.start, a.end) != kCursorAtomText) a,
    ];

/// 命中表（[atomsForHitTest] 的结果）里第 [index] 个原子 → **原始 tex** 的源码偏移。
///
/// [leftHalf] = 点在那个原子的左半（取左边界），否则取右边界（与 `hit_map` 的规则一致）。
/// 返回 `null` = 映射不出来（调用方就当没点到）。
int? sourceOffsetOfHit({
  required String source,
  required String renderTex,
  required List<VisibleAtom> hitAtoms,
  required int index,
  required bool leftHalf,
}) {
  if (index < 0 || index >= hitAtoms.length) return null;
  // 数一数它前面有几个是"我们注入的占位"（光标条已在 hitAtoms 里被剔除，不必算）
  var injectedBefore = 0;
  for (var i = 0; i < index; i++) {
    if (renderTex.substring(hitAtoms[i].start, hitAtoms[i].end) ==
        kSlotMarkAtomText) {
      injectedBefore++;
    }
  }
  final List<VisibleAtom> raw = lexVisibleAtoms(source);
  final int idx = index - injectedBefore;
  if (idx < 0 || idx >= raw.length) return null;
  return leftHalf ? raw[idx].start : raw[idx].end;
}
