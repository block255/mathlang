// 数语引擎 · **结构几何**（《编辑地基与手感》六张地基表的第 6 张 · ② 组）
//
// 回答一个问题：**结构 / 空槽 / 公式在屏幕上占哪块矩形**。
//
// ─────────────────────────────────────────────────────────────
// ★★ 三批探针（2026-10-15 晚，数据见 `_cache\probe_structure.log` / `probe2.log` / `probe3.log`）
//    推翻了三个"看起来显然"的方案，别再把它们想回来：
//
//   ① **"按节点类型配对"（第 k 个 `_FracPos` ↔ 第 k 个 `\frac`）不成立** ——
//      同一个源码结构在不同 `MathStyle` 下落在**不同节点**：
//        `\sum_{i=1}^{n}a_i`  display → `RenderRelativeWidthColumn`（上下限在正上/正下）
//                             text    → `RenderCustomLayout<_ScriptPos>`
//      `\lim` / `\max` 两种样式都是 `RelativeWidthColumn`；`\int_a^b` 两种都是 `_ScriptPos`。
//   ② **源码里 `^`/`_` 的个数 ≠ `_ScriptPos` 个数**：`\sum_{i=1}^{n}a_i` 源码 3 个脚本、
//      display 只 1 个 `_ScriptPos`（上下限折进了算子那个节点）⇒ 必须先把
//      **"算子的上下限折进算子"**，再谈对齐。
//   ③ **accent 与 display 模式的 limits 算子共用 `RenderRelativeWidthColumn`** ⇒
//      类型分不开两族，**必须靠源码侧的结构种类**来认。
//
//   ⇒ 于是对齐规则是：**源码侧的结构对象（前序）↔ 渲染侧的结构承载节点（前序）**，
//      **按位置 zip**（不是按类型查表、也不是按偏移换算），并**断言数量相等 + 类型相容**。
//
// ─────────────────────────────────────────────────────────────
// 渲染侧的结构承载节点名单（三批探针实测；**不在这里做二次判断**）：
//
//   | 源码结构 | 渲染节点 | 盒的语义 |
//   |---|---|---|
//   | 分式族 | `RenderCustomLayout<_FracPos>` | 整个分式（含分数线与 2×1.9 内边距） |
//   | 根号 | `RenderCustomLayout<_SqrtPos>` | 整个根号（含勾、横线、次数槽、尾垫） |
//   | 脚本 | `RenderCustomLayout<_ScriptPos>` | 基座 + 该基座上的全部脚本 |
//   | accent（两族都算） | `RenderRelativeWidthColumn` | 装饰 + 内容 |
//   | 带上下限的算子 | `RenderRelativeWidthColumn` / `_ScriptPos`（随样式） | **算子 + 它自己的上下限**（不含被作用的内容） |
//   | 环境 | `RenderEqnArray` / `RenderCustomLayout<int>` | 整个环境（不含 `\left` 的括号） |
//
//   ⚠️ **不在这张名单里的**（都是**装饰 / 定界符**，不是结构）：
//     · `_RenderLayoutBuilderPreserveBaseline` —— 根号那张矢量图、`\left(` `\right)` 的括号、
//       `cases` 的大括号、`pmatrix` 的两侧括号都走它（实测：`\sqrt{2}` 的节点表里
//       除了 `_SqrtPos` 还有 1 个它 ⇒ 早期把它当结构会让"数量相等"假失败）
//     · `RenderFittedBox` —— 装饰矢量图的缩放壳（内层 `RenderPictureVectorGraphic` 是 2133×1080，
//       被它缩到真实尺寸；**失真的只是内层**，所以几何一律取外壳）
//
// ─────────────────────────────────────────────────────────────
// **纯 Dart 的只有 `structureObjectsFor`**；其余要一个已布局的渲染子树（`RenderObject`）。
// 矩形一律是 **Math 根盒的局部坐标**（调用方自己加根盒的全局偏移）。

import 'package:flutter/rendering.dart';

import 'caret_sites.dart';
import 'injection_map.dart';
import 'leaf_boxes.dart';
import 'scope_table.dart';
import 'visible_atoms.dart';

/// 结构对象的种类。
enum StructureKind {
  /// 分式族（`\frac` `\binom` …）
  frac,

