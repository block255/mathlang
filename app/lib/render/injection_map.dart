// 数语引擎 · 「渲染 tex 的偏移」→「原始源码的偏移」（点击定位的换算）
//
// ★ 为什么必须有这个文件（2026-10-14 用户实测，分两轮才定位干净）：
//   点击定位 `hitTestMathTex` 的判据是「**引擎叶盒数 == 传入的可见原子数**」，
//   不成立就**静默返回 null**（点不动、也不报错）。两种注入各破坏它一次：
//   ① **空槽占位 `\square`** —— 正常字形，多 1 盒也多 1 原子 ⇒ 命中必须用渲染 tex
//   ② **光标条 `\cursor`** —— 只有 1.5px 宽，被 `leaf_boxes` 的 `kMinLeafWidth = 2.0`
//      过滤掉，可它在原子表里还在 ⇒ 命中表还必须**剔除光标条**
//
// 而**换算**（本文件）不该再靠"数原子"（那在**空槽上没有对应原子**时会落错地方 ——
// 用户实测："点不到灰框/蓝框的位置，进不去空分母"）。改成**按插入串反算**：
//
//   注入只是"往原始 tex 里插入已知常量串" ⇒
//   渲染偏移 r → 原始偏移 = r − (r 之前插入的总长度)
//   若 r 落在某个插入串**内部** ⇒ 直接返回**该插入点**（这正是空槽的偏移）✓
//
// ⚠️ 代价：靠"认出插入串"来反算 ⇒ 用户若在公式里**手写**同样的串会算偏。
//   罕见，且退化是"点偏一格"而不是"点不动"。以后若改成注入方返回插入表，这条即可消除。
//
// **纯 Dart。**

import 'caret_sites.dart';
import 'slot_marks.dart';
import 'visible_atoms.dart';

/// 光标条的原子字面（它**必须**从命中表里剔除，理由见文件头 ②）
const String kCursorAtomText = r'\cursor';

/// **给命中测试用的原子表**：渲染 tex 的原子，但**剔除光标条**。
///
/// 理由见文件头 ②：光标条的盒只有 1.5px 宽会被最小宽度过滤掉，留在表里就永远差 1。
List<VisibleAtom> atomsForHitTest(String renderTex) => <VisibleAtom>[
      for (final VisibleAtom a in lexVisibleAtoms(renderTex))
        if (renderTex.substring(a.start, a.end) != kCursorAtomText) a,
    ];

/// 所有可能被注入的常量串（长串在前，避免短串把长串的一部分也匹配上）
List<String> get _kMarkers => <String>[
      kCursorSplitTex,
      kCurrentSlotTex,
      kEmptySlotTex,
      kCursorTex,
    ];

/// 渲染 tex 的偏移 [renderOffset] → **原始 tex** 的偏移。
///
/// 点在被注入的串内部（占位方框、光标条）时返回**该插入点** —— 于是
/// "点空槽的方框"会落到空槽的偏移上，再经位点吸附就是合法落点 ✓
int renderToSourceOffset(String renderTex, int renderOffset) {
  if (renderOffset <= 0) return 0;
  final List<({int at, int len})> found = <({int at, int len})>[];
  for (final String m in _kMarkers) {
    if (m.isEmpty) continue;
    var i = renderTex.indexOf(m);
    while (i >= 0) {
      found.add((at: i, len: m.length));
      i = renderTex.indexOf(m, i + 1);
    }
  }
  // 丢掉"被更长的匹配完全包住"的那些（否则 `}`+光标+`\text{` 会把里面的光标再算一遍）
  final List<({int at, int len})> ins = <({int at, int len})>[
    for (final ({int at, int len}) a in found)
      if (!found.any((({int at, int len}) b) =>
          b.at <= a.at && b.at + b.len >= a.at + a.len && b.len > a.len))
        a,
  ]..sort((({int at, int len}) a, ({int at, int len}) b) => a.at.compareTo(b.at));

  var shift = 0;
  for (final ({int at, int len}) e in ins) {
    if (renderOffset <= e.at) break;
    if (renderOffset < e.at + e.len) return e.at - shift; // 点在注入串内部 → 插入点
    shift += e.len;
  }
  return renderOffset - shift;
}
