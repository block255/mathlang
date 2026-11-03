// 反馈 7（2026-10-30）· **再插一次上下标会不会"套娃"** 的判据。
//
// 用户实测两条：
//   · `f` 后面**连点两次**面板的「下标」⇒ `f_{_{}}`（公式不完整）；
//   · 连按快捷键下标 ⇒ `f` 和框**越来越小、越来越往下**（每套一层降一档字号）。
//
// 根因：两条入口（`EditView.insertScript` 与面板 `insertSymbolTex`）都只看
//   "整段里前面有没有基座"（`_hasBaseAtom`，注释里本就记着这条是错的），
//   **不看光标是不是已经站在某个脚本槽里** ⇒ 第二次在槽里再插一个 `_{}`。
//
// ★★★ 2026-11-04（用户反馈 A3："打不出指数的指数 / 下标的下标"）——**判据改口径**：
//
//   旧口径（2026-10-30）：① 光标所在的最内层槽是同种脚本 ⇒ **一律拒绝**。
//   ⇒ 把合法的嵌套也挡死了：`$x^{y}$` 里光标在 `y` 之后按 `^`，文档**一个字符都不变**；
//     而 `x^{y^{2}}` 在 TeX 里完全合法（基座 = `y`）。
//
//   新口径（只有一条）：
//     · 光标所在的最内层**脚本槽**里、光标之前**有可见内容** ⇒ 那是基座 ⇒ **放行**
//       （`x^{y|}` + `^` ⇒ `x^{y^{2}}`；`f_{x|}` + `_` ⇒ `f_{x_{2}}`）；
//     · 槽里**空**（光标前什么都没有）⇒ **拒绝** —— 否则会插出"没有基座的脚本"
//       （`x^{|}` + `^` ⇒ `x^{^{}}`，KaTeX 直接 `Parser Error`）。
//
//   ⇒ "同种 / 不同种"这个区分**不再参与判断**：能不能套，只看**有没有基座**。
//   ⇒ 想给"整个 `x^{2}`"再加一层指数，把光标移到 `}` 之后按（那才是对象层）。
//   （旧口径里"期望作用于整个对象"的那条反馈，被 2026-11-03 的"要能套"取代：
//     同一个动作按**光标所在层**决定语义 —— 顶层无墙、内部有层。）

import 'caret_sites.dart';

/// 在 [rel] 处再插一个 `^`（[sup]）或 `_` 会不会套娃 / 造出非法脚本。
bool scriptInsertWouldNest(String tex, int rel, {required bool sup}) {
  final int r = rel.clamp(0, tex.length);
  final CaretSiteTable t = buildCaretSites(tex);
  if (t.degraded) return false; // 解析不了 ⇒ 不猜，照旧放行
  final CaretSite s = t.snap(r);
  if (s.path.isEmpty) return false; // 主行（含分式、根号里）⇒ 不管
  final String owner = s.path.last.command;
  if (owner != '^' && owner != '_') return false;
  // 只挡"空槽"：槽里光标前有内容 ⇒ 那就是基座，允许再套一层。
  return !scriptSlotHasBase(tex, r);
}

/// 光标 [rel] 所在的最内层**脚本槽**里，光标之前**有没有可见内容（基座）**。
///
/// 没有脚本槽 / 解析失败 ⇒ `false`（"没有基座"）。
/// ★ 供 `script_nest`（面板 / 快捷键 / 打字三条入口）与
///   `insert_guard`（纯脚本载荷不许落在"空脚本槽末尾"那条）**共用同一判据**。
bool scriptSlotHasBase(String tex, int rel) {
  final int r = rel.clamp(0, tex.length);
  final CaretSiteTable t = buildCaretSites(tex);
  if (t.degraded) return false;
  for (final SlotSpan sp in t.slots) {
    if (sp.path.isEmpty) continue;
    final SlotStep last = sp.path.last;
    if (last.command != '^' && last.command != '_') continue;
    if (sp.start <= r && r <= sp.end) {
      return tex.substring(sp.start, r).trim().isNotEmpty;
    }
  }
  return false;
}
