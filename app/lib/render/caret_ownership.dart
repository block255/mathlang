// 数语引擎 · 光标归属（「光标画在哪」的**唯一**判据）
//
// ============================ 为什么要有这个文件 ============================
// 2026-10-15，用户实测：「粘贴 `$\frac{}{}$` 直接消失了」（连光标一起消失）。
// 查下来根因不是某个功能坏了，而是**同一件事有四份判据，其中一份是错的**：
//   · `InlineMathText._caretInSegment`   → `c >= absStart && c <= absEnd`
//   · `projection.mathPlaceholderAt`     → 放宽 `slack = 1`
//   · `projection.caretParagraphOffset`  → 只认文字段
//   · `DocView._computeCaretRect`        → 自己又一套
// 其中只有 `_caretInSegment` 那一份**不知道边界要放宽一格**，于是漏出一个洞：
//   **粘贴完光标恰好停在「闭合 `$` 之后那一格」**（`absEnd + 1`）——
//   数学段不认（`c <= absEnd` 为假）、后面又没有文字段 → **谁都不画光标**；
//   而同一个判据还决定要不要注入空槽占位 → 空分数退化成 **3.4 × 10.3 px** 的细线
//   → **公式也"消失"**（实测：`\frac{}{}` 未注入 3.4px，注入占位后 13.2px）。
//
// ★ 教训（写进设计稿）：**同一件事有多份判据时，必然有一份是错的。**
//   所以这里把它收成**一份纯函数**，并用三条**全域不变量**测试锁住
//   （完备 / 归属单调 / 段内偏移合法）—— 逐例测试永远漏得掉"某个偏移没人认领"。
//
// ============================ 一个必须分清的区别 ============================
// ★★ **「画在哪」与「插在哪」是两件事。**
//   · **插入**必须用**精确的那个整数**：`contentEnd`（闭合 `$` 的位置）与
//     `closeEnd`（它之后一格）是**两个不同的插入点** —— 前者把字插进公式里，后者插到公式外。
//   · **画**的位置可以**多对一**：这两个偏移在视觉上都在公式右边缘，都画在那儿。
//   本文件只管「画在哪」；插入点永远是 `DocBuffer.caret` 那个整数，不经过这里。
//
// **纯 Dart，不依赖 Flutter。**

import 'projection.dart';

/// 光标该由**哪个分段**认领、画在**哪个相对位置**。
class CaretPlacement {
  const CaretPlacement({
    required this.segIndex,
    required this.isMath,
    required this.segStart,
    required this.localRel,
    required this.paragraphPos,
  });

  /// 在 `projectInline(source)` 结果里的下标
  final int segIndex;

  /// 认领它的分段是不是数学段
  final bool isMath;

  /// 该分段在 source 里的起点。
  /// · 文字段 = 第一个字的位置
  /// · 数学段 = `tex[0]` 的位置（即**开 `$` 之后**那一格）
  final int segStart;

  /// 段内相对偏移：
  /// · 文字段 → 第几个字（`0..text.length`）：光标条插在这一格
  /// · 数学段 → tex 内的偏移（`0..tex.length`）：交给 `injectCursor(tex, localRel)` 注入
  final int localRel;

  /// 段落坐标（渲染出来的 `Text.rich` 里第几格）。
  /// · 文字段 = 光标条那一格
  /// · 数学段 = **该公式所占的那一格**（与 `projection.mathPlaceholderAt` 同义）
  final int paragraphPos;

  @override
  String toString() => 'CaretPlacement(seg=$segIndex '
      '${isMath ? 'math' : 'text'} start=$segStart local=$localRel para=$paragraphPos)';
}

/// ★★ **唯一入口**：给定一段（一行 / 一段）源码与段内光标偏移，返回**恰好一个**归属。
///
/// 规则（按文档顺序，**先到先得** —— 这保证了唯一性）：
/// | 分段 | 认领的源偏移区间 | 段内相对偏移 |
/// |---|---|---|
/// | 文字段 `[start, start+len)` | `[start, start+len]`（闭区间） | `c - start` |
/// | 数学段（tex 覆盖 `[start, end)`） | **`[start-1, end+1]`** | `(c - start).clamp(0, tex.length)` |
///
/// 数学段两端各多认领一格，理由：
/// · `start-1` = **开 `$` 的位置** = "在公式之前" → 画在公式**左**边缘
/// · `end+1`   = **闭 `$` 之后** = "在公式之后" → 画在公式**右**边缘（夹进 tex 末尾）
/// 这两格**没有任何别的分段会认领**（文字段到 `start-1` 就结束了、下一段从 `end+1` 才开始），
/// 所以补上它们正好把洞堵住，而且不会和别的分段抢。
///
/// 返回 `null` 只有一种情况：**[source] 是空串**。
/// 空行没有渲染物可归属 —— 那是"空行不是一等公民"那个问题（见交接快照 §十二 W3/W4），
/// 本函数**不假装**能解决它，宁可显式返回 null 让调用方知道。
CaretPlacement? caretPlacement(String source, int caretRel) {
  if (source.isEmpty) return null;
  final int c = caretRel.clamp(0, source.length);

  var units = 0;
  final List<ProjectionSegment> segs = projectInline(source);
  for (var i = 0; i < segs.length; i++) {
    final ProjectionSegment s = segs[i];
    if (s.isMath) {
      // 开 `$` 那一格 .. 闭 `$` 之后那一格（两端都夹进 tex 内）
      if (c >= s.start - 1 && c <= s.end + 1) {
        return CaretPlacement(
          segIndex: i,
          isMath: true,
          segStart: s.start,
          localRel: (c - s.start).clamp(0, s.tex.length),
          paragraphPos: units,
        );
      }
      units += 1;
      continue;
    }
    if (c >= s.start && c <= s.end) {
      return CaretPlacement(
        segIndex: i,
        isMath: false,
        segStart: s.start,
        localRel: c - s.start,
        paragraphPos: units + (c - s.start),
      );
    }
    units += s.text.length;
  }
  // 只有畸形输入才会走到这里：非空源码必然至少有一个分段覆盖它。
  return null;
}

/// 便捷判断：这个光标是否由**第 [segIndex] 个分段**认领（且该分段是数学段 / 文字段）。
///
/// 给渲染层用 —— 它遍历分段时只需问这一句，不再自己写区间判据。
bool caretOwnedBy(CaretPlacement? pl, int segIndex, {required bool isMath}) =>
    pl != null && pl.segIndex == segIndex && pl.isMath == isMath;
