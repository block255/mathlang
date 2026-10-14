// 数语引擎 · 「注入后的渲染 tex」→「原始源码」的偏移映射
//
// ★ 为什么必须有这个文件（2026-10-14 用户实测抓出，两处残留同一个根因）：
//   点击定位 `hitTestMathTex` 的判据是「**引擎叶盒数 == 我们的可见原子数**」，
//   而叶盒来自**注入后**的渲染树、原子却是按**原始源码**词法的 —— 只要注入让渲染多出一个盒，
//   数量就不等 → 它**静默返回 null** → **点不回公式里 / 公式内点击失效**。
//   两个注入都会造成这件事：空槽占位（`\square`）与光标条（`\cursor`）。
//
// 根治办法（本文件）：命中测试**也用渲染 tex**（这样两侧天然对得上），
//   再把命中结果里的原子下标**剔除注入原子**换回原始原子 —— 注入只"**插入**"原子、不删改，
//   所以去掉插入的那些之后，剩下的与原始原子**一一对应**。
//
// **纯 Dart。**

import 'visible_atoms.dart';

/// 我们自己注入进渲染 tex 的原子字面（`\square` = 空槽占位、`\cursor` = 光标条）。
///
/// ⚠️ 已知代价：用户如果在公式里**手写** `\square` / `\cursor`，这些原子会被一并剔除，
/// 于是点击落点可能差一格。可接受（罕见，且只是"点偏一格"而不是"点不动"）。
const Set<String> kInjectedAtomTexts = <String>{r'\square', r'\cursor'};

/// 渲染 tex 里第 [renderAtomIndex] 个原子 → **原始 tex** 里的源码偏移。
///
/// [leftHalf] = 点在那个原子的左半（取左边界），否则取右边界（与 `hit_map` 的规则一致）。
/// 返回 `null` = 映射不出来（调用方就当没点到）。
int? sourceOffsetOfRenderAtom({
  required String source,
  required String renderTex,
  required int renderAtomIndex,
  required bool leftHalf,
}) {
  final List<VisibleAtom> render = lexVisibleAtoms(renderTex);
  if (renderAtomIndex < 0 || renderAtomIndex >= render.length) return null;
  var injectedBefore = 0;
  for (var i = 0; i < renderAtomIndex; i++) {
    if (isInjectedAtom(renderTex, render[i])) injectedBefore++;
  }
  final List<VisibleAtom> raw = lexVisibleAtoms(source);
  final int idx = renderAtomIndex - injectedBefore;
  if (idx < 0 || idx >= raw.length) return null;
  return leftHalf ? raw[idx].start : raw[idx].end;
}

/// 这个渲染原子是不是我们注入的
bool isInjectedAtom(String renderTex, VisibleAtom a) =>
    kInjectedAtomTexts.contains(renderTex.substring(a.start, a.end));