  /// 根号（含可选次数槽）
  sqrt,

  /// 脚本（一个基座上的 `^` / `_` 全体 —— `x_i^2` 是**一个**对象）
  script,

  /// accent（拉伸族 + 定宽族，两族都是"套在基座上的装饰"）
  accent,

  /// 堆叠 / 上下关系（`\overset` `\underset` `\stackrel` `\substack` `\xrightarrow`…）
  /// —— 2026-10-15 晚用语料问出来的：它们**有**结构节点（`RenderRelativeWidthColumn`）。
  stack,

  /// 算子（`\sin` / `\sum` / `\int` / `\lim` …）——**含它自己的上下限与其作用域内容**
  operator,

  /// 多行环境（`\begin{...}`）
  env,
}

/// 一组 accent 命令（与 `smart_delete.kOpaqueCommands` 里的装饰段一致）。
///
/// ★ 这里**不是第二份判据**：`kOpaqueCommands` 管"删除时是不是一个整体"，
///   本表管"渲染上是不是一个带装饰的整体" —— 两组命令**恰好相同**，所以直接复用
///   `isOpaqueItem` 判定，只有本文件需要按 accent 分类时才会用到 [kAccentCommands]。
const Set<String> kAccentCommands = <String>{
  'overline', 'underline', 'vec', 'hat', 'widehat', 'bar', 'dot', 'ddot',
  'tilde', 'widetilde', 'check', 'breve', 'acute', 'grave', 'mathring',
  'overbrace', 'underbrace', 'overbracket', 'underbracket',
  'overrightarrow', 'overleftarrow', 'overleftrightarrow',
  'underrightarrow', 'underleftarrow', 'underleftrightarrow',
  'overgroup', 'undergroup', 'overlinesegment', 'underlinesegment',
};

/// 分式族。
const Set<String> kFracCommands = <String>{
  'frac', 'dfrac', 'tfrac', 'cfrac', 'genfrac',
  'binom', 'dbinom', 'tbinom', 'choose', 'brack', 'brace',
};

/// 堆叠 / 上下关系族 —— **有结构节点**（2026-10-15 晚语料问出来，见 `structure_geometry_test.dart`）。
const Set<String> kStackCommands = <String>{
  'overset', 'underset', 'stackrel', 'substack',
  'xrightarrow', 'xleftarrow', 'xleftrightarrow',
  'xRightarrow', 'xLeftarrow', 'xLeftrightarrow',
};

/// ★ **没有结构节点**的 accent（语料量出来的，别想当然）：
/// `\overbracket` / `\underbracket` 的装饰也是**矢量图**，但引擎**不为它们建
/// `RenderRelativeWidthColumn`** ⇒ 它们的矩形只能靠叶盒并集（本版返回 `null`，
/// 等"一原子多盒"配对修好再补）。
const Set<String> kNodeLessAccents = <String>{
  'overbracket', 'underbracket',
};

/// 源码侧的一个**结构对象**。
class StructureObject {
  const StructureObject({
    required this.kind,
    required this.command,
    required this.start,
    required this.end,
    required this.nodeBacked,
    this.parent,
  });

  final StructureKind kind;

  /// 命令名（**不带反斜杠**）；脚本对象是 `'^'` / `'_'`（哪个先出现就是哪个）
  final String command;

  /// 源码区间 `[start, end)`（绝对偏移，相对该段 tex）
  final int start;
  final int end;

  /// ★ 渲染侧有没有**专属节点** —— 决定矩形是"节点盒"还是"叶盒并集"。
  ///
  /// 实测：分式 / 根号 / 脚本 / accent / 环境 / **带上下限的算子**有（`true`）；
  /// **没有上下限的算子**（`\sin x`）与 `\left…\right` 括号组没有（`false`）。
  final bool nodeBacked;

  /// 最内层的**包含**自己的结构对象（父）；没有就是 `null`（主行层）
  final StructureObject? parent;

  bool contains(int offset) => offset >= start && offset < end;

  bool containsObject(StructureObject o) => o.start >= start && o.end <= end;

  @override
  String toString() => '${kind.name}\\$command[$start,$end)'
      '${nodeBacked ? '' : '（无节点）'}';
}

/// 渲染侧的一个**结构承载节点**。
class StructureNode {
  const StructureNode(this.type, this.rect);

