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
// 口径（讨论稿 §五 第 7 条）：**当前对象已是最外层脚本 ⇒ 不再套**。
//   ① 光标所在的最内层槽就是**同种**脚本（`_` 里再按 `_`）⇒ 拒绝；
//   ② 是**另一种**脚本但槽里光标前**什么都没有**（没有基座可挂）⇒ 拒绝
//      （否则会插出 `^{}` 这种"没有基座的脚本" ⇒ `Parser Error`）；
//   ③ 其余一律放行（在分式里、在正文里按上下标都还能用 —— 不许把功能做死）。

import 'caret_sites.dart';

/// 在 [rel] 处再插一个 `^`（[sup]）或 `_` 会不会套娃 / 造出非法脚本。
bool scriptInsertWouldNest(String tex, int rel, {required bool sup}) {
  final int r = rel.clamp(0, tex.length);
  final String mark = sup ? '^' : '_';
  final CaretSiteTable t = buildCaretSites(tex);
  if (t.degraded) return false; // 解析不了 ⇒ 不猜，照旧放行
  final CaretSite s = t.snap(r);
  if (s.path.isEmpty) return false; // 主行（含分式、根号里）⇒ 不管
  final String owner = s.path.last.command;
  if (owner != '^' && owner != '_') return false;
  if (owner == mark) return true; // ① 同种脚本 ⇒ 不再套
  // ② 另一种脚本：槽里光标前必须有东西能当基座
  for (final SlotSpan sp in t.slots) {
    if (sp.path.length != s.path.length) continue;
    if (sp.path.last.label != s.path.last.label) continue;
    if (sp.start <= r && r <= sp.end) {
      return tex.substring(sp.start, r).trim().isEmpty;
    }
  }
  return false;
}