  /// `runtimeType.toString()`（引擎的私有类名，如 `RenderCustomLayout<_FracPos>`）
  final String type;

  /// **Math 根盒局部坐标**
  final Rect rect;

  bool get isFrac => type.contains('_FracPos');
  bool get isSqrt => type.contains('_SqrtPos');
  bool get isScript => type.contains('_ScriptPos');
  bool get isRelativeWidthColumn => type.contains('RelativeWidthColumn');
  bool get isEqnArray => type.contains('EqnArray');
  bool get isGenericCustomLayout =>
      type.contains('CustomLayout') && !type.contains('_');

  @override
  String toString() => '$type $rect';
}

// ---------------------------------------------------------------------------
// 一、源码侧：结构对象表（纯函数）
// ---------------------------------------------------------------------------

/// 枚举 tex 里的**结构对象**（按起点升序；父在子前 —— 源区间包含关系天然保证）。
///
/// ★ **判据全部来自既有地基表**，本函数不新写判据：
///   · 算子与其上下限 / 作用域 → `scope_table.dart: operatorScopes`（§4.7）
///   · 结构命令的区间 → **区域表**（`CaretSiteTable.regions` 的内容项）
///   · 脚本的基座 → 同层内容项里紧邻的前一个
///
/// ⚠️ **为什么不用 `structureUnits`**（2026-10-15 晚探针发现它三个短板）：
///   ① `\sqrt[3]{x}` 的槽起点回退算法不认 `[...]` ⇒ **枚举不到根号**；
///   ② 环境（`\begin{cases}`）同理 ⇒ **枚举不到环境**；
///   ③ 去重键只含"父路径 + 命令 + 行列"、**不含位置** ⇒ 同一层里第二个同种结构被丢掉
///      （`\frac{a}{b}+\frac{c}{d}` 只剩一个）—— 这是 `structureUnits` 自身的既有缺陷
///      （会影响 `normalize` 的回收范围），已单独记账，不在本文件里顺手改。
///
/// 降级位点表（配对失败）⇒ 返回空表：结构树不可靠时，几何也不该猜（§2.3 同理）。
List<StructureObject> structureObjectsFor(String tex) {
  final CaretSiteTable t = buildCaretSites(tex);
  if (t.degraded) return const <StructureObject>[];

  final List<_Draft> drafts = <_Draft>[];

  // ── ① 算子（含它自己的上下限 + 被作用的内容）──────────────────
  final List<OpScope> scopes = operatorScopes(tex);
  for (final OpScope sc in scopes) {
    final int nameEnd = sc.opStart + 1 + sc.command.length; // `\` + 命令名
    drafts.add(_Draft(
      StructureKind.operator,
      sc.command,
      sc.start,
      sc.end,
      // ★ 只有"带上下限"的算子才有专属节点（实测）
      nodeBacked: sc.limitsEnd > nameEnd,
    ));
  }

  /// 这个偏移是不是某个算子**自己的上下限**（要折进算子对象，不单独成对象）
  bool isOperatorLimit(int offset) {
    for (final OpScope sc in scopes) {
      final int nameEnd = sc.opStart + 1 + sc.command.length;
      if (offset >= nameEnd && offset < sc.limitsEnd) return true;
    }
    return false;
  }

  // ── ② 结构命令：走**区域表**（每个区域的内容项就是"同层"的兄弟）──
  for (final TexRegion reg in t.regions) {
    final List<TexItem> items = reg.items;
    for (var i = 0; i < items.length; i++) {
      final TexItem it = items[i];
      final String? cmd = it.command;
      if (cmd == null) continue;

      if (cmd == '^' || cmd == '_') {
        if (isOperatorLimit(it.start)) continue; // 折进算子
        // 同一基座上的**连续**脚本合成一个对象（`x_i^2` → 一个 `_ScriptPos`）
        int end = it.end;
        final int base = i > 0 ? items[i - 1].start : it.start;
        while (i + 1 < items.length &&
            (items[i + 1].command == '^' || items[i + 1].command == '_') &&
            _onlySpace(tex, end, items[i + 1].start)) {
          i++;
          end = items[i].end;
        }
        drafts.add(_Draft(StructureKind.script, cmd, base, end, nodeBacked: true));
        continue;
      }

      final StructureKind? kind = _kindOfCommand(cmd);
      if (kind == null) continue; // 其它不透明命令（`\boxed` `\cancel`…）暂不建对象
      drafts.add(_Draft(kind, cmd, it.start, it.end,
          // ★ 有/无节点是**量出来的**：`\overbracket` / `\underbracket` 没有节点
          nodeBacked: !kNodeLessAccents.contains(cmd)));
    }
  }

  // ── 去重 + 排序 + 补父指针 ─────────────────────────────────
  drafts.sort((_Draft a, _Draft b) => a.start != b.start
      ? a.start.compareTo(b.start)
      : b.end.compareTo(a.end)); // 同起点：**外层在前**（父先于子 = 前序）
  final List<_Draft> uniq = <_Draft>[];
  for (final _Draft d in drafts) {
    if (uniq.any((_Draft u) =>
        u.start == d.start && u.end == d.end && u.kind == d.kind)) {
      continue;
    }
    uniq.add(d);
  }

  final List<StructureObject> out = <StructureObject>[];
  for (final _Draft d in uniq) {
    StructureObject? parent;
    for (final StructureObject o in out) {
      if (o.start <= d.start && o.end >= d.end) {
        if (parent == null || o.end - o.start < parent.end - parent.start) {
          parent = o;
        }
      }
    }
    out.add(StructureObject(
      kind: d.kind,
      command: d.command,
      start: d.start,
      end: d.end,
      nodeBacked: d.nodeBacked,
      parent: parent,
    ));
  }
  return out;
}

/// 命令名 → 结构种类（不在这张表里的命令**不建结构对象**）。
StructureKind? _kindOfCommand(String cmd) {
  if (cmd == 'sqrt') return StructureKind.sqrt;
  if (kFracCommands.contains(cmd)) return StructureKind.frac;
  if (cmd == 'begin') return StructureKind.env;
  if (kAccentCommands.contains(cmd)) return StructureKind.accent;
  if (kStackCommands.contains(cmd)) return StructureKind.stack;
  return null;
}

class _Draft {
  _Draft(this.kind, this.command, this.start, this.end, {required this.nodeBacked});
  final StructureKind kind;
  final String command;
  final int start;
  final int end;
  final bool nodeBacked;
}

/// `[from,to)` 之间只有空白吗？（`to == from` = 紧邻 ⇒ `true`）
bool _onlySpace(String tex, int from, int to) {
  if (to <= from) return true;
  for (var i = from; i < to; i++) {
    if (tex[i] != ' ' && tex[i] != '\n' && tex[i] != '\t') return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// 二、渲染侧：结构承载节点表
// ---------------------------------------------------------------------------

/// 收集渲染子树里的**结构承载节点**（前序）。
///
/// 名单见文件头（`_FracPos` / `_SqrtPos` / `_ScriptPos` / `RelativeWidthColumn` /
/// `EqnArray` / `CustomLayout<int>`）；**装饰与定界符不算**（`_RenderLayoutBuilderPreserveBaseline`、
/// `RenderFittedBox` 都不收）。
List<StructureNode> collectStructureNodes(RenderObject root) {
  final List<StructureNode> out = <StructureNode>[];
  final Rect bounds =
      (root is RenderBox && root.hasSize) ? (Offset.zero & root.size) : Rect.largest;

  void walk(RenderObject o) {
    final String type = o.runtimeType.toString();
    final bool structural = type.contains('CustomLayout') ||
        type.contains('RelativeWidthColumn') ||
        type.contains('EqnArray');
    if (structural && o is RenderBox && o.hasSize) {
      out.add(StructureNode(type, o.localToGlobal(Offset.zero, ancestor: root) & o.size));
    }
    o.visitChildren(walk);
  }

  walk(root);
  // `bounds` 只用于诊断（越界检查），此处显式引用以免"未使用"告警
  assert(bounds.isEmpty || bounds.width >= 0);
  return out;
}

// ---------------------------------------------------------------------------
// 三、对齐 + 矩形
// ---------------------------------------------------------------------------

/// 对齐结果：结构对象表 + 节点表 + 每个对象的矩形。
class StructureGeometry {
  StructureGeometry._({
    required this.objects,
    required this.nodes,
    required this.rects,
    required this.nodeBackedIndexes,
    required this.mismatch,
    required this.diagnostics,
  });

  final List<StructureObject> objects;
  final List<StructureNode> nodes;

  /// 与 [objects] 一一对应的矩形（**Math 根盒局部坐标**）；算不出来的是 `null`
  final List<Rect?> rects;

  /// 第 i 个对象对应的**节点序号**（`-1` = 它没有节点）
  final List<int> nodeBackedIndexes;

  /// `null` = 对齐成功；否则是**诊断串**（数量不等 / 类型不相容）
  final String? mismatch;

  /// 供测试与排查用的补充信息（叶盒并集用到的信息、降级提示等）
  final List<String> diagnostics;

  bool get aligned => mismatch == null;

  Rect? rectAt(int index) => index >= 0 && index < rects.length ? rects[index] : null;

  /// **引擎给的那个盒**（不含叶盒并集）—— 诊断与守卫测试用；没有节点就是 `null`
  Rect? nodeRectAt(int index) {
    if (index < 0 || index >= nodeBackedIndexes.length) return null;
    final int k = nodeBackedIndexes[index];
    return k < 0 || k >= nodes.length ? null : nodes[k].rect;
  }

  /// 覆盖某个**源偏移**的**最内层**结构对象（`null` = 主行层）
  StructureObject? innermostAt(int offset) {
    StructureObject? best;
    for (final StructureObject o in objects) {
      if (!o.contains(offset)) continue;
      if (best == null || (o.end - o.start) < (best.end - best.start)) best = o;
    }
    return best;
  }

  Rect? rectOf(StructureObject o) {
    final int i = objects.indexOf(o);
    return i < 0 ? null : rects[i];
  }

  /// 某个对象的**引擎节点盒**（诊断用）
  Rect? nodeRectOf(StructureObject o) {
    final int i = objects.indexOf(o);
    return i < 0 ? null : nodeRectAt(i);
  }

  @override
  String toString() => 'StructureGeometry(objects=${objects.length}, '
      'nodes=${nodes.length}, aligned=$aligned${mismatch == null ? '' : ' ← $mismatch'})';
}

/// 造结构几何：**源码侧结构对象 ↔ 渲染侧结构节点**，按前序 zip。
///
/// [tex] 是**源空间**的 tex；[renderTex] 是**实际渲染**的那一份（`renderMathTex(...)` 的产物，
/// 即已注入空槽占位 / 尾垫 / 光标锚点）。
/// [mathRoot] 是那个 `Math` 的渲染对象。
///
/// ★ **为什么要 renderTex**：没有专属节点的结构对象（`\sin x`、`\left(…\right)`）
///   只有**叶盒并集**能给出矩形，而叶盒要靠「渲染偏移 → 源偏移」换算（`injection_map`）。
///
/// [includeLeafUnion] 打开时，矩形 = **节点盒 ∪ 区间内叶盒的并集**（默认打开：
/// 数学字形本来就会画出根盒之外，并集才"点得到"；对分式这类有节点的，两者几乎重合）。
StructureGeometry buildStructureGeometry({
  required String tex,
  required String renderTex,
  required RenderObject mathRoot,
  bool includeLeafUnion = true,
}) {
  final List<StructureObject> objects = structureObjectsFor(tex);
  final List<StructureNode> nodes = collectStructureNodes(mathRoot);
  final List<String> diags = <String>[];

  // 叶盒并集（可选）
  List<({int src, Rect rect})> leafUnion = const <({int src, Rect rect})>[];
  if (includeLeafUnion) {
    final LeafBoxScan scan = scanLeafBoxes(mathRoot);
    final List<VisibleAtom> atoms = atomsForHitTest(renderTex);
    if (scan.eligible.length == atoms.length) {
      leafUnion = <({int src, Rect rect})>[
        for (var i = 0; i < atoms.length; i++)
          (src: renderToSourceOffset(renderTex, atoms[i].start), rect: scan.eligible[i].rect),
      ];
    } else {
      diags.add('叶盒 ${scan.eligible.length} ≠ 原子 ${atoms.length} ⇒ 退化为只用节点盒');
    }
  }

  String? mismatch;
  // ★★ 只有 **有专属节点** 的对象才参与"按前序 zip" ——
  //    没有节点的（`\sin x`、`\left…\right`）不能占用节点表的位次，
  //    否则位置全错位（实测：`\lim_{x\to0}\frac{\sin x}{x}` 里 `\sin x` 会把 frac 挤到下一个）。
  final List<int> nodeBacked = <int>[
    for (var i = 0; i < objects.length; i++)
      if (objects[i].nodeBacked) i,
  ];
  if (nodeBacked.length != nodes.length) {
    mismatch = '结构对象（有节点）${nodeBacked.length} ≠ 结构节点 ${nodes.length}'
        '；全部对象 = ${objects.map((StructureObject o) => o.toString()).toList()}';
  } else {
    for (var k = 0; k < nodeBacked.length; k++) {
      final String? why = _typeMismatch(objects[nodeBacked[k]], nodes[k]);
      if (why != null) {
        mismatch = '第 $k 个（源码 ${objects[nodeBacked[k]]}）：$why';
        break;
      }
    }
  }

  final List<Rect?> rects = <Rect?>[];
  for (var i = 0; i < objects.length; i++) {
    final StructureObject o = objects[i];
    final int k = nodeBacked.indexOf(i);
    Rect? r = (mismatch == null && k >= 0) ? nodes[k].rect : null;
    if (includeLeafUnion) {
      for (final ({int src, Rect rect}) e in leafUnion) {
        if (!o.contains(e.src)) continue;
        r = r == null ? e.rect : r.expandToInclude(e.rect);
      }
    }
    rects.add(r);
  }

  // ★★ **自底向上合并**：父的矩形必须**含住子结构的矩形**（P2 包含性）。
  //
  // 为什么不能只靠"父自己的节点盒 ∪ 父区间内的叶盒"：
  //   · 子结构的**节点盒**带内边距（实测 `_ScriptPos` 比字形宽 0.8 px）
  //     ⇒ 父的叶盒并集够不到它；
  //   · 父自己的叶盒并集**可能整个拿不到**（"一原子多盒"配对失败，见 diagnostics）
  //     —— 实测 `\lim_{x\to0}\frac{\sin x}{x}`：父的节点盒只到 x=48，而分式在 50.7..121.2。
  //
  // 倒序遍历：对象表按起点升序 ⇒ 子一定排在父之后（同一层里子结构的起点 ≥ 父的起点）。
  for (var i = objects.length - 1; i >= 0; i--) {
    final StructureObject? p = objects[i].parent;
    if (p == null || rects[i] == null) continue;
    final int pi = objects.indexOf(p);
    if (pi < 0) continue;
    rects[pi] = rects[pi] == null ? rects[i] : rects[pi]!.expandToInclude(rects[i]!);
  }

  return StructureGeometry._(
    objects: objects,
    nodes: nodes,
    rects: rects,
    nodeBackedIndexes: <int>[
      for (var i = 0; i < objects.length; i++) nodeBacked.indexOf(i),
    ],
    mismatch: mismatch,
    diagnostics: diags,
  );
}

/// 类型相容性检查（**守卫**，不是匹配依据 —— 匹配是"按前序位置"）。
String? _typeMismatch(StructureObject o, StructureNode n) {
  switch (o.kind) {
    case StructureKind.frac:
      return n.isFrac ? null : '源码是分式，节点却是 ${n.type}';
    case StructureKind.sqrt:
      return n.isSqrt ? null : '源码是根号，节点却是 ${n.type}';
    case StructureKind.script:
      return n.isScript ? null : '源码是脚本，节点却是 ${n.type}';
    case StructureKind.accent:
      return n.isRelativeWidthColumn ? null : '源码是 accent，节点却是 ${n.type}';
    case StructureKind.stack:
      // `\overset` / `\xrightarrow` → `RelativeWidthColumn`；
      // `\substack` → `RenderCustomLayout<int>`（与矩阵同一类，实测）
      return (n.isRelativeWidthColumn || n.isScript || n.isGenericCustomLayout)
          ? null
          : '源码是堆叠结构，节点却是 ${n.type}';
    case StructureKind.env:
      return (n.isEqnArray || n.isGenericCustomLayout)
          ? null
          : '源码是环境，节点却是 ${n.type}';
    case StructureKind.operator:
      return (n.isRelativeWidthColumn || n.isScript)
          ? null
          : '源码是算子，节点却是 ${n.type}';
  }
}
