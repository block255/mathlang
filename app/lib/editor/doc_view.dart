// 数语引擎 · 文档视图（S2-4 核心）
//
// 结构（由 S2-3 的实测确定，见《技术选型与风险.md》§十二）：
//
//   L0 buf ──parse──> BlockIndex ──> FlowUnit 列表 ──> 单元 widget（**内容寻址缓存**）
//                                        │
//                      ┌─────────────────┴──────────────────┐
//                      ▼                                    ▼
//            ① 离屏测量树（Offstage）              ② 每页渲染树（可见）
//               读 RenderBox 高度                     用上次的分页结果摆位
//                      │                                    ▲
//                      └──> paginate()（纯算法）────────────┘
//
// 三条硬约束（都是实测数据换来的）：
//   1. **单元级 widget 缓存**：源文本没变 → 复用同一实例 → 子树整棵跳过。不做的话空帧就要 91 ms（N=25）。
//   2. **测量树与渲染树各用各的池**：否则两棵树互相挤掉对方的实例，两边每帧都重建。
//   3. **"渲染即测量"**：`Offstage` 测出的高度与真实渲染**完全一致**（0.000 px，25/25），
//      且成本相同 —— 所以测量这一趟不是浪费，它就是布局本身。
//
// 打字时的时序（这是"手感"的关键）：
//   第 N 帧：测量树里只有变化的那个单元重建 → 渲染树里新文字**立刻显示**（页码/分页还是旧的）
//   第 N+1 帧：读到新高度 → 重跑分页 → 页边界落定
// 也就是说**打字零延迟，分页晚一帧**。

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../core/block.dart';
import 'blank_runs.dart';
import '../core/doc_buffer.dart';
import '../core/doc_settings.dart';
import '../layout/page_metrics.dart';
import '../layout/paginator.dart';
import '../render/caret_ownership.dart';
import '../render/caret_sites.dart';
import '../render/empty_math_mark.dart';
import '../render/env_cells.dart';
import '../render/hit_map.dart';
import '../render/inline_math_text.dart';
import '../render/injection_map.dart';
import '../render/leaf_boxes.dart';
import '../render/leaf_pairing.dart';
import '../render/math_caret.dart';
import '../render/math_nav.dart';
import '../render/tex_fixups.dart';
import '../render/projection.dart';
import '../render/slot_marks.dart';
import '../render/structure_geometry.dart';
import 'page_sheet.dart';
import 'unit_pool.dart';

/// **空行槽**（⑥ 丙，2026-10-17）：块与块之间的那段空白，也是**一行空行**。
///
/// 三件事，一件都不能少：
/// ① **版面中性**：高度就是原来那段 `gap`（原来是 `SizedBox(height: gap)`）—— 一个像素都不变；
/// ② **点击能落**：`Listener(behavior: opaque)` 覆盖整段空隙 ⇒ 点空白 = 落在那行空行的位点上；
/// ③ **光标能画**：光标在这行空行上时，自己画那根竖条（文本层标准 `字号×1.25`），
///    用 `OverflowBox` **溢出**画（空隙只有 0.7 字号高，竖条比它高）—— 不撑版面。
class _BlankSlot extends StatefulWidget {
  const _BlankSlot({
    required this.id,
    required this.height,
    required this.offset,
    required this.caretHere,
    required this.caretHeight,
    required this.caretWidth,
    required this.caretColor,
    required this.onTap,
    required this.onBox,
    this.topAligned = false,
    this.lineOffsets = const <int>[],
    this.lineDys = const <double>[],
    this.caretDy,
    this.gapBefore = 0,
    this.lineHeight = 20,
  });

  final String id;
  final double height;

  /// 这行空行的位点（L0 偏移）
  final int offset;

  final bool caretHere;
  final double caretHeight;
  final double caretWidth;
  final Color caretColor;
  final void Function(int at, Offset global) onTap;
  final void Function(String id, RenderBox box) onBox;

  /// 竖条是否**贴顶**（末尾槽占整片剩余空白时，光标要紧贴最后一行下面，不浮在中间）
  final bool topAligned;

  /// ★★ 2026-10-18 晚（§11.46 真修）：这个槽代表的**真空段落里有哪几行**（每行行首偏移）。
  ///
  /// 一个槽可能覆盖 **n 个空行**（用户连按 Enter 出来的）。有了这张表：
  ///   · 点槽里第 k 行 ⇒ 光标落到第 k 行（而不是永远落第一行）；
  ///   · 光标在第 k 行 ⇒ 竖条画在那个行高上（`caretDy`）。
  final List<int> lineOffsets;

  /// ★★ 2026-10-27：每个位置**相对槽顶的纵向偏移**（与 [lineOffsets] 一一对应）。
  ///
  /// 为什么不再用"gapBefore + k × lineHeight"现算：空行串里**第一个**位置只是"段距那一截"
  /// （贴着上一段的行盒底，段内行位置），从第二个起才是整行 —— 一条折线，不是一个等差序列。
  /// 由调用方（`DocViewState._blankDys`）算好，槽只管用：点最近的那一行、按行画光标。
  final List<double> lineDys;

  /// 光标在这一串空行里的**纵向偏移**（`null` ⇒ 光标不在这一段里）
  final double? caretDy;

  /// ★★ 2026-10-18 晚：这段空隙里**属于"段距"的那一截**（下面的部分才是真空段落的一行行）。
  ///
  /// 为什么要有它：`甲` 按 Enter 得到 `甲\n\n`，光标停在**新段的行首**，
  /// 而新段真正落脚的位置是 `甲` 底下**再让开一个段距**。
  /// 原来竖条画在空隙最顶上（`dy = 0`）⇒ 用户看到"光标在这儿、打出来的字却在下面"
  /// （用户实测原话：「字符进入的行跟刚才 enter 后光标到的位置不是一个高度」）。
  /// ⇒ 空行的行盒从 `gapBefore` 起算：**第 k 个空行 = gapBefore + k × lineHeight**。
  final double gapBefore;

  /// 一行的高（点哪一行 ⇒ 按这个换算）
  final double lineHeight;

  @override
  State<_BlankSlot> createState() => _BlankSlotState();
}

class _BlankSlotState extends State<_BlankSlot> {
  @override
  void initState() {
    super.initState();
    _report();
  }

  @override
  void didUpdateWidget(_BlankSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _report();
  }

  void _report() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final RenderObject? ro = context.findRenderObject();
      if (ro is RenderBox && ro.hasSize) widget.onBox(widget.id, ro);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // ★ `opaque`：这个盒子**没有孩子**（只有空行），必须靠 behavior 自己接住点击
      behavior: HitTestBehavior.opaque,
      // ★★ 2026-10-18 晚：有"行表"时按**点在第几行**落点（一个槽可能是好几个空行）；
      //   没有行表（文末槽、旧调用）就照旧落到 `offset`。
      // ★★★ 批 45（2026-10-26，调试日志实证）：**必须在 `onTapDown`（按下）上报**。
      //   日志现场：点空行 → 点正文那一击被打成 `[tap] DEDUP丢弃 off=5`。
      //   根因：`EditView` 的去重标记 `_tapHandledThisPress` 在**指针抬起**（`_endDrag`）复位；
      //   而槽原来用 `onTap`（抬起**之后**才跑）⇒ 它把标记又置 true 却没有下一次抬起来复位
      //   ⇒ **下一次按下的第一条上报被吞掉** ⇒ 光标不动（用户："第一下换行无效"）。
      //   单元（文字/公式）本来就在 `onTapDown` 上报 —— 槽与它们统一。
      onTapDown: (TapDownDetails d) {
        final RenderBox? box = context.findRenderObject() as RenderBox?;
        if (widget.lineOffsets.isEmpty || box == null || !box.hasSize) {
          widget.onTap(widget.offset, d.globalPosition);
          return;
        }
        final double dy = box.globalToLocal(d.globalPosition).dy;
        if (widget.lineDys.length == widget.lineOffsets.length &&
            widget.lineDys.isNotEmpty) {
          // ★ 2026-10-27：**点最近的那一行**（表由调用方算好，槽不再自己推算几何）
          var best = 0;
          var bestD = double.infinity;
          for (var i = 0; i < widget.lineDys.length; i++) {
            final double dd = (widget.lineDys[i] - dy).abs();
            if (dd < bestD) {
              bestD = dd;
              best = i;
            }
          }
          widget.onTap(widget.lineOffsets[best], d.globalPosition);
          return;
        }
        // ★ 空行的行盒从 `gapBefore` 起算（上面那截是段距，不算"某一行"）
        final double rel = dy - widget.gapBefore;
        final int k = rel <= 0 ? 0 : (rel / widget.lineHeight).floor();
        final int i = k.clamp(0, widget.lineOffsets.length - 1);
        widget.onTap(widget.lineOffsets[i], d.globalPosition);
      },
      onTap: null,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: widget.caretHere
              ? (widget.caretDy != null
                  // ★ 有明确的行内偏移（多个空行 / 文末槽）⇒ 贴左上 + 下移 dy
                  ? Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: EdgeInsets.only(top: widget.caretDy!),
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: 0,
                          maxWidth: widget.caretWidth * 4,
                          minHeight: 0,
                          maxHeight: widget.caretHeight,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Container(
                              width: widget.caretWidth,
                              height: widget.caretHeight,
                              color: widget.caretColor,
                            ),
                          ),
                        ),
                      ),
                    )
                  // 单个空行（段距）：保持原样（贴顶 / 居中），一个像素都不动
                  : Align(
                      alignment: widget.topAligned
                          ? Alignment.topLeft
                          : Alignment.centerLeft,
                      child: OverflowBox(
                        alignment: widget.topAligned
                            ? Alignment.topLeft
                            : Alignment.centerLeft,
                        minWidth: 0,
                        maxWidth: widget.caretWidth * 4,
                        minHeight: 0,
                        maxHeight: widget.caretHeight,
                        child: Container(
                          width: widget.caretWidth,
                          height: widget.caretHeight,
                          color: widget.caretColor,
                        ),
                      ),
                    ))
              : null,
        ),
      ),
    );
  }
}

/// 渲染树里的「命中盒」：把点击的**全局坐标**交回给调用方。
///
/// ★ 用自己的 `BuildContext` 取渲染对象 → **不需要 GlobalKey**
/// （光标/内容会在单元之间迁移，同一个 GlobalKey 在同一帧里跨位置迁移会直接抛
/// "Multiple widgets used the same GlobalKey"；用 context 就没这个问题）。
class _UnitHitBox extends StatefulWidget {
  const _UnitHitBox({
    required this.unit,
    required this.onHit,
    this.onBox,
    required this.child,
  });

  final _Unit unit;
  final void Function(_Unit unit, BuildContext ctx, Offset global) onHit;

  /// 帧末把自己在渲染树里的盒子报回去（**给光标定位用**，见 `DocView._computeCaretRect`）
  final void Function(_Unit unit, RenderBox box)? onBox;
  final Widget child;

  @override
  State<_UnitHitBox> createState() => _UnitHitBoxState();
}

class _UnitHitBoxState extends State<_UnitHitBox> {
  @override
  void initState() {
    super.initState();
    _report();
  }

  @override
  void didUpdateWidget(_UnitHitBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    _report();
  }

  void _report() {
    final void Function(_Unit, RenderBox)? cb = widget.onBox;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final RenderObject? ro = context.findRenderObject();
      if (ro is RenderBox && ro.hasSize) cb(widget.unit, ro);
    });
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        // 文本区要给"工"字形光标（用户实测：没有它手感很怪）—— 数学区由 InlineMathText 自己设
        cursor: SystemMouseCursors.text,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (PointerDownEvent e) =>
              widget.onHit(widget.unit, context, e.position),
          // ★★ ③-A（《编辑地基与手感》§7.3）：**命中盒一律铺满文本栏**，与块类型无关。
          //   实测（《位点与结构导航》§11.25 第五轮）：列表项因为 `Row[标记, Expanded(内容)]`
          //   命中盒是满栏宽 ⇒ 点"行末之后的空白"会夹到**行末**；而标题 / 普通段落只有**内容宽**
          //   ⇒ 同一列**落空**。同一段文字因块类型不同而地位不同 —— 这是实现细节泄漏，必须消除。
          //   `Align`（**松约束**）只把**命中盒**撑满文本栏 —— ★ 必须用松约束：
          //   紧约束的 `SizedBox(width: ∞)` 会把子节点也定宽，段落尺寸就不再随内容变化
          //   （实测踩到：`edit_view_test` 那条"拼音接进排版 ⇒ 段落宽度增大"当场变红）。
          //   子节点是**池里缓存的同一实例** → 这层包装不破坏"整棵子树跳过"
          child: Align(
            alignment: Alignment.centerLeft,
            child: widget.child,
          ),
        ),
      );
}

/// 「渲染文本 + 它在**原始切片**里的起点」。
///
/// S3-2 的关键：原始切片与渲染文本之间隔着"被剥掉的标记"（标题的 `# `、列表的 `- `、
/// 公式块的 `$$` 围栏……）。光标偏移必须按 `renderBase` 补偿，否则整体偏掉几格。
class _Rendered {
  const _Rendered(this.text, this.offsetInSource);
  final String text;
  final int offsetInSource;
}

/// 一个 FlowUnit 的解析结果。
class _Unit {
  _Unit({
    required this.id,
    required this.contentKey,
    required this.type,
    required this.source,
    required this.blockIndex,
    required this.isFirstInBlock,
    required this.breakBefore,
    required this.label,
    required this.renderBase,
    required this.renderLength,
    int? acceptFrom,
    int? acceptTo,
  })  : acceptFrom = acceptFrom ?? renderBase,
        acceptTo = acceptTo ?? (renderBase + renderLength);

  /// 位置标识（分页结果回指用）
  final String id;

  /// 内容键（内容变了才变 → 插入内容不会让后面的单元失效）
  final String contentKey;

  final BlockType type;

  /// 该单元的**原始切片**（L0 里从第一行到最后一行的原文，含行首标记）
  final String source;

  final int blockIndex;
  final bool isFirstInBlock;
  final bool breakBefore;
  final String label;

  /// ★ S3-2：**渲染文本首字符在 L0 里的绝对偏移**
  /// （原始切片与渲染文本之间隔着"剥掉的标记"，如标题的 `# `、列表的 `- `）
  final int renderBase;

  /// 渲染文本的长度（≠ `source.length`，因为标记被剥掉了）
  final int renderLength;

  /// 该单元**愿意接收光标**的绝对区间（默认 = 自己的渲染区间）。
  /// 列表项的标记区（`- `）划进来 → 光标在标记里也显示在本单元开头。
  final int acceptFrom;
  final int acceptTo;

  int get renderEnd => renderBase + renderLength;

  /// 光标在本单元时给出**相对渲染文本**的偏移；不在则 null。
  int? relFor(int? caret) {
    if (caret == null) return null;
    if (caret < acceptFrom || caret > acceptTo) return null;
    return (caret - renderBase).clamp(0, renderLength);
  }
}

/// ★★★ 2026-10-24（批 21）：**行间块的边界竖条归谁**（`before` / `after` 各一格）。
///
/// 用户实测「有时候同时存在两个光标」：两个**紧挨着**的行间块（中间只有一个 `\n`）
/// 让同一个偏移**同时**属于 A 的"块之后"（`base + length`）与 B 的"块之前"（`base - 1`）
/// ⇒ 两块各画一根竖条 ⇒ 屏幕上两根光标。
///
/// 口径：
///   ① 只认**紧贴**的那两格（相等判据；旧的 `<` / `>` 连更远的空白都算，更容易撞）；
///   ② 两个块**共享**那一格时（左邻是另一个行间块的收尾 `$$`）⇒ 让给**左边那块**
///      （它画"块之后"），本块不画"块之前"。
@visibleForTesting
({bool before, bool after}) blockEdgeClaim({
  required int? caret,
  required int acceptFrom,
  required int acceptTo,
  required bool sharesLeftCell,
}) =>
    (
      before: caret != null && caret == acceptFrom && !sharesLeftCell,
      after: caret != null && caret == acceptTo,
    );

/// ★★★ 2026-10-24（批 22）：**这一块要不要把光标画出来**。
///
/// 用户实测「点两个分段的花括号中间那一块，出现两个光标」—— 不是边界竖条那套，
/// 而是**两个单元的认领区间在那一格重叠**：A 的 `acceptTo` 与 B 的 `acceptFrom` 是同一个偏移
/// （两块之间只有一个 `\n`）⇒ 两个 `MathWithCaret` 都 `showCaret = true`
/// ⇒ 一根画在 A 的 tex 末尾、一根画在 B 的 tex 开头 ⇒ 屏幕上两根。
/// ⇒ 共享那一格**只归左边那块**（右边那块不画）。
///
/// ★★★ 2026-10-24（批 25）：**补上"光标在不在这块"的区间判据**。
///   批 23 的探针发现：上面这条只判了 `caret != null` + 共享格，
///   **没判光标是否落在本块的 `[acceptFrom, acceptTo]`** ⇒ 只要文档里有光标，
///   **每个**公式块都得到 `true`（实测 4 块 4 个 true）。
///   今天没画出 k 根竖条，全靠两道巧合：① `doc_view` 只对含光标的单元注锚点
///   （`showCursor: caretAbs != null`）；② `MathWithCaret._measure` 的 `findCaretAnchor`
///   找不到那个零尺寸 `ColoredBox` 就返回 null。
///   ⇒ 一旦注入链变化（给所有块注锚点）或 `findCaretAnchor` 加兜底，屏幕上会同时冒出 k 根。
///   ⇒ 判据补齐后，`showCaret` 才真的等于它的名字（`math_caret.dart` 的注释原话：
///   "光标在不在这段数学里（不在 ⇒ 连竖条也不画）"）。
///
/// ★ 区间是**闭区间**：`acceptFrom` = 块之前那一格、`acceptTo` = 块之后那一格，两格都归本块
///   （③-C 定的口径，别改），所以用 `>=` / `<=`；共享格仍由上面那条让给左边。
@visibleForTesting
bool blockShowsCaret({
  required int? caret,
  required int acceptFrom,
  required int acceptTo,
  required bool sharesLeftCell,
}) =>
    caret != null &&
    caret >= acceptFrom &&
    caret <= acceptTo &&
    !(sharesLeftCell && caret == acceptFrom);

/// ★★★ 2026-10-24（批 23）：**空行与"下一个行间块"抢同一格 ⇒ 空行让位**。
///
/// 用户文档（20:0x 第二组图）：`aaa` + 三个行间块，**块与块之间空一行**
/// （`$$\n…\n$$\n\n$$\n…`）。那个空行的行首偏移**正好等于**下一块的 `acceptFrom`
/// （行间块认领 `sliceStart - 1`，而 `sliceStart - 1` 就是这个空行自己的 `\n`）
/// ⇒ 空行槽画一根文本光标（页面左边行首）、块画一根"块之前"边界条（块的左缘）
/// ⇒ 屏幕上两根竖条，用户读成"两个光标"。
///
/// 口径（与批 21/22 的边界条同源）：**一个偏移只画一根**；两边都合法时
/// **让块来画**（"块之前"条贴着块的左缘，正好表示"光标要进这块"）。
/// ★ 空行**前后没有行间块**时（`nextAcceptFrom` 为 null 或与它不相等）照旧自己画 ——
/// 否则普通空行会变成"光标消失"。
@visibleForTesting
bool blankLineDrawsCaret({
  required int? caret,
  required int blankStart,
  required int? nextAcceptFrom,
}) =>
    caret == blankStart && blankStart != nextAcceptFrom;

/// 供外部（状态栏 / 实验页）显示的分页统计。
class DocViewStats {
  const DocViewStats({
    required this.blocks,
    required this.units,
    required this.pages,
    required this.overflow,
    required this.measurePool,
    required this.renderPool,
  });

  final int blocks;
  final int units;
  final int pages;

  /// 高于一页、被迫单独占页的块数（告警）
  final int overflow;

  /// 两棵树的 widget 池大小（应当稳定，不随文档长度线性增长）
  final int measurePool;
  final int renderPool;

  @override
  bool operator ==(Object other) =>
      other is DocViewStats &&
      other.blocks == blocks &&
      other.units == units &&
      other.pages == pages &&
      other.overflow == overflow &&
      other.measurePool == measurePool &&
      other.renderPool == renderPool;

  @override
  int get hashCode =>
      Object.hash(blocks, units, pages, overflow, measurePool, renderPool);

  @override
  String toString() => '块 $blocks · 流单元 $units · 页 $pages · 告警 $overflow'
      ' · 测量池 $measurePool · 渲染池 $renderPool';
}

/// 一次落点上报**来自哪一层**（2026-10-21 · L10）。
///
/// 行内公式上**确实有两条**上报路径：① 单元宿主的 `Listener`（文本层，落点只到"公式那一格"）
/// ② 行内公式自己的指针监听（精确到原子）。两条都保留才有精度，
/// 但调用方必须把**同一次物理按下**只算一次 —— 否则连击计数会把它数成两击
/// （实测：单击变"选中一个原子"、双击变空选、从公式里起手拖不动）。
/// ★ 三者**有优先级**（数值大的覆盖数值小的，同一次按下内）：
///   `band`（页边"公式之前/之后"的物理边界，用户拍板的判据）＞ `math`（字形命中）＞ `text`（粗落点）。
///   实测用例：行首公式左缘内侧 2px 既在公式盒里（math 会给"字形位置"）又在左缘带里
///   （band 给"公式之前"）—— 按用户拍板必须是**公式之前**。
enum TapSource {
  text,
  math,
  band;

  int get priority => index;
}

class DocView extends StatefulWidget {
  const DocView({
    super.key,
    required this.buffer,
    this.settings = DocSettings.defaults,
    this.onStats,
    this.onTapOffset,
    this.onEnvResizeRequest,
    this.onCaretRect,
    this.composingText = '',
    this.hideCaretAndSelection = false,
    this.caretVisible = true,
  });

  final DocBuffer buffer;
  final DocSettings settings;

  /// 每次分页结果变化时回调（给状态栏用）
  final void Function(DocViewStats stats)? onStats;

  /// ★ S3-2：点屏幕 → **L0 里的绝对偏移**（调用方负责落光标）。
  /// 文字走 `RenderParagraph.getPositionForOffset` + 段落↔源坐标换算；
  /// 行内公式与行间公式走 S1 验证过的 `hitTestMathTex`（叶盒 ↔ 可见原子）再做位点吸附。
  ///
  /// ★★ 2026-10-19（L4）：**第二个参数是这一按的全局位置**。
  ///   为什么必须给：连击（双击选词 / 三击选整块）要看"两次按下的位置是不是同一个"，
  ///   而父层的 `Listener.onPointerDown` 在**子层之后**才跑 ⇒ 从那里读位置会**滞后一按**
  ///   （实测：双击永远被算成单击、三击被算成双击）。
  ///
  /// ★★ 2026-10-21（L10）：**第三个参数是这条上报来自哪一层**。
  ///   行内公式一次物理按下会**上报两次** —— 文本层（粗：只认得"公式这一格"）与
  ///   公式层（精确到原子）。调用方按 `TapSource` 取**更精确**的那一个，
  ///   并且**只算一次按下**（否则第二次上报会被连击逻辑当成"第二击"）。
  final void Function(int offset, Offset global, TapSource source)? onTapOffset;

  /// 行间块上**右键**时回调（参数 = 该块的源偏移）；多行环境才会被接住（PC-5）
  final void Function(int offset)? onEnvResizeRequest;

  /// ★ S3-2：**光标处**的盒子（DocView 局部坐标）—— 给平台文本输入面定位用。
  ///
  /// ★★ 左边界必须是**光标的精确 x**，不能是整行的左边界（2026-10-14 实测定正）：
  /// 平台元素里的插入符（文本为空 → 插入符在元素原点）就是浏览器算 **IME 候选框**位置的依据，
  /// 元素摆在行首 ⇒ 候选框出现在整行最左端。同理，我们自己画的组合中间态也要落在光标处。
  final void Function(Rect? caretRect)? onCaretRect;

  /// ★ 组合中间态（正在拼的拼音串）—— **接进排版，让后面的字被真的推开**。
  ///
  /// 只对「含光标的那一个单元」生效，且**行间公式块不接**（那种情况由 `EditView` 叠画兜底）。
  /// 它**不进缓冲区**（设计稿 §11.7），纯粹是渲染期的临时内容。
  final String composingText;

  /// ★ ⑤ 失焦时**不画**光标与选区（数据仍保留；重新聚焦即恢复）
  final bool hideCaretAndSelection;

  /// ★ ⑤ 光标这一帧**画不画**（闪烁用；选区不受它影响）
  final bool caretVisible;

  @override
  State<DocView> createState() => DocViewState();
}

class DocViewState extends State<DocView> {
  late DocSettings _s = widget.settings;
  late PageGeometry _m = PageGeometry.from(_s);

  List<_Unit> _units = <_Unit>[];
  Map<String, _Unit> _unitById = <String, _Unit>{};

  final GlobalKey _measureRootKey = GlobalKey();
  final UnitPool _measurePool = UnitPool();
  final UnitPool _renderPool = UnitPool();

  List<double> _heights = <double>[];

  /// 上一次分页用的**正文**（判"要不要重排"的第二根尺子，见 `_scheduleMeasure`）
  String? _layoutSource;
  PageLayout? _layout;
  bool _measureScheduled = false;
  int _blockCount = 0;
  DocViewStats? _lastStats;

  int get measurePoolSize => _measurePool.size;
  int get renderPoolSize => _renderPool.size;
  int get pageCount => _layout?.pageCount ?? 0;

  /// ★★ S4-d③：每页那张 `RepaintBoundary` 的句柄（图片集 / 图片式 PDF 抓的就是它）
  final List<GlobalKey> _sheetKeys = <GlobalKey>[];

  /// 取第 [p] 页的 key（按需增长；页数减少时**不缩短**，避免正在抓的时候 key 被换掉）
  GlobalKey _sheetKeyOf(int p) {
    while (_sheetKeys.length <= p) {
      _sheetKeys.add(GlobalKey(debugLabel: 'page-${_sheetKeys.length + 1}'));
    }
    return _sheetKeys[p];
  }

  /// 第 [p] 页的绘制边界（**同步**取；单独抽出来是为了不跨 `await` 使用 `BuildContext`）
  RenderRepaintBoundary? _boundaryOf(int p) {
    if (p < 0 || p >= _sheetKeys.length) return null;
    final BuildContext? ctx = _sheetKeys[p].currentContext;
    if (ctx == null) return null;
    final RenderObject? ro = ctx.findRenderObject();
    return ro is RenderRepaintBoundary ? ro : null;
  }

  /// ★★ S4-d③：把**每一页**抓成 PNG 字节。
  ///
  /// 原则 4：抓的就是屏幕上那棵 `PageSheet` 子树（所见即所得），所以"图片集 / PDF"不另写排版。
  /// [pixelRatio] 默认 2×（= 96 dpi × 2 ⇒ 打印也够用；一页 ≈ 1588 × 2246）。
  ///
  /// 返回的列表长度 = **实际抓到的页数**（某一页还没上屏时会少，调用方按需报错）。
  ///
  /// ★★ 用 `toImageSync` 而不是 `await toImage`：后者在"这一帧还没画"时会
  ///   **等下一帧**，而调用方（导出按钮 / 测试）并不一定在出帧 —— 实测会把整个流程挂死。
  ///   `toImageSync` 取的是**上一次画好的那一层**，正是"所见即所得"要的东西。
  Future<List<Uint8List>> capturePages({double pixelRatio = 2.0}) async {
    final int n = pageCount;
    final bool prevHide = _hideForCapture;
    // ★★ 2026-10-20（用户实测：导出的 PDF 里 `M_x` 前面多了一根光标条）：
    //   `capturePages` 抓的是**屏幕上那一层**，所以必须先把光标与选区藏起来、
    //   等一帧真的画完（没有光标的那一帧），再 `toImageSync`；抓完在 `finally` 里恢复。
    _hideForCapture = true;
    captureHideCountForTest++;
    setState(() {});
    // ★ 等一帧画完（好让"没有光标"的那一帧上屏）。
    //   但**不能死等**：`tester.runAsync` 等环境里不会有帧 ⇒ 用 32ms 兜底（约两帧），
    //   真机上 `endOfFrame` 会先到，几乎不损失什么。
    await Future.any(<Future<void>>[
      WidgetsBinding.instance.endOfFrame,
      Future<void>.delayed(const Duration(milliseconds: 32)),
    ]);
    final List<Uint8List> out = <Uint8List>[];
    try {
      for (var p = 0; p < n; p++) {
        final RenderRepaintBoundary? ro = _boundaryOf(p);
        // 还没画过的页跳过（真机上点导出时页面早就画好了；跳过比永远等下去强）
        if (ro == null || ro.debugNeedsPaint) continue;
        final ui.Image img = ro.toImageSync(pixelRatio: pixelRatio);
        try {
          final ByteData? bd =
              await img.toByteData(format: ui.ImageByteFormat.png);
          if (bd != null) out.add(bd.buffer.asUint8List());
        } finally {
          img.dispose();
        }
      }
    } finally {
      _hideForCapture = prevHide;
      if (mounted) setState(() {});
    }
    return out;
  }
  /// 本帧的光标（绝对偏移）—— S3-2
  int? _caret;

  /// ★★ 2026-10-20（用户实测"导出的 PDF 里带着光标"）：导出期间临时隐藏光标与选区。
  ///   `capturePages` 抓的是"屏幕上那一层"，所以必须先藏光标、等一帧画完再抓，抓完立刻恢复。
  // ignore: prefer_final_fields
  bool _hideForCapture = false;

  /// 光标/选区是否要藏（失焦 **或** 正在导出）
  bool get _hideCaret => widget.hideCaretAndSelection || _hideForCapture;

  /// 测试用：导出期间是否处于"隐藏光标"状态
  bool get hidingForCaptureForTest => _hideForCapture;

  /// 测试用：累计"进入导出隐藏态"的次数（证明导出确实走过隐藏这一步）
  int captureHideCountForTest = 0;

  /// 行间公式块的 Math 渲染盒（仅渲染树用；键按**单元 id** 稳定，不会跨位置迁移）
  final Map<String, GlobalKey> _mathBlockKeys = <String, GlobalKey>{};

  /// 渲染树里每个单元的渲染盒（由 `_UnitHitBox` 帧末上报）—— 光标定位要用
  final Map<String, RenderBox> _unitBoxes = <String, RenderBox>{};

  /// 空行槽的渲染盒（⑥ 丙）：给"光标在空行上"时的输入面定位用
  final Map<String, RenderBox> _blankBoxes = <String, RenderBox>{};


  /// ⑤ 选区（绝对偏移；无选区时 `start == end`）
  int _selStart = 0;
  int _selEnd = 0;

  // ---------------- 光标像素位置（S3-2：给镜像输入框定位） ----------------

  /// 帧末算一次「光标处的盒子」（DocView 局部坐标），报给 [DocView.onCaretRect]。
  ///
  /// ★★ 左边界 = **光标的精确 x**（不是整行的左边界）。
  /// 平台元素里的插入符就是浏览器算 IME 候选框位置的依据，元素摆在行首 ⇒ 候选框跑到行首去。
  /// 宽度只用来给"正在拼的那串拼音"留排版余地，所以给一个固定值即可
  /// （元素里平时是空的，宽度不影响插入符位置）。
  static const double _kCaretBoxWidth = 160.0;

  /// ★★ 2026-10-19（L18；用户选 **方案 B**）：**行内公式左边缘的命中带宽度 = 4 px**。
  ///
  /// 两处用到（**都是命中层，不改排版**）：
  /// · 公式**内部**的最左 4 px ⇒ 段首（`_mathTapTexOffset`）；
  /// · 公式**外侧**的 4 px（行首时那一片属于页边距，谁也不认领）⇒ 段首（`_onPagePointerDown`）。
  /// 实测依据：物理边界；文字的左缘也是"前一个字之后"，不是按比例切。
  static const double kInlineLeftBandPx = 4.0;

  bool _caretRectScheduled = false;

  void _scheduleCaretRect() {
    if (widget.onCaretRect == null || _caretRectScheduled) return;
    _caretRectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _caretRectScheduled = false;
      if (!mounted) return;
      widget.onCaretRect?.call(_computeCaretRect());
    });
  }

  Rect? _computeCaretRect() {
    if (!mounted) return null;
    // ★★ 2026-10-18：`_blankBoxes` 是**只写不清**的缓存 —— 空行 widget 被回收后表里还留着
    //   它的 RenderBox，帧回调再拿它 `localToGlobal` 就会断言 `'attached': is not true`
    //   （用户实测"点第二次报错"）。⇒ 先清掉已 detach 的条目，用前再查一次。
    _blankBoxes.removeWhere((String _, RenderBox b) => !b.attached);
    final RenderObject? root = context.findRenderObject();
    final int? caret = _caret;
    if (root is! RenderBox || caret == null) return null;

    // ★★ ⑥ 丙：光标在**空行**上 ⇒ 用空行槽自己的盒子（它才是那一行的载体）
    final RenderBox? blank = _blankBoxes['blank@$caret'];
    if (blank != null && blank.attached && blank.hasSize) {
      final Offset g = blank.localToGlobal(Offset.zero, ancestor: root);
      return Rect.fromLTWH(g.dx, g.dy, _kCaretBoxWidth, textCaretHeight(_s.bodyFontSize));
    }

    // 光标所在单元；落在"文末空行"这类不属于任何单元的位置时 → 退到最后一个单元的行尾
    // （否则镜像框会跑回页面左上角，中文候选框就飘了）
    _Unit? target;
    var rel = 0;
    for (final _Unit u in _units) {
      final int? r = u.relFor(caret);
      if (r != null) {
        target = u;
        rel = r;
        break;
      }
    }
    if (target == null && _units.isNotEmpty) {
      target = _units.last;
      rel = target.renderLength;
    }
    if (target == null) return null;
    final _Unit u = target;

    // ① 行间公式块：整块是一个公式，放在它的下方（候选框不会挡住公式）
    if (u.type == BlockType.math) {
      final RenderObject? mr =
          _mathBlockKeys[u.id]?.currentContext?.findRenderObject();
      if (mr is! RenderBox || !mr.hasSize) return null;
      final Offset g = mr.localToGlobal(Offset.zero, ancestor: root);
      return Rect.fromLTWH(
          g.dx, g.dy + mr.size.height, mr.size.width, _s.bodyFontSize * 1.25);
    }

    final RenderBox? box = _unitBoxes[u.id];
    if (box == null || !box.hasSize) return null; // 单元盒要晚一帧才上报
    final String text = _renderParts(u.type, u.source).text;
    final RenderParagraph? para = _contentParagraph(box, _plainTextOf(text));
    if (para == null) return null;

    final Offset paraOrigin = para.localToGlobal(Offset.zero, ancestor: root);
    final double lineH = _s.bodyFontSize * _s.lineHeight;

    // ② 光标在**数学段**里 → 用那个数学占位符的盒子定位置
    //    （精确到公式内部的哪一列需要"位点 → 像素"的反查，留给 S3-3；先用占位符左边界）
    final int? mp = mathPlaceholderAt(text, rel);
    if (mp != null) {
      final List<TextBox> bs = para.getBoxesForSelection(
        TextSelection(baseOffset: mp, extentOffset: mp + 1),
      );
      final Offset o = bs.isNotEmpty
          ? para.localToGlobal(bs.first.toRect().topLeft, ancestor: root)
          : paraOrigin;
      return Rect.fromLTWH(o.dx, o.dy, _kCaretBoxWidth, lineH);
    }

    // ③ 光标在**文字段**里 → 段落排版器直接给位置
    final int? p = caretParagraphOffset(text, rel);
    if (p == null) return null;
    final Offset o = para.getOffsetForCaret(TextPosition(offset: p), Rect.zero);
    final Offset g = para.localToGlobal(o, ancestor: root);
    return Rect.fromLTWH(g.dx, g.dy, _kCaretBoxWidth, lineH);
  }

  // ---------------- 点屏幕定位（S3-2） ----------------

  /// 渲染树里某个单元被点中 → 算出 L0 绝对偏移
  void _handleUnitHit(_Unit u, BuildContext ctx, Offset global) {
    final void Function(int, Offset, TapSource)? cb = widget.onTapOffset;
    if (cb == null) return;
    final int? off = _offsetAt(u, ctx.findRenderObject(), global);
    if (off != null) cb(off, global, TapSource.text);
  }

  /// ★★ 2026-10-19（L18；用户选 **方案 B**）：**公式左缘外侧那 4 px**（行首时落在页边距里）。
  ///
  /// 探针实测（行内公式在**行首**、光标先在文末）：点它左缘
  /// **−2 / −4 / −6 / −10 / −16 px ⇒ 光标一动不动** —— 那几像素既不在段落盒里、
  /// 也不在公式的 `WidgetSpan` 里 ⇒ **谁都不认领**。而点它自己最左 0 px 则落进公式内部。
  /// ⇒ 行首公式的"左边"根本没有落点，与"文字左边 = 前一个字之后"**不同权**。
  ///
  /// 做法：页面级 `Listener`（页边距那一片本来没人接指针，所以**不会抢任何东西**），
  /// 只在"**某个单元左缘 − 4 px … 左缘**之间 + 竖直落在该单元内"时生效：
  /// 把落点换成**该行行首**（在左缘内侧 0.5 px 处求一次 `_offsetAt`）
  /// ⇒ 行首若是公式，换出来就是"公式之前"；若是文字，就是那一行第一个字之前。
  void _onPagePointerDown(PointerDownEvent e) {
    final void Function(int, Offset, TapSource)? cb = widget.onTapOffset;
    if (cb == null) return;
    for (final _Unit u in _units) {
      if (u.type == BlockType.math) continue; // 行间块是整块认领的，不走这条
      final RenderBox? box = _unitBoxes[u.id];
      if (box == null || !box.attached || !box.hasSize) continue;
      final Offset tl = box.localToGlobal(Offset.zero);
      if (e.position.dy < tl.dy || e.position.dy > tl.dy + box.size.height) {
        continue;
      }
      // 落在单元**里面** ⇒ 单元自己的命中盒已经处理了，这里必须让开（否则会算两次）
      if (e.position.dx >= tl.dx && e.position.dx <= tl.dx + box.size.width) {
        return;
      }
      if (e.position.dx < tl.dx - kInlineLeftBandPx) continue;
      final int? off =
          _offsetAt(u, box, Offset(tl.dx + 0.5, e.position.dy));
      if (off != null) cb(off, e.position, TapSource.band);
      return;
    }
  }

  /// ★★ ⑤ 拖选要用的**纯查询**：某个全局坐标落在哪个偏移上（不改任何状态）。
  ///
  /// 与点击走**同一套**判据（行间块 → 公式命中；文字 → 段落排版器），
  /// 这样"拖着走"给出的落点与"点一下"完全一致。
  int? offsetAtGlobal(Offset global) {
    for (final _Unit u in _units) {
      final RenderBox? box = _unitBoxes[u.id];
      if (box == null || !box.hasSize) continue;
      if (!(Offset.zero & box.size).contains(box.globalToLocal(global))) continue;
      return _offsetAt(u, box, global);
    }
    // ★★ 2026-10-17 用户实测：**单行内**拖选会少最后一个字符（跨行没事）。
    //   原因：拖到行末时指针已经出了该单元的盒子（盒子只有文字的宽度）⇒ 这里返回 null
    //   ⇒ 落点停在"上一个还命中的位置"，最后一个字就选不上。
    //   ⇒ 退路：按**竖直位置**找最近的那一行；在它右半边就落到**行末**，左半边就落到**行首**。
    _Unit? near;
    var bestDy = double.infinity;
    for (final _Unit u in _units) {
      final RenderBox? box = _unitBoxes[u.id];
      if (box == null || !box.hasSize) continue;
      final Offset topLeft = box.localToGlobal(Offset.zero);
      final double dy = global.dy < topLeft.dy
          ? topLeft.dy - global.dy
          : (global.dy > topLeft.dy + box.size.height
              ? global.dy - (topLeft.dy + box.size.height)
              : 0);
      if (dy < bestDy) {
        bestDy = dy;
        near = u;
      }
    }
    if (near == null) return null;
    final RenderBox? nb = _unitBoxes[near.id];
    if (nb == null) return null;
    final Offset tl = nb.localToGlobal(Offset.zero);
    final bool right = global.dx >= tl.dx + nb.size.width / 2;
    return near.renderBase + (right ? near.renderLength : 0);
  }

  /// 命中计算本体（[ro] 是单元盒或公式盒）
  int? _offsetAt(_Unit u, RenderObject? ro, Offset global) {
    if (ro is! RenderBox || !ro.hasSize) return null;

    // ① 行间公式块：整块就是一个数学段
    if (u.type == BlockType.math) {
      final String rawTex = _renderParts(u.type, u.source).text;
      // ★★ §6.1.1（2026-10-18）：**空的公式块没有字形盒** ⇒ 命中表用不了
      //   （`_mathBlockKeys` 那个 Math 盒根本不存在 —— 我们画的是 `EmptyMathMark`）。
      //   但它是**看得见的对象** ⇒ 点这块里的任何地方都落进块内
      //   （空块唯一的内容位点 = `renderBase`）。
      if (rawTex.trim().isEmpty) return u.renderBase;
      final RenderObject? mr =
          _mathBlockKeys[u.id]?.currentContext?.findRenderObject();
      if (mr is! RenderBox || !mr.hasSize) return null;
      final int? caretRel = _caret == null ? null : u.relFor(_caret);
      final int? texRelRaw = _mathTapTexOffset(
        tex: rawTex,
        renderTex: _renderTexFor(rawTex, caretRel),
        root: mr,
        global: global,
        displayStyle: true,
        // ★ 行距兜底用（环境里量不出行距时 ×1.2）；行间块的字号是"行间字号"
        fontSize: _s.effectiveDisplayFontSize,
      );
      // ★★★ 2026-10-24（批 20）：`&=` 的 `=` **之前**不是落点（与方向键同一口径）
      final int? texRel =
          texRelRaw == null ? null : normalizeAlignedEqOffset(rawTex, texRelRaw);
      if (texRel == null) return null;
      return u.renderBase + buildCaretSites(rawTex).snap(texRel).offset;
    }

    // ② 文字（段落 / 标题 / 引用 / 列表项）：交给段落排版器
    final String text = _renderParts(u.type, u.source).text;
    final int? rel = u.relFor(_caret);
    // ★ 只有**真的画了光标条**时，段落才多那一格（与渲染侧共用同一判据）
    final int? caretInText =
        _caretAbsFor(u, rel) == null ? null : _caretInTextSegment(text, rel);
    // ★★ 2026-10-17 用户实测「单行拖选少最后一个字符」的**根因**就在这里：
    //   段落里那根**零宽光标条**占了**一个格子**（`caretInText` 让映射表多一格），
    //   而 `getPositionForOffset` 在"拖到行尾右侧"时会把落点吸到**光标条之前**
    //   ⇒ 段落坐标比真实行末少 1；再套上多了一格的映射表，正好又少 1 ⇒ 差 1 格。
    //   修法：**映射用"纯表"**（不含光标条），再把段落坐标里"光标条那一格"扣掉。
    // 映射表与段落**必须**同时"有/没有"光标条那一格 —— 这就是上面那条判据的唯一意义
    final List<int> pureMap =
        paragraphIndexMap(text, caretInText: caretInText);
    final RenderParagraph? para = _contentParagraph(ro, _plainTextOf(text));
    if (para == null) return null;
    final TextPosition tp =
        para.getPositionForOffset(para.globalToLocal(global));
    // ★ `pureMap` 与"段落是否多一格光标条"现在由**同一个判据**（`_caretAbsFor`）决定：
    //   画了光标条 ⇒ `caretInText` 非空 ⇒ 映射表多一格、段落也多一格 ⇒ 两侧一致；
    //   没画（有选区 / 失焦 / 闪烁灭）⇒ 两侧都**没有**那一格 ⇒ 不会差 1。
    final int p = tp.offset.clamp(0, pureMap.length - 1);
    return u.renderBase + pureMap[p];
  }

  /// 光标落在本段**文字段**里的相对偏移（落在数学段里则 null —— 那时不产生额外码元）
  static int? _caretInTextSegment(String text, int? rel) {
    if (rel == null) return null;
    for (final ProjectionSegment s in projectInline(text)) {
      if (s.isMath) continue;
      if (rel >= s.start && rel <= s.end) return rel;
    }
    return null;
  }

  /// 该渲染文本里的**纯文字部分**（把行内公式整段去掉）
  static String _plainTextOf(String text) => projectInline(text)
      .where((ProjectionSegment s) => !s.isMath)
      .map((ProjectionSegment s) => s.text)
      .join();

  /// 渲染某个数学段时用的 tex（**注入与渲染必须走同一个函数**，否则点击定位会错位）
  String _renderTexFor(String tex, int? caretRel) {
    // ★ 2026-10-20：行间块也走同一条**显示修正**（`\limsup`/`\liminf` 补 `\limits`），
    //   并把光标偏移同步映射过去（插入 `\limits` 会改长度）。
    final FixedTex fixed = withOperandLimits(tex);
    final int rel = caretRel == null ? -1 : fixed.mapOffset(caretRel);
    final SlotMarkResult m = injectSlotMarks(fixed.tex, caretRel: rel);
    return caretRel == null ? m.tex : injectCursor(m.tex, m.rel).tex;
  }

  /// ★★ 一次数学段点击 → **段内 tex 偏移**（`null` = 这一格不归数学管，交回行级落点）。
  ///
  /// 判据分两条（③-B，《位点与结构导航》§5.2 归属表 + §11.25）：
  /// 1. **真点在字形盒上**（`onGlyph`）⇒ 用 `hitTestMathTex` 的叶盒 ↔ 原子映射（原行为）；
  /// 2. 只点在**装饰 / 结构盒 / 公式外侧留白** ⇒ 用 `structure_geometry.glyphlessLanding`：
  ///    结构盒内 ⇒ 左半=结构之前、右半=结构之后；盒外 ⇒ 公式之前 / 之后。
  ///
  /// ★ 为什么必须分这两条：`hitTestMathTex` 在没点中字形时的兜底是"**几何最近的字形盒**"，
  ///   于是在分式右端的装饰区里最近的是**分母** ⇒ "点分式右边"变成"点进分母"（用户实测 ①）。
  /// ★ 2026-10-17 起第 1 条**可靠了**：配对改走 `leaf_pairing`（一原子可占多盒 + 渲染顺序重排），
  ///   所以含 `\sin` / `\lim` / `\sum` 这类算子名的公式也能精确落点；
  ///   配对确实对不上（`cases` 那一族）时仍退回第 2 条的结构层落点，**宁可粗，不许错**。
  int? _mathTapTexOffset({
    required String tex,
    required String renderTex,
    required RenderObject root,
    required Offset global,
    required bool displayStyle,
    double? fontSize,
  }) {
    final Offset localPos = (root as RenderBox).globalToLocal(global);

    // ★★ 2026-10-19（用户："外面都点不到"）：**行间公式的外侧**要落在"公式之前 / 之后"。
    //   原来的兜底是"最近字形 / 最近格子" ⇒ 点左边 40 px 也会被吸进第一格
    //   （用户看到的就是"点不到外面"）。判据：点落在数学盒的**横向范围之外**。
    //   行内公式不走这条（它的宽度就是那几个字，外侧属于段落文本，由段落自己管）。
    if (displayStyle) {
      if (localPos.dx < -2) return 0;
      // ⏳ 2026-10-24（批 11）：这里本该"块外 ⇒ 块之后"，但改成返回 null 会打乱
      //   `env_click_test` ⑧/⑪ 与 `math_blank_landing_test` ③-B 钉住的落点（它们要的是
      //   "公式之后"那一格，而返回 null 会走到页面层的另一条兜底）⇒ **先保持原样**，
      //   等"块外落点"在单元层统一处理时一起改。见后优化清单 §14.7 H6′。
      // ★★★ 2026-10-24（批 19 · F1-b）：**多行环境里，点落在某条行带内 ⇒ 落那一行的末尾**。
      //   旧口径（批 11 ③"点外侧 ⇒ 块内末尾"）对多行块太粗：`cases` 两段里想接着写**第一段**，
      //   点它右边留白 ⇒ 光标跳到整块最后。现在按**竖直位置**判：哪条行带里就落那一行的末尾
      //   （= 该行最后一格的内容末尾，**不是**块末尾 —— 末行的行末在 `\end{…}` 之前）；行带之外才落块末尾。
      if (localPos.dx > root.size.width + 2) {
        if (hasEnv(tex)) {
          final EnvGrid? grid = buildEnvGrid(
              root: root,
              tex: renderTex,
              displayStyle: displayStyle,
              fontSize: fontSize ?? 20);
          if (grid != null) {
            for (var r = 0; r <= grid.maxRow; r++) {
              final Rect? band = grid.rowBand[r];
              if (band == null) continue;
              if (localPos.dy < band.top || localPos.dy > band.bottom) continue;
              final int? rowEnd =
                  envCellOffset(tex, EnvCellHit(r, grid.maxCol, atEnd: true));
              if (rowEnd != null) return rowEnd;
            }
          }
        }
        return tex.length;
      }
    } // ★★ 2026-10-25：**行内左缘那条 4px 带挪到命中之后**（见下面 `hit` 算完那处）——
    //   它只该管"**没点到墨迹**"的像素。

    // ★★ 2026-10-18 晚（用户："坏文本导致符号之间点不到的问题依然存在，行列式也有"）：
    //   **先试细粒度命中**（点在字形上 ⇒ 叶盒 ↔ 原子，能落到**符号之间**），
    //   只有"没点在字形上"（格子里的空白 / 空格子 / 竖线）才退回**按格子**判。
    //   原来是"有环境先按格子" ⇒ 格子内的 `a+b` 只能落到格首/格尾，**符号之间点不到**。
    final MathHit hit = hitTestMathTex(
      root: root,
      localPos: localPos,
      tex: renderTex, // ★ 必须用渲染时的 tex（见 injection_map.dart）
      // ★ 原子表必须是**渲染顺序**（尾垫/占位垫由词法自己在走查顺序里认出）
      atoms: renderOrderAtoms(renderTex, displayStyle: displayStyle),
      displayStyle: displayStyle,
    );

    // ★★ 2026-10-25（用户 2026-10-25 追问"左缘带是不是 `\lim` 下面 x 的左边那一块"）：
    //   **墨迹优先** —— 这条带只对"**没点到字形**"的像素生效。
    //
    //   来由（探针 v52 整篇逐字形盒体检抓到的**唯一**一处点不到）：
    //   `$\lim\limits_{x\to x_0}\frac{1}{f(x)}=0$` 的**下限 x** 画在盒子最左边
    //   （盒内 x≈3.2 < 4）⇒ 它的左半截被这条带判成"点公式之前"（落下标了，落到段首）。
    //   而它**明明是一块墨迹**：一像素一个主人 ⇒ 墨迹的主人就是它自己。
    //
    //   ★ 带子原本要救的是"公式盒**外面**那几像素"（−4..0，谁都不认领，用户 2026-10-19 报
    //     "点它左边点不到"）—— 那些像素**没有字形**，照旧归"公式之前"，口径一点没变。
    if (!displayStyle && localPos.dx < kInlineLeftBandPx && !hit.onGlyph) return 0;

    if (hit.onGlyph && hit.offset != null && hit.reliable) {
      final int rel = renderToSourceOffset(renderTex, hit.offset!);
      // ★★★ 2026-10-24（批 8）：**"对象层落点"只对"点在字形盒之外"的点击生效**。
      //
      // 来由（两次用户实测，方向相反，必须同时满足）：
      //   · 批 4c（D5）：「在 `x^{3}` **后面**加东西，只能点到 `3` 后面，点不到这个指数的后面」
      //     ⇒ 需要"对象之后"可达；
      //   · 批 8（今天）：「`3` **后面**的位置也点不到，现在点后面一定是整个指数的后面」
      //     ⇒ 需要"`3` 之后（指数里）"也可达。
      // 两者只能靠**位置**分开：
      //   · 点在**字形盒内**（含右半/左半）⇒ 细粒度：`3` 之前 / `3` 之后（就是指数里那两位点）；
      //   · 点在**字形盒之外**（外扩 2px 与"行内宽容"8px 认领的那些像素）⇒ 落到"对象之前/之后"。
      // 实测：`x^{3}` 里 `3` 的右缘外只有 ~1px 缝，但它**是**对象边界那一格（11）；
      //   再往外 8px 内也仍认作"对象之后" ⇒ 手指够得着，而 `3` 本身仍然给了细粒度。
      final Rect? br = hit.boxRect;
      final bool outsideGlyph =
          br != null && (localPos.dx < br.left || localPos.dx > br.right);
      final int? outer = !outsideGlyph
          ? null
          : buildCaretSites(tex)
              .scriptOuterSiteAt(rel, rightHalf: localPos.dx > br.right);
      return outer ?? rel;
    }

    // ★★ P2-D（2026-10-18）：多行环境**按格子**判落点（判的是"没点中字形"的那些位置）。
    if (hasEnv(tex)) {
      final EnvCellHit? cell = envCellHitAt(
        root: root,
        localPos: localPos,
        tex: renderTex,
        displayStyle: displayStyle,
        fontSize: fontSize,
      );
      if (cell != null) {
        // ★★ 点在**这一格有墨迹的内容上**（字与字之间也算）⇒ 用细粒度落点，
        //    落在两个符号之间；只有格子里的空白才压到格首/格尾。
        if (cell.onInk && hit.offset != null) {
          return renderToSourceOffset(renderTex, hit.offset!);
        }
        final int? cellOffset = envCellOffset(tex, cell);
        if (cellOffset != null) return cellOffset;
      }
    }
    if (hit.onGlyph && hit.offset != null) {
      return renderToSourceOffset(renderTex, hit.offset!);
    }

    final StructureGeometry g = buildStructureGeometry(
      tex: tex,
      renderTex: renderTex,
      mathRoot: root,
      displayStyle: displayStyle,
    );
    Rect? hull;
    for (final LeafBox b in scanLeafBoxes(root).eligible) {
      hull = hull == null ? b.rect : hull.expandToInclude(b.rect);
    }
    return glyphlessLanding(
      objects: g.objects,
      rects: g.rects,
      glyphHull: hull,
      localPos: localPos,
      texLength: tex.length,
    );
  }

  /// 行间公式块被点中

  /// 行内公式被点中（`InlineMathText.onMathTap` 给的是**段内相对**的 tex、
  /// **渲染用的 tex**、以及渲染盒 key）
  void _onMathTap(_Unit u, ProjectionSegment seg, String renderTex, Offset global,
      GlobalKey key) {
    final void Function(int, Offset, TapSource)? cb = widget.onTapOffset;
    if (cb == null) return;
    // ★★ §6.1.1（2026-10-18）：**空公式没有字形盒** ⇒ 走不了命中表。
    //   但它是**看得见的对象**（`EmptyMathMark` 那个虚线小框），点它必须"落进公式里"
    //   —— 空公式唯一的内容位点就是它的 contentStart。
    if (seg.tex.trim().isEmpty) {
      cb(u.renderBase + seg.start, global, TapSource.math);
      return;
    }
    final RenderObject? ro = key.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return;
    final int? texRelRaw = _mathTapTexOffset(
      tex: seg.tex,
      renderTex: renderTex,
      root: ro,
      global: global,
      displayStyle: false, // ★ 行内 = text 样式（`\sum` 的上下限退回脚本位）
      fontSize: _s.bodyFontSize,
    );
    // ★★★ 2026-10-24（批 20）：同一条口径（点击与方向键落点必须一致）
    final int? texRel =
        texRelRaw == null ? null : normalizeAlignedEqOffset(seg.tex, texRelRaw);
    if (texRel == null) return;
    // ★ 位点吸附：落点必须是合法位点（设计稿 §2.4 的 P3）
    final int rel = buildCaretSites(seg.tex).snap(texRel).offset;

    cb(u.renderBase + seg.start + rel, global, TapSource.math);
  }

  /// 找出**内容段落**（而不是列表标记那种小段落）。
  ///
  /// ★ 不能"取第一个 `RenderParagraph`"：列表项的 widget 是
  ///   `Row[ SizedBox(Text('•')), Expanded(InlineMathText) ]` —— 子树里第一个段落是**标记那个**，
  ///   它的纯文本只有 1 个码元，点内容区会被它夹到末尾
  ///   → 光标**永远落在同一个错位置**（用户实测：点「判别式」任何地方都落在「判」「别」之间）。
  ///
  /// 判据：段落的**纯文字部分**（剥掉所有 `U+FFFC` 占位符）与 [expectedPlain] 完全相等。
  /// ⚠️ 不能用"码元数"当判据 —— 我们自己注入的**光标条也是 `WidgetSpan`**，会给段落多出 1 个码元
  /// （实测：`判别式` 的段落纯文本是 `￼判别式`，长度 4 而不是 3，判据当场失效）。
  static RenderParagraph? _contentParagraph(
    RenderObject ro,
    String expectedPlain,
  ) {
    RenderParagraph? exact;
    RenderParagraph? first;
    void visit(RenderObject o) {
      if (o is RenderParagraph) {
        // ★★ 2026-10-16：**帧末回调可能晚于子树的卸载** —— `RenderParagraph.text`
        //   内部是 `_textPainter.text!`，此时会抛 `Null check operator used on a null value`
        //   （**既有缺陷**，快照 §十二·B-15 记过："组件刚被 dispose"就会撞；
        //   `accent_as_one_object_test` 的连挂扫描把它撞实了，挡住了 ④ 这一批的验证）。
        //   本站只是**诊断遍历**（找内容段落）⇒ 拿不到文本就当它不是候选，
        //   **绝不让它把整帧打挂**。真机上（不反复挂卸）不会走到这里。
        if (o.attached && o.hasSize) {
          first ??= o;
          final String plain;
          try {
            plain = o.text.toPlainText();
          } catch (_) {
            return;
          }
          if (plain.replaceAll('\uFFFC', '') == expectedPlain) exact ??= o;
        }
        return;
      }
      o.visitChildren(visit);
    }

    visit(ro);
    return exact ?? first;
  }

  /// ★ 池键要带上"光标态"。
  ///
  /// 池是按**内容**寻址的，而光标让"包含光标的那个单元"的 widget 变了：
  /// 若不加进键，光标从 A 移到 B 时，A 会从池里拿回**带光标的旧实例** → 屏幕上留一个幽灵光标。
  /// 加上之后：一次击键最多重建 2 个单元，空转时池照样全命中（S2 的 2.8 ms 空帧不退化）。
  /// 本单元的**局部选区**（渲染坐标）；无选区 / 与本单元无交集 ⇒ null。
  /// 这个单元**这一帧到底画不画光标条**（唯一判据）。
  ///
  /// ★★ 2026-10-17 真凶：`_offsetAt` 原来**只要光标落在本段文字里**就认为段落多了一格
  ///   光标条（`caretInText`），但渲染侧在"有选区 / 失焦 / 闪烁灭"时**根本不画**光标条。
  ///   两边不一致 ⇒ 映射整体差 1 ⇒ **行内拖选少最后一个字**，而且随闪烁相位"时好时坏"。
  ///   ⇒ 把判据抽成这一个函数，渲染与命中**共用**。
  int? _caretAbsFor(_Unit u, int? rel) {
    if (rel == null) return null;
    if (_selEnd > _selStart) return null; // 有选区 ⇒ 不画光标（也占位）
    if (_hideCaret) return null; // 失焦 / 导出中
    if (!widget.caretVisible) return null; // 闪烁"灭"的相位
    return u.renderBase + rel;
  }

  /// **逻辑光标**位置：只用来决定"注不注空槽垫子"。
  ///
  /// ★★ 与 [_caretAbsFor] 的差别只有两条：**闪烁相位**与**选区**都不参与。
  ///   理由：垫子会改版面宽度 —— 它必须只随"光标在哪"变，不能随"光标看不看得见"变。
  ///   失焦仍然返回 null（不画光标时不注垫子，否则页面上会留下看不见的占位）。
  int? _slotCaretAbsFor(_Unit u, int? rel) {
    if (rel == null) return null;
    if (_hideCaret) return null;
    return u.renderBase + rel;
  }
  ({int from, int to})? _localSelFor(_Unit u) {
    if (_hideCaret || _selEnd <= _selStart) return null;
    final int rawA = _selStart - u.renderBase;
    final int rawB = _selEnd - u.renderBase;
    final int a = rawA.clamp(0, u.renderLength);
    final int b = rawB.clamp(0, u.renderLength);
    if (b > a) return (from: a, to: b);
    if (_selStart <= u.renderBase && _selEnd >= u.renderBase + u.renderLength) {
      return (from: 0, to: u.renderLength); // 整单元被选中（含两端）
    }
    return null;
  }
  String _poolKeyFor(_Unit u) {
    final int? rel = u.relFor(_caret);
    // ★★ ⑤ 实测踩到的坑（用户："拖选全部后再点下面，只有最后一排取消"）：
    //   池键原来**不含选区** ⇒ 不含光标的那些单元会从池里拿回**上一帧（带高亮）的 widget**
    //   ⇒ 只有"光标所在那一行"被重建、高亮消失，其余行的高亮**留着不动**。
    final ({int from, int to})? sel = _localSelFor(u);
    final String selKey = sel == null ? '' : '#s${sel.from}-${sel.to}';
    // 光标这一帧画不画（闪烁相位 / 失焦）也必须进键：否则单元从池里拿回旧 widget，
    // 相位变了也不重画 ⇒ 看起来就是光标一直静态不闪、点完有时不出现。
    final String caretKey = widget.caretVisible ? '#b1' : '#b0';
    // ★★★ 2026-10-20（T-C 实测 F16 的真正根因）：**"这一帧画不画编辑辅助"也必须进键**。
    //   `capturePages` 是"先藏再抓"：藏的只是**状态**，而单元 widget 是从 `_renderPool` 里取的
    //   —— 键里没有这个状态，就会把**上一帧（带光标 / 带空槽虚线框）的 widget** 拿回来
    //   ⇒ 抓到的图里照样有光标与虚线框（实测：F16 改完第一版导出的 PDF 里两者都在）。
    //   ★ 用 `_hideCaret`（= 失焦 **或** 导出中）：
    //     它决定"光标/选区画不画"，是同一帧的渲染输入；不进键就永远是池里的旧样子。
    final String aidsKey = _hideCaret ? '#a1' : '#a0';
    // ★★★ 2026-10-24（批 24 —— 用户稳定复现"点另一块时整块闪一帧"的真根因）：
    //   **池里的 widget 内嵌着"这一单元自己的身份"**（`MathWithCaret.mathKey` =
    //   `_mathBlockKeys[u.id]`，而 `Math.tex(key: mathKey)` 就是那个 GlobalKey）。
    //   池却**只按内容**寻址 ⇒ 两块内容一模一样时（用户的文档里
    //   `\begin{cases}4\\\end{cases}` 出现两次）键相同 ⇒ 后一块从池里拿回
    //   **前一块的 widget 实例**，里面装的是**前一块的 GlobalKey**
    //   ⇒ 同一帧同一个 GlobalKey 出现在两处 ⇒ 框架把元素搬走
    //   ⇒ 实测：**整块消失一帧** + 21 处框架断言（`childRenderObject.parent != null`、
    //   `_debugRelayoutBoundaryAlreadyMarkedNeedsLayout`、`!childSemantics.renderObject._needsLayout`）。
    //   ⇒ 键里必须带**单元身份** `u.id`。内容键保留：同一单元内容不变时照旧复用
    //   （打字只改被编辑那一个单元的键；插入/删除块会让后面单元的 id 变一次 ⇒ 重建一次，可接受）。
    final String idKey = '#u${u.id}';
    if (rel == null) return '$idKey${u.contentKey}$selKey$caretKey$aidsKey';
    // ★ 组合态也要进键：拼音变化会改变"含光标那个单元"的 widget 内容，
    //   不进键就会从池里拿回上一帧的旧拼音（叠字/不刷新）。
    final String comp = _composingFor(u, rel).isEmpty
        ? ''
        : '#k${_composingFor(u, rel).hashCode}';
    return '$idKey${u.contentKey}#c$rel$comp$selKey$caretKey$aidsKey';
  }

  /// 这个单元要不要接组合串（**只给含光标的那一个单元，且行间公式块不接**）。
  ///
  /// 为什么不接行间公式块：它的单元文本就是 LaTeX 源码本身，把拼音塞进排版等于往源码里塞字符 ——
  /// 那种情况由 `EditView` 用**叠画**兜底（见它的 `_composingOverlay`）。
  String _composingFor(_Unit u, int? rel) {
    if (rel == null || widget.composingText.isEmpty) return '';
    if (u.type == BlockType.math) return '';
    return widget.composingText;
  }

  void _emitStats() {
    final DocViewStats s = DocViewStats(
      blocks: _blockCount,
      units: _units.length,
      pages: _layout?.pageCount ?? 0,
      overflow: _layout?.overflow.length ?? 0,
      measurePool: _measurePool.size,
      renderPool: _renderPool.size,
    );
    if (_lastStats == s) return;
    _lastStats = s;
    widget.onStats?.call(s);
  }

  @override
  void initState() {
    super.initState();
    widget.buffer.addListener(_onBufferChanged);
  }

  @override
  void didUpdateWidget(DocView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.buffer != widget.buffer) {
      oldWidget.buffer.removeListener(_onBufferChanged);
      widget.buffer.addListener(_onBufferChanged);
    }
    if (oldWidget.settings != widget.settings) {
      _s = widget.settings;
      _m = PageGeometry.from(_s);
      // 版面变了：**缓存的旧高度全部作废**，否则高度比较会判定"没变化"而提前返回，
      // 分页与统计就都不会更新（这是被 widget 测试抓出来的真 bug）。
      _layout = null;
      _heights = <double>[];
    }
  }

  @override
  void dispose() {
    widget.buffer.removeListener(_onBufferChanged);
    super.dispose();
  }

  void _onBufferChanged() {
    if (mounted) setState(() {});
  }

  // ---------------- 解析：BlockIndex → FlowUnit 列表 ----------------

  List<_Unit> _buildUnits(BlockIndex idx) {
    final LineIndex lines = idx.lines;
    final out = <_Unit>[];
    var pendingBreak = false;

    for (var bi = 0; bi < idx.blocks.length; bi++) {
      final Block b = idx.blocks[bi];
      if (b.type == BlockType.pageBreak) {
        pendingBreak = true;
        continue;
      }
      final units = idx.flowUnits.where((FlowUnit u) => u.blockIndex == bi);
      var k = 0;
      for (final FlowUnit u in units) {
        final sb = StringBuffer();
        for (var l = u.lineFrom; l < u.lineTo; l++) {
          if (l > u.lineFrom) sb.write('\n');
          sb.write(lines.text(l));
        }
        final src = sb.toString();
        final int sliceStart = lines.starts[u.lineFrom];
        // ★ S3-2：渲染文本与它的绝对起点（剥标记的偏移要补偿，否则光标整体偏掉）
        final _Rendered r = _renderParts(b.type, src);
        out.add(_Unit(
          id: 'blk$bi/u$k',
          contentKey: '${b.type.name}\u0000$src',
          type: b.type,
          source: src,
          blockIndex: bi,
          isFirstInBlock: k == 0,
          breakBefore: k == 0 && pendingBreak,
          label: _labelFor(b.type, src),
          renderBase: sliceStart + r.offsetInSource,
          renderLength: r.text.length,
          // 列表项的标记区（`- ` / `1. `）也归它 → 光标在标记里时显示在内容开头
          //
          // ★★ ③-C（《位点与结构导航》§11.25，2026-10-16）：**行间公式块认领自己整片源码**
          //    （`$$` 围栏与行尾都算）。原来只认 `[renderBase, renderEnd]`（= 公式本身）⇒
          //    光标走出公式、停在"块之后那一格"时**没有任何单元认领它**
          //    ⇒ `showCaret = false`（用户实测的"光标消失"，但删除还能删掉整个分式）。
          //    `relFor` 会把两端**夹进 tex** ⇒ 光标画在公式的**左 / 右边缘**（与行内对称）。
          acceptFrom: switch (b.type) {
            BlockType.bulletList || BlockType.orderedList => sliceStart,
            // ★★ 批 28：标题 / 引用的**标记区**（`### ` / `> `）也归本单元。
            //   原来落到默认值 `renderBase`（= 标记之后）⇒ **空标题块**（`### ` 后面没字）
            //   整个标记区没人认领 ⇒ 光标进不去、也就没有竖条
            //   （探针 v30 逐偏移实测：分界线后面那个空 `### ` 的 30–34 全是死区）。
            //   与列表项同口径：标记区算"内容开头"。
            BlockType.heading1 ||
            BlockType.heading2 ||
            BlockType.heading3 ||
            BlockType.quote =>
              sliceStart,
            // ★ 与行内公式的「两端各多认领一格」对称：**块前那一格**也算（否则光标从上面
            //   往下走进块时，最后一格没人管 ⇒ 又是"光标消失"）
            BlockType.math => sliceStart > 0 ? sliceStart - 1 : 0,
            BlockType.divider => sliceStart,
            _ => null,
          },
          acceptTo: switch (b.type) {
            BlockType.math => sliceStart + src.length,
            // ★★★ 2026-10-24（批 27）：**分界线块也要认领自己那一整行**（用户实测"点分界线下面那行
            //   光标不显示"）。它的渲染文本是空的（`_renderParts` 给 `('', 0)`）⇒ 默认
            //   `acceptTo = renderBase + 0 = sliceStart` = **行首**，于是：
            //     · `blankRunAfter(buf, sliceStart)` 看到的是 `-` 而不是 `\n` ⇒ **分界线下面那个空行
            //       根本没有空行槽** ⇒ 点它、光标落对了，但没人画；
            //     · 文末槽的 `_blankOffsetAfter` 同理返回 -1 ⇒ 文末在分界线之后也没有光标。
            //   改成"认领整片源码"（与行间公式块同一条口径）⇒ 换行符回到 `acceptTo` 那一格。
            BlockType.divider => sliceStart + src.length,
            _ => null,
          },
        ));
        k++;
      }
      if (k > 0) pendingBreak = false;
    }
    return out;
  }

  String _labelFor(BlockType t, String src) {
    final name = switch (t) {
      BlockType.heading1 || BlockType.heading2 || BlockType.heading3 => '标题',
      BlockType.bulletList || BlockType.orderedList => '列表项',
      BlockType.quote => '引用',
      BlockType.code => '代码块',
      BlockType.math => '公式块',
      BlockType.divider => '分隔线',
      _ => '段落',
    };
    final s = src.replaceAll('\n', ' ').trim();
    final snippet = s.length > 24 ? '${s.substring(0, 24)}…' : s;
    return '$name「$snippet」';
  }

  /// 块间距（挂在该块第一个 FlowUnit 的 leadingGap 上）
  double _gapBefore(BlockType t) {
    final double body = _s.bodyFontSize;
    return switch (t) {
      BlockType.heading1 => body * 1.1,
      BlockType.heading2 => body * 0.95,
      BlockType.heading3 => body * 0.8,
      BlockType.math => body * 0.9,
      BlockType.divider => body * 0.5,
      _ => body * 0.7,
    };
  }

  // ---------------- 单元 → widget ----------------

  Widget _buildUnitWidget(_Unit u, int? caretRel, {bool interactive = false}) {
    final double body = _s.bodyFontSize;
    final TextStyle base = TextStyle(
      fontSize: body,
      height: _s.lineHeight,
      color: Colors.black87,
      // ★★ 2026-10-20（N3）：正文带**系统字体回退链** ——
      //   `⟺` 这类符号中文主字体没有字形，不回退就是豆腐块。
      fontFamilyFallback: kCjkFallback,
    );
    final _Rendered r = _renderParts(u.type, u.source);
    final String text = r.text;
    // ★★ ⑤ 选区 → **本单元的局部区间**（渲染坐标）。与本单元无交集 ⇒ null。
    final ({int from, int to})? sel = _localSelFor(u);
    final int? selFrom = sel?.from;
    final int? selTo = sel?.to;
    // 光标在本单元内时换算成**绝对偏移**（InlineMathText 用的是绝对偏移）
    // ★ ⑤ 有选区时**不画光标**（标准编辑器行为：选区就是"当前操作对象"，光标让位）
    final int? caretAbs = _caretAbsFor(u, caretRel);
    // ★★ 2026-10-18：注入空槽垫子用的是**逻辑位置**（不看闪烁、不看选区）。
    //   垫子是"注进 TeX 的字形"，会改版面宽度；跟着闪烁走 ⇒ 整段每秒重排两次
    //   （用户实测："虚线框若隐若现 + 排版闪动"）。
    final int? slotCaretAbs = _slotCaretAbsFor(u, caretRel);
    // ★ 组合中间态：只接给含光标的那一个单元，且行间公式块不接（见 _composingFor）
    final String composing = _composingFor(u, caretRel);
    // 只有渲染树需要接点击（测量树是离屏的，接了也没用，还会多两个对象）
    final void Function(ProjectionSegment, String, Offset, GlobalKey)? onMathTap =
        interactive
            ? (ProjectionSegment seg, String rt, Offset g, GlobalKey k) =>
                _onMathTap(u, seg, rt, g, k)
            : null;
    // ★★ 2026-10-18 晚（用户实测"行内矩阵右键没反应"）：行内公式也要能右键改尺寸。
    //   `_resizeEnvAt` 只要一个"落在这段公式里"的文档偏移 ⇒ 传这段的起点即可。
    final void Function(int absOffset)? onMathRight = interactive
        ? (int at) => widget.onEnvResizeRequest?.call(at)
        : null;

    switch (u.type) {
      case BlockType.heading1:
      case BlockType.heading2:
      case BlockType.heading3:
        final double size = switch (u.type) {
          BlockType.heading1 => _s.heading1Size,
          BlockType.heading2 => _s.heading2Size,
          _ => _s.heading3Size,
        };
        // ★ S3-2：标题也走 InlineMathText —— 标题里的行内公式要渲染，且光标要进得去
        return InlineMathText(
          source: text,
          baseOffset: u.renderBase,
          caretOffset: caretAbs,
                slotCaretOffset: slotCaretAbs,
          selStart: selFrom,
          selEnd: selTo,
          composingText: composing,
          mathFontSize: size,
          // ★★ 2026-10-20（T-C 实测 F16）：导出抓图时**不画任何编辑辅助**
          //   （空槽虚线框 / 当前槽淡蓝底 / 光标竖条 / 选区底块）——它们不是文档内容。
          showEditingAids: !_hideForCapture,
          onMathTap: onMathTap,
          onMathRightClick: onMathRight,
          textStyle: TextStyle(
            fontFamilyFallback: kCjkFallback,
            fontSize: size,
            fontWeight: FontWeight.bold,
            height: 1.35,
            color: Colors.black,
          ),
        );

      case BlockType.bulletList:
      case BlockType.orderedList:
        final ListMarker? m = BlockMarkers.listMarker(u.source);
        final String marker = m == null ? '•' : (m.ordered ? m.raw : '•');
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: body * 1.7,
              child: Text(marker, style: base),
            ),
            Expanded(
              child: InlineMathText(
                source: text,
                baseOffset: u.renderBase,
                caretOffset: caretAbs,
                slotCaretOffset: slotCaretAbs,
                selStart: selFrom,
                selEnd: selTo,
                composingText: composing,
                mathFontSize: body,
                onMathTap: onMathTap,
          onMathRightClick: onMathRight,
                textStyle: base,
              ),
            ),
          ],
        );

      case BlockType.quote:
        return Container(
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: Colors.grey.shade400, width: 3),
            ),
          ),
          child: InlineMathText(
            source: text,
            baseOffset: u.renderBase,
            caretOffset: caretAbs,
                slotCaretOffset: slotCaretAbs,
            selStart: selFrom,
            selEnd: selTo,
            composingText: composing,
            mathFontSize: body,
            onMathTap: onMathTap,
          onMathRightClick: onMathRight,
            textStyle: base.copyWith(color: Colors.black54),
          ),
        );

      case BlockType.math:
        // 行间公式：注入链只有**一个入口**（`slot_marks.renderMathTex`）——
        // 先注空槽占位（★ 光标不在里面时**也要注**：空槽必须一直看得见，见该函数注释），再按需注光标。
        final String tex = renderMathTex(
          text,
          // ★ 垫子看逻辑位置（闪烁/选区不影响），竖条看视觉位置（同 renderMathTex 的说明）
          caretRel:
              slotCaretAbs == null ? -1 : slotCaretAbs - u.renderBase,
          showCursor: caretAbs != null,
        );
        // ★★ 批 16（2026-10-24 用户拍板"变矮"）：光标在**脚本槽**（`^` / `_` 的内容）里
        //   ⇒ 竖条单独缩矮（与行内公式同一判据、同一函数）。
        //   ★ 位点表按**源码** `text` 建（不是注入过的 `tex`）—— 注入会挪偏移。
        //   ★ 块前/块后那两格用 `caretEdge` 那条路，不看这个值。
        final int texRel = slotCaretAbs == null ? -1 : slotCaretAbs - u.renderBase;
        final bool caretScript = texRel >= 0 && isScriptSite(text, texRel);
        // ⚠️ 2026-10-15 晚：原先这里给整段行间公式刷淡色底（§6.5 旧版），**已撤** ——
        //    它把"渲染提示"画成了"一个对象"（用户指出 `$\frac{a}{b}=\sqrt{2}$` 是三个对象）。
        //    见 `inline_math_text.kMathRangeColor` 的注释与《编辑地基与手感》§六-6。
        // ★★ 光标：行间公式同样走"零尺寸锚点 + 自绘竖条"（`MathWithCaret`）。
        final GlobalKey mathKey = interactive
            ? _mathBlockKeys.putIfAbsent(u.id, () => GlobalKey())
            : GlobalKey();
        // ★★ 层级（§11.27）：块**之前 / 之后**那两格由块认领（③-C，否则光标没处落），
        //   但它们**视觉上属于文本层** ⇒ 让竖条按**文本层标准**画（字号×1.25、贴基线）。
        //   ⚠️ 判"在块外"必须用**原始缓冲区光标** `_caret`（不是 `caretAbs`）——
        //      `relFor()` 会把两端**夹进** `[renderBase, renderEnd]`，用 clamped 值判
        //      `caretAbs > renderEnd` **永远不成立**（2026-10-16 实测：用户看到的
        //      "行间还是分母位高度"就是这个），块后那一格会退回数学层标准。
        final int? rawCaret = _caret;
        // ★★★ 2026-10-24（批 21，用户实测"有时候会出现同时存在两个光标"）：
        //   边界竖条只在光标**紧贴**这一块时才画 —— 原来是 `< / >`，
        //   于是"两个行间块之间那一段空白"同时满足 A 的"块之后"和 B 的"块之前"
        //   ⇒ **两个块各画一根竖条** ⇒ 屏幕上两根光标。
        //   改成**相等**判据：A 只认 `A.end`、B 只认 `B.start - 1`。
        //
        //   ★ 但两个**紧挨着**的行间块（中间只有一个 `\n`）会让这个格**同时**属于
        //     A 的"块之后"与 B 的"块之前" ⇒ 仍然两根。判据：本块左邻是不是**另一个行间块的收尾 `$$`**
        //     （`buf[renderBase-1] == '\n' && buf[renderBase-2] == '$'`）⇒ 这一格**让给左边那块**
        //     （它画"块之后"），本块不画"块之前" ⇒ 共享格上恒为**一根**竖条。
        final String src = widget.buffer.buf;
        // 左邻是不是**另一个行间块的收尾 `$$`**（`acceptFrom` 那一格是换行、再前一格是 `$`）
        final bool sharesLeftCell = u.acceptFrom >= 1 &&
            u.acceptFrom < src.length &&
            src[u.acceptFrom] == '\n' &&
            src[u.acceptFrom - 1] == r'$';
        final ({bool before, bool after}) edge = blockEdgeClaim(
          caret: rawCaret,
          acceptFrom: u.acceptFrom,
          acceptTo: u.acceptTo,
          sharesLeftCell: sharesLeftCell,
        );
        final bool beforeBlock = edge.before;
        final bool afterBlock = edge.after;
        // ★★ ④-5：行间公式用**自己的字号**（`DocSettings.effectiveDisplayFontSize`，
        //   默认 = 正文 × 1.25）。块内的光标不需要另设判据 —— 它取自当地 ¶ 盒（自动跟随）；
        //   块**之前 / 之后**那两格仍按**段落文本层**标准（`textFontSize: body`，§11.27）。
        final double display = _s.effectiveDisplayFontSize;
        // ★★ §6.1.1（2026-10-18）：**空的公式块也要看得见**（同上，行内那份的理由）。
        //   行间块的内容被删光时，`renderMathTex('')` 是零尺寸 ⇒ 同理是个幽灵。
        if (text.trim().isEmpty) {
          return Center(
            child: EmptyMathMark(
              width: display * 1.2,
              height: display * 1.1,
              // ★ 批 22：共享那一格让给左边那块 ⇒ 本块不画（否则屏幕上两根光标）
            showCaret: blockShowsCaret(
                caret: rawCaret,
                acceptFrom: u.acceptFrom,
                acceptTo: u.acceptTo,
                sharesLeftCell: sharesLeftCell),
              // ★ F16：导出抓图时不画这个虚线小框（它是编辑态的标记）
              showEditingAids: !_hideForCapture,
            ),
          );
        }
        return Center(
          // ★★ 2026-10-18（PC-5 右键入口）：行间块上**右键** ⇒ 请求改尺寸。
          //   只有多行环境（矩阵/行列式）会被 EditView 接住；其它公式右键什么都不发生。
          //   ★★ 2026-10-18 晚（用户实测"右键矩阵内部没反应，只有点到括号上才认"）：
          //   默认 `deferToChild` 时，**两个格子之间的空白**没有子节点认领 ⇒ 这个手势
          //   根本不在命中路径上 ⇒ 右键落在空白处什么都不发生。
          //   ⇒ `HitTestBehavior.opaque`：整块公式（含内部空白）都归它接次级点击。
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: widget.onEnvResizeRequest == null
                ? null
                : (TapDownDetails _) =>
                    widget.onEnvResizeRequest!(u.renderBase),
            // ★★ 2026-10-20（N1）：**行间公式超宽时等比缩小到正文宽**。
            //   用户实测：一条长推导（`limsup{x_n+y_n}=lim(sup{…})≤…`）会顶出页面右缘、
            //   画出 Flutter 的溢出条纹，PDF 里也会被截断。
            //   为什么用 FittedBox 而不是"折行"：折行要判断在哪个关系符处断，
            //   语义与间距都会变；而**等比缩小**只影响这一行的视觉大小，语义不变、位置不变。
            //   FittedBox 的命中测试是逆变换过的（`RenderFittedBox.hitTestChildren`）⇒
            //   点公式、光标进公式这些交互仍然准。`scaleDown` 保证**不会放大**小公式。
            child: LayoutBuilder(builder: (BuildContext c, BoxConstraints cons) {
              final Widget math = MathWithCaret(
              tex: tex,
            // ★ ⑤ 选区：行间公式整块是一个对象（用户拍板）—— 被选中就铺整块
            selFrom: selFrom,
            selTo: selTo,
            // 块前那一格（`renderBase - 1`）也要画 —— 它已被本单元认领（acceptFrom）
            // ★ 批 22：共享那一格让给左边那块 ⇒ 本块不画（否则屏幕上两根光标）
            showCaret: blockShowsCaret(
                caret: rawCaret,
                acceptFrom: u.acceptFrom,
                acceptTo: u.acceptTo,
                sharesLeftCell: sharesLeftCell),
            // ★ 批 16：脚本槽 ⇒ 竖条变矮（判据同上，源码位点）
            caretScript: caretScript,
            caretEdge: beforeBlock
                ? CaretEdge.before
                : (afterBlock ? CaretEdge.after : CaretEdge.none),
            textFontSize: body,
            mathKey: mathKey,
            fontSize: display,
            mathStyle: MathStyle.display,
            // ★★ F16：导出抓图时不画编辑辅助（行间公式的空槽虚线框最常被抓进 PDF）
            showEditingAids: !_hideForCapture,
            onErrorFallback: (e) => Tooltip(
              message: e.messageWithType,
              child: const Text(
                '［公式不完整］',
                style: TextStyle(color: Color(0xFFB08968), fontSize: 13),
              ),
            ),
            );
            if (!cons.maxWidth.isFinite) return math;
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: math,
            );
            }),
          ),
        );

      case BlockType.code:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          color: const Color(0xFFF5F5F5),
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: body * 0.88,
              height: 1.5,
            ),
          ),
        );

      case BlockType.divider:
        // ★★ 批 27：分界线这一行**也要看得见光标**（它没有任何文本能挂光标 ⇒ 自己画一根）。
        //   用户 2026-10-24 实测「点分界线下面那行光标不显示」—— 除下面那个空行之外，
        //   `---` 这三格本身同样是死区（点上去光标移过去了，屏幕上什么都没有 = 平权反例）。
        //   ★ 竖条画在**行首**（这一行没有可参照的字形，固定左边），
        //     高度用文本层标准（与"文字后面的光标"同一把尺），溢出 12px 的行高（`Clip.none`）。
        final bool dividerCaret = !_hideCaret &&
            widget.caretVisible &&
            u.relFor(_caret) != null;
        final double dividerCaretH = textCaretHeight(body);
        return SizedBox(
          height: 12,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              const Positioned.fill(
                child: Center(child: Divider(height: 1, thickness: 1)),
              ),
              if (dividerCaret)
                Positioned(
                  left: 0,
                  top: (12 - dividerCaretH) / 2,
                  child: Container(
                    width: 1.5,
                    height: dividerCaretH,
                    color: const Color(kCaretColorValue),
                  ),
                ),
            ],
          ),
        );

      case BlockType.pageBreak:
        return const SizedBox.shrink();

      case BlockType.paragraph:
        return InlineMathText(
          source: text,
          baseOffset: u.renderBase,
          caretOffset: caretAbs,
                slotCaretOffset: slotCaretAbs,
          selStart: selFrom,
          selEnd: selTo,
          composingText: composing,
          mathFontSize: body,
          onMathTap: onMathTap,
          onMathRightClick: onMathRight,
          textStyle: base,
        );
    }
  }

  /// 渲染文本 + 它在**原始切片**里的起点（S3-2：光标偏移换算的唯一真相）
  static _Rendered _renderParts(BlockType t, String src) {
    switch (t) {
      case BlockType.heading1:
      case BlockType.heading2:
      case BlockType.heading3:
        return _headingParts(src);
      case BlockType.quote:
        return _quoteParts(src);
      case BlockType.bulletList:
      case BlockType.orderedList:
        final ListMarker? m = BlockMarkers.listMarker(src);
        final int off = m?.contentStart ?? 0;
        return _Rendered(off == 0 ? src : src.substring(off), off);
      case BlockType.math:
        return _mathParts(src);
      case BlockType.code:
        return _codeParts(src);
      case BlockType.divider:
      case BlockType.pageBreak:
        return const _Rendered('', 0);
      case BlockType.paragraph:
        return _Rendered(src, 0);
    }
  }

  static _Rendered _headingParts(String src) {
    final m = RegExp(r'^ {0,3}#{1,6} +').firstMatch(src);
    final int off = m?.end ?? 0;
    return _Rendered(off == 0 ? src : src.substring(off), off);
  }

  static _Rendered _quoteParts(String src) {
    final m = RegExp(r'^ {0,3}> ?').firstMatch(src);
    final int off = m?.end ?? 0;
    return _Rendered(off == 0 ? src : src.substring(off), off);
  }

  /// `$$` 行间公式：剥掉围栏，并给出正文的起点
  static _Rendered _mathParts(String src) {
    final List<String> ls = src.split('\n');
    if (ls.length == 1) {
      final String raw = ls.first;
      final String t = raw.trim();
      final int lead = raw.length - raw.trimLeft().length;
      var body = t;
      if (body.startsWith(kMathFence)) {
        body = body.substring(kMathFence.length);
      }
      if (body.endsWith(kMathFence)) {
        body = body.substring(0, body.length - kMathFence.length);
      }
      return _Rendered(body, lead + kMathFence.length);
    }
    final bool closed = ls.last.trim().startsWith(kMathFence);
    final List<String> inner =
        closed ? ls.sublist(1, ls.length - 1) : ls.sublist(1);
    return _Rendered(inner.join('\n'), ls[0].length + 1);
  }

  static _Rendered _codeParts(String src) {
    final List<String> ls = src.split('\n');
    if (ls.length <= 2) return const _Rendered('', 0);
    final bool closed = ls.last.trimLeft().startsWith(kFence);
    final List<String> inner =
        closed ? ls.sublist(1, ls.length - 1) : ls.sublist(1);
    return _Rendered(inner.join('\n'), ls[0].length + 1);
  }

  // ---------------- 测量 → 分页 ----------------

  List<double> _readHeights() {
    final RenderObject? ro = _measureRootKey.currentContext?.findRenderObject();
    if (ro is! RenderBox) return const <double>[];
    final out = <double>[];
    ro.visitChildren((RenderObject c) {
      if (c is RenderBox && c.hasSize) out.add(c.size.height);
    });
    return out;
  }

  bool _statsScheduled = false;

  void _scheduleStatsOnce() {
    if (_statsScheduled) return;
    _statsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _statsScheduled = false;
      if (mounted) _emitStats();
    });
  }

  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final List<double> hs = _readHeights();
      if (hs.length != _units.length) return;

      var changed = hs.length != _heights.length;
      if (!changed) {
        for (var i = 0; i < hs.length; i++) {
          if ((hs[i] - _heights[i]).abs() > 0.01) {
            changed = true;
            break;
          }
        }
      }
      // ★★★ 2026-10-18 晚（P5 探针抓到的**真缺陷**）：**正文变了就得重排**。
      //   原来只比"单元高度"⇒ 有一种改动**高度完全不变、位置必须变**：
      //     `甲\n\n乙` → `甲\n\n\n乙`（多一个空行：单元高度一个像素都没动，
      //     变化全在**段距**里）⇒ `changed == false` ⇒ `_layout` 沿用旧的 ⇒
      //     **连按 Enter 不长高**（用户报的"空行不占行"的现象之一）。
      //   ⇒ 把"正文"也纳入判据：正文与上次分页时不同 ⇒ 重排。
      final String bufNow = widget.buffer.buf;
      if (!changed && bufNow != _layoutSource) changed = true;
      if (!changed && _layout != null) return;
      // ★★ 2026-10-18 晚：**零单元也必须分页一次**。
      //   空文档前 `hs` 与 `_units` 都是空 ⇒ `changed == false` ⇒ 这里原来直接 return
      //   ⇒ `_layout` 永远是 `null` ⇒ 界面上根本没有"页"（只有"正在分页…"），
      //     于是连"文末那片空白"都不存在 ⇒ **点哪儿都落不了光标**。
      //   `paginate` 对空列表会自己补一页（`if (pages.isEmpty) pages.add([])`），
      //   所以这里放进来的代价就是"多一页空白纸"—— 那正是新建文档该有的样子。

      setState(() {
        _heights = hs;
        _layoutSource = bufNow;
        _layout = paginate(
          items: _itemsFrom(hs),
          bodyHeight: _m.bodyHeight,
          // ★ 文首空行：挂在第一页顶部（不能挂 leadingGap —— 页首不留段前距）。
          //   ★ 与"块之间"不同：文首**每一个**空行都占一整行（前面没有"上一段"要分隔，
          //     所以不存在"第一个空行只是段距"这回事）。
          topInset: leadingBlankHeight(_blankRunAtStart().length,
              lineHeight: _blankLineHeight),
        );
      });
      _emitStats();
    });
  }

  /// 标题类（三级都算）——用于分页的"不许落单在页底"
  static bool _isHeadingType(BlockType t) =>
      t == BlockType.heading1 || t == BlockType.heading2 || t == BlockType.heading3;

  /// 尾部空行那个"占位 item"的 id（不产单元，只让分页器知道这里还有高度）
  static const String _kTailBlankItem = '\u0000tail-blank';

  List<FlowItem> _itemsFrom(List<double> hs) {
    final List<FlowItem> items = <FlowItem>[];
    for (var i = 0; i < _units.length; i++) {
      // ★★★ 2026-10-27（用户实测："原页一直 Enter 往下，光标进入异次元空间"）：
      //   **硬分页之前那串空行**原来只作为"下一个单元的 leadingGap"结算 ——
      //   而那个单元带 `breakBefore`、永远从新页开始，**页首不留段前距** ⇒ 高度被整个丢掉。
      //   结果：页面不长、光标却按"第几个空行"一路下移（探针：第 1 页底 1163 不变，光标 154→734）。
      //   ⇒ 把这串空行做成**占位 item 排在分页符那个单元之前**（与末页同一套），
      //     它跟正文一样会被 flush：写满一页就流到下一页，分页符再把后面的内容推到再下一页
      //     （与 Word 里"在手动分页符上方加空段落"的表现一致）。
      if (i > 0 && _units[i].breakBefore) {
        // ★★ 2026-10-27（与文末同一条尺子）：**这一页底部的行** = `_rowsAfter(前一个单元)`，
        //   一行一个 item；每一项 = 一个段（行盒 + 段间距）。分页符块自己不占行，
        //   所以"分页符行首"那一行必须由这里 reserve 出来 —— 否则原页底部那片白
        //   根本没有行盒，光标画上去就出了版面。
        final int nRows = _rowsAfter(_units[i - 1]).length;
        for (var k = 0; k < nRows; k++) {
          // ★ 第 0 个盒子从"上一段行盒底"起算（它还要承接**段距那一格**的位置），
          //   所以行盒 + 段距整块给它；后面的每个盒子 = 行盒 + 段间距。
          items.add(k == 0
              ? FlowItem(
                  id: '$_kTailBlankItem#b$i#$k',
                  height: _lineBox + _paraGap)
              : FlowItem(
                  id: '$_kTailBlankItem#b$i#$k',
                  height: _lineBox,
                  leadingGap: _paraGap));
        }
      }
      items.add(FlowItem(
        id: _units[i].id,
        height: hs[i],
        // ★★ 2026-10-18 晚（§11.46 真修）：段距之外还要加上**真空段落**的高度。
        //   规则：上一个单元之后有 n 个连续空行 ⇒
        //     n <= 1 ⇒ 只是段距（一个空行 = 段落边界，视觉上是"一点段距"）
        //     n >= 2 ⇒ 多出 (n-1) 个**整行**（用户连按 Enter 出来的那些空行要真占高）
        leadingGap: _units[i].isFirstInBlock && i > 0
            ? _gapBefore(_units[i].type) +
                extraBlankHeight(_blankRunAfter(_units[i - 1]).length,
                    lineHeight: _blankLineHeight)
            : 0,
        breakBefore: _units[i].breakBefore,
        // ★★ 2026-10-20（N5）：标题不许孤零零留在页底
        keepWithNext: _isHeadingType(_units[i].type),
        label: _units[i].label,
      ));
    }
    // ★★★ 2026-10-27（用户实测：页面写满后文末连按 Enter，光标画到纸外、页数不变）：
    //   **尾部空行也要参与自动分页**。原来空行高度只作为"下一个单元的 leadingGap"结算，
    //   文末后面没有下一个单元 ⇒ 分页器根本不知道那里还有高度（探针：45 次 Enter 页数一直 3，
    //   第 42 次起光标 y 超过末页底）。
    //   ⇒ 末尾追加一个"占位 item"（有高度、无单元），它跟正文一样会被 flush 到下一页。
    //      `n <= 1` 时高度是 0（只是段距）⇒ 不追加，行为与改前完全一致。
    // ★ 2026-10-27（统一行高）：尾部区域 = n 个空行 **+ 1 个"当前行"**（光标停的那一行，
    //   Word 里那个总是存在的段落标记），**一行一个 item**、每行 = 一个正文行距。
    //   文档没有尾换行时（`甲` 打字的中间态）当前行就是正文那一行 ⇒ 不额外占位。
    if (_units.isNotEmpty && widget.buffer.buf.endsWith('\n')) {
      // ★ 2026-10-27：行数与 `_rowsAfter` **同一条规则**（空行串[1..] + 一个待写行），
      //   `#t#k` 的 k 就是 `tailRows` 的下标。
      //   ★ 每一项 = **一个段**：行盒（拍照）+ 段间距（`leadingGap`）——
      //   这就是"拆行高/段间距"：一行占 行盒 + 段距，而不是一个 38.4 的整块。
      final int nTailRows = _rowsAfter(_units.last).length;
      for (var k = 0; k < nTailRows; k++) {
        // ★ 第 0 个盒子 = 行盒 + 段距（它同时承接"段距那一格"的位置），其余 = 行盒 + 段间距。
        items.add(k == 0
            ? FlowItem(
                id: '$_kTailBlankItem#t#$k', height: _lineBox + _paraGap)
            : FlowItem(
                id: '$_kTailBlankItem#t#$k',
                height: _lineBox,
                leadingGap: _paraGap));
      }
    }
    return items;
  }

  /// **行盒**：一行文字自己的高度（字号 × 行距）。
  ///
  /// ★★★ 2026-10-27（只读基准 6「彻底区分行/段/行间距/段间距」）：
  ///   以前这里把"段间距"折进了"空行高度"（`_blankLineHeight = 行盒 + 段距`），
  ///   数值对、概念错 —— 于是没人说得清"一行到底多高"（量出 38 / 31 / 20 三种值）。
  ///   现在三个量分开：**行盒** = 这一行自己；**段间距** = 两段之间让开的那一截；
  ///   **一行**（= 一个段）= 行盒 + 段间距。
  double get _lineBox => _s.bodyFontSize * _s.lineHeight;

  /// **段间距**：相邻两段之间让开的那一截（段落在页首时不留）。
  double get _paraGap => _gapBefore(BlockType.paragraph);

  /// **光标在一行里的垂直内缩**：行盒比光标条高，文本层把光标**居中**放。
  ///
  /// ★ 空行、文字行、文末那一行都必须用这同一个内缩，否则"光标在这儿、字却低一截"
  ///   （探针实测：(27.2 − 20) / 2 = 3.6 px，正是用户说的"低一截"）。
  double get _caretInset =>
      (_lineBox - textCaretHeight(_s.bodyFontSize)) / 2;

  /// **一行（一个段）占的高度** = 行盒 + 段间距。
  double get _blankLineHeight => _lineBox + _paraGap;

  /// 从 [from]（**必须是行首**）起的连续**空行**，返回每个空行的行首偏移。
  ///
  /// ★ 判据本体在 `blank_runs.dart`（纯函数，可单测 —— 它决定"要不要占一整行高"）。
  List<int> _blankRunFrom(int from) => blankRunFrom(widget.buffer.buf, from);

  /// 上一个单元之后那串空行的**行首偏移**（没有 ⇒ 空表）
  List<int> _blankRunAfter(_Unit prev) =>
      blankRunAfter(widget.buffer.buf, prev.acceptTo);

  /// [prev] 之后**这一页底部那些"行"**的行首偏移（只读基准 4：末页与分页原页同一条规则）。
  ///
  /// = 已有的空行（每行一个偏移）＋ **一个待写行**：
  ///   · 后面紧跟**分页符** ⇒ 待写行 = **分页符行的行首**（那 19 格本来就存在，零像素）；
  ///   · 否则 ⇒ 待写行 = **文末**（EOF）。`DocBuffer` 保证非空文档以 `\n` 收尾，
  ///     所以 EOF 与"文末行的行末"是**两个不同的整数偏移**，这一行不是假位置。
  ///
  /// 为什么必须补这一行：分页符块不产单元、文末后面没有下一段 ⇒ 两边都"没人画这一行"，
  /// 而用户要的是"文末下一行这个空行**永远**能承接光标"（基准 3 最后一句）。
  List<int> _rowsAfter(_Unit prev) {
    final String buf = widget.buffer.buf;
    final List<int> blanks = _blankRunAfter(prev);
    // ★ 空行串里**第一个**只是"段距那一截"（它属于上一段的行盒之后、下一段之前），
    //   从第二个起才是真正的**行**（探针坐实：`A⏎⏎⏎B` 只有 1 个空行是行，第 2 个 `⏎` 之前那格
    //   在上面一行的行盒里）。所以行表 = `blanks.skip(1)`。
    final List<int> rows = <int>[...blanks.skip(1)];
    final int at = prev.acceptTo.clamp(0, buf.length);
    int next = at;
    if (at < buf.length && buf[at] == '\n') next = at + 1;
    if (blanks.isNotEmpty) next = (blanks.last + 1).clamp(0, buf.length);
    if (next < buf.length) {
      final int nl = buf.indexOf('\n', next);
      final String line = buf.substring(next, nl < 0 ? buf.length : nl);
      if (BlockMarkers.isPageBreak(line)) {
        rows.add(next); // 待写行 = 分页符行首
        return rows;
      }
    }
    rows.add(buf.length); // 待写行 = 文末
    return rows;
  }

  /// 光标落在 [rows] 的哪一行
  int _caretRowIndexIn(List<int> rows) {
    final int c = _caret ?? -1;
    if (c < 0 || rows.isEmpty) return 0;
    var k = 0;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i] <= c) {
        k = i;
      } else {
        break;
      }
    }
    return k;
  }

  /// [prev] 之后**每一个可落位置**的行首偏移 = 空行串（全部）+ 待写行。
  ///
  /// ★ 与 `_rowsAfter` 的区别：那个只给"**行**"（第一个空行只是段距，不是行）；
  ///   这个给"**位置**"—— 第一个空行也是一个真实偏移（换行符也是真实位置），
  ///   光标站上去必须看得见，所以必须有主人。
  List<int> _rowSlotsAfter(_Unit prev) {
    final String buf = widget.buffer.buf;
    final List<int> blanks = _blankRunAfter(prev);
    final List<int> slots = <int>[...blanks];
    final int at = prev.acceptTo.clamp(0, buf.length);
    int next = at;
    if (at < buf.length && buf[at] == '\n') next = at + 1;
    if (blanks.isNotEmpty) next = (blanks.last + 1).clamp(0, buf.length);
    if (next < buf.length) {
      final int nl = buf.indexOf('\n', next);
      final String line = buf.substring(next, nl < 0 ? buf.length : nl);
      if (BlockMarkers.isPageBreak(line)) {
        slots.add(next);
        return slots;
      }
    }
    slots.add(buf.length);
    return slots;
  }

  /// 空行串里第 [i] 个位置相对**槽顶**的纵向偏移。
  ///
  /// · `i < firstRow` ⇒ 它是"**段距那一截**"：紧贴上一段行盒底（段内行位置），没有段距；
  /// · 否则 ⇒ 第 `i - firstRow` 个**段**：段距 + k × 一行 + 行内内缩。
  ///
  /// [firstRow] = "第一个真正的行"在表里的下标：空行串**非空**时第一个空行只是段距那一截
  /// （`firstRow = 1`）；空行串为空时第 0 个就是待写行本身（`firstRow = 0`）。
  /// 这就是"彻底区分行 / 段 / 行间距 / 段间距"（只读基准 6）落到像素上的那一条。
  double _blankDy(int i, {double? gap, int firstRow = 1}) {
    final double g = gap ?? _paraGap;
    if (i < firstRow) return _caretInset;
    return g + (i - firstRow) * _blankLineHeight + _caretInset;
  }

  List<double> _blankDys(int n, {double? gap, int firstRow = 1}) =>
      <double>[for (var i = 0; i < n; i++) _blankDy(i, gap: gap, firstRow: firstRow)];

  /// 文档**开头**那串空行（文首空行，记账 #2）
  List<int> _blankRunAtStart() {
    final String s = widget.buffer.buf;
    if (s.isEmpty) return const <int>[];
    return _blankRunFrom(0);
  }

  /// 光标落在 [run] 的**第几个空行**上（不在这一段里 ⇒ null）
  int? _caretLineIndexInRun(List<int> run) {
    final int? c = _caret;
    if (c == null || run.isEmpty) return null;
    final String s = widget.buffer.buf;
    for (var i = 0; i < run.length; i++) {
      final int start = run[i];
      final int nl = s.indexOf('\n', start);
      final int end = nl < 0 ? s.length : nl;
      if (c >= start && c <= end) return i;
    }
    return null;
  }

  // ---------------- 渲染 ----------------

  Widget _pageWidget(PageLayout layout, int p) {
    final slots = layout.pages[p];
    final children = <Widget>[];
    final warnings = <String>[];
    var bottom = 0.0;
    _Unit? prevUnit;
    // 尾部区域第一行的缓冲区偏移（`#t#k` 的 k = 第几行；行首偏移 = tailRows[k]）
    final int tailAfter =
        _units.isEmpty ? -1 : _blankOffsetAfter(_units.last);
    // ★ 2026-10-27：尾部那些"行"的行首偏移 —— 与分页原页**同一个函数**（`_rowsAfter`）。
    final List<int> tailRows =
        _units.isEmpty ? const <int>[] : _rowsAfter(_units.last);
    final int len = widget.buffer.buf.length;
    var tailLinesOnPage = 0;
    // ★ 2026-10-27：本页上"硬分页之前那些行"的个数（> 0 ⇒ 接缝槽不再画光标，避免一像素两主）
    var breakRowsOnPage = 0;

    for (final PageSlot s in slots) {
      final double gap = s.y - bottom;
      final _Unit? u = _unitById[s.item.id];
      // ★★ ⑥「空行是一等公民」· 丙（2026-10-17 用户拍板）：
      //   块与块之间那段空白（`SizedBox(height: gap)`）**原来谁都不管** ——
      //   空行被块模型当成"一个边界"（R1，不产生块）⇒ 没有单元 ⇒ **没有渲染物**
      //   ⇒ 光标没人画、点击落到虚空。⇒ 把这段空隙做成**空行槽**：
      //     · 版面**一个像素都不变**（还是那个 `gap` 的高度）；
      //     · 点它能落到**空行的位点**（`caret = 空行起点`）；
      //     · 光标在空行上时，它自己画那根竖条（文本层标准，可溢出空隙、不撑版面）。
      if (gap > 0.5) {
        // ★★ 2026-10-18 晚（§11.46 真修）：这段空隙可能覆盖**多个空行**
        //   （用户连按 Enter 出来的"真空段落"）⇒ 用行表，不用单个 offset。
        //   · 第一个单元之前（`prevUnit == null`）⇒ 那是**文首空行**（记账 #2），
        //     它在第 1 页顶部（`paginate(topInset:)` 给它留了高）；
        final List<int> run = prevUnit != null
            ? _blankRunAfter(prevUnit)
            : (p == 0 ? _blankRunAtStart() : const <int>[]);
        // ★★★ 2026-10-27（`caret_ownership_global_test` ③ 当场抓到的双光标）：
        //   `u == null` 就是"**本页最后一个单元之后**"那段空行 —— 它由**末页槽**认领
        //   （末页槽的 `dy = 段距 + k × 行高`，量的是同一串空行）。
        //   这里再建一个块间空行槽 = 同一格像素两个主人（探针：偏移 5 画在 161 与 183 两根）。
        if (run.isNotEmpty && u != null) {
          final int? idx = _caretLineIndexInRun(run);
          // ★ 段距那一截：空隙里除了"真空段落的行"之外，前面还有一段**段距**
          final double gapBefore = prevUnit == null ? 0.0 : _gapBefore(u.type);
          // ★★ 批 23：这一行空行**是不是与下一块的 `acceptFrom` 同一格** ——
          //   是则让给块（由它画"块之前"边界条），否则屏幕上两根竖条。
          final bool drawsCaret = idx != null &&
              blankLineDrawsCaret(
                caret: _caret,
                blankStart: run[idx],
                nextAcceptFrom: u.acceptFrom,
              );
          children.add(_BlankSlot(
            id: 'blank@${run.first}',
            height: gap,
            offset: run.first,
            lineOffsets: run,
            lineDys: _blankDys(run.length, gap: gapBefore),
            gapBefore: gapBefore,
            lineHeight: _blankLineHeight,
            caretHere: !_hideCaret &&
                widget.caretVisible &&
                drawsCaret,
            // 空行的行盒从 gapBefore 起算 ⇒ 光标落在"它真正会落脚"的那一行上
            // ★ 2026-10-27：再补一个**行内垂直内缩**（光标在行盒里居中）——
            //   少了这 3.6px 就是用户说的"光标在这儿、打出来的字低一截"。
            caretDy: drawsCaret ? _blankDy(idx, gap: gapBefore) : null,
            caretHeight: textCaretHeight(_s.bodyFontSize),
            caretWidth: 1.5,
            caretColor: const Color(kCaretColorValue),
            onTap: (int at, Offset global) => widget.onTapOffset?.call(at, global, TapSource.text),
            onBox: (String id, RenderBox box) => _blankBoxes[id] = box,
          ));
        } else {
          children.add(SizedBox(height: gap));
        }
      }
      if (u == null) {
        // ★★★ 2026-10-27（统一行高）：尾部/页尾空行现在是**一行一个 item**，
        //   每一行都要**真的占版面**、并由它自己画光标 —— 否则"分页器算了高度、
        //   页面视觉却不长"，光标会一路画到纸外（用户："进入异次元空间"）。
        final String id = s.item.id;
        if (id.startsWith(_kTailBlankItem)) {
          final int pos = id.lastIndexOf('#');
          final int? k = pos < 0 ? null : int.tryParse(id.substring(pos + 1));
          final bool isTail = k != null && tailAfter >= 0 && id.contains('#t#');
          final bool isBreak = k != null && !isTail && id.contains('#b');
          if (isTail || isBreak) {
            // ★★★ 2026-10-27（只读基准 4）：`#t$k`（文末）与 `#b<unit>$k`（硬分页之前）
            //   **走同一套**：行首偏移取自 `_rowsAfter`（空行串[1..] + 待写行），
            //   自己画光标（接缝槽不再重复画同一格 —— 一像素一语义）。
            List<int> rows = const <int>[];
            List<int> run = const <int>[];
            if (isTail) {
              rows = tailRows;
              run = _units.isEmpty
                  ? const <int>[]
                  : _blankRunAfter(_units.last);
              tailLinesOnPage++;
            } else {
              final int h1 = id.indexOf('#b');
              final int h2 = id.indexOf('#', h1 + 2);
              final int? ui =
                  h2 > 0 ? int.tryParse(id.substring(h1 + 2, h2)) : null;
              if (ui != null && ui - 1 >= 0 && ui - 1 < _units.length) {
                rows = _rowsAfter(_units[ui - 1]);
                run = _blankRunAfter(_units[ui - 1]);
              }
              breakRowsOnPage++;
            }
            // k == 0 的盒子还背着"**段距那一格**"（空行串里第一个位置）：
            // 它紧贴上一段的行盒底，不是一整行，但**也是一个真实位置**（光标得看得见）。
            final List<int> offs = <int>[];
            final List<double> dys = <double>[];
            if (k == 0) {
              if (run.isNotEmpty) {
                offs.add(run.first);
                dys.add(_caretInset);
              }
              if (rows.isNotEmpty) {
                offs.add(rows.first);
                dys.add(_paraGap + _caretInset);
              }
            } else if (k < rows.length) {
              offs.add(rows[k]);
              dys.add(_caretInset);
            }
            // ★ 分页符行内部的格：那一行**零像素、不可见**，屏幕上就是同一格 ——
            //   所以它们与"分页符行首"共用同一个 y（批 38 的口径：那 19 格不许是死区）。
            if (isBreak && rows.isNotEmpty && k == rows.length - 1) {
              final String buf = widget.buffer.buf;
              final int pb = rows.last;
              if (pb < buf.length) {
                final int nl = buf.indexOf('\n', pb);
                final int end2 = nl < 0 ? buf.length : nl;
                final double y = k == 0 ? _paraGap + _caretInset : _caretInset;
                for (var o = pb + 1; o <= end2; o++) {
                  offs.add(o);
                  dys.add(y);
                }
              }
            }
            final int hit = offs.indexOf(_caret ?? -1);
            children.add(_BlankSlot(
              id: isTail ? 'tailline@$k' : 'breakline@$pos',
              height: s.item.height,
              offset: offs.isEmpty ? len : offs.last,
              lineOffsets: offs,
              lineDys: dys,
              caretHere: !widget.hideCaretAndSelection &&
                  widget.caretVisible &&
                  hit >= 0,
              caretDy: hit >= 0 && hit < dys.length ? dys[hit] : null,
              caretHeight: textCaretHeight(_s.bodyFontSize),
              caretWidth: 1.5,
              caretColor: const Color(kCaretColorValue),
              onTap: (int at, Offset _) => widget.buffer.setCaret(at),
              onBox: (String bid, RenderBox box) => _blankBoxes[bid] = box,
            ));
          } else {
            children.add(SizedBox(height: s.item.height));
          }
          bottom = s.y + s.item.height;
          continue;
        }
        children.add(SizedBox(height: s.item.height));
        bottom = s.y + s.item.height;
        continue;
      }
      // 外面套一层命中盒（子节点仍是池里缓存的同一实例 → 不破坏"整棵子树跳过"）
      children.add(_UnitHitBox(
        unit: u,
        onHit: _handleUnitHit,
        onBox: (_Unit unit, RenderBox box) => _unitBoxes[unit.id] = box,
        child: _renderPool.widgetFor(
          _poolKeyFor(u),
          () => _buildUnitWidget(u, u.relFor(_caret), interactive: true),
        ),
      ));
      prevUnit = u;
      bottom = s.y + s.item.height;
      if (s.item.height > _m.bodyHeight) {
        warnings.add('${s.item.label ?? u.type.name} 高于一页'
            '（${s.item.height.toStringAsFixed(0)} px > '
            '${_m.bodyHeight.toStringAsFixed(0)} px），已强制放在一页内、未切断');
      }
    }

    // ★★★ 批 38（2026-10-26，用户 20261026 实测）：
    //   **每一页底部的剩余白都要能点、能看见光标**。探针实测（改前）：
    //     `甲\n<!-- pagebreak -->\n`     ⇒ 偏移 2..21 **一根光标条都没有**（分页符那 19 格全死）；
    //     `甲\n<!-- pagebreak -->\n\n\n` ⇒ 全部 0（末页槽要求 `after >= 0`，而分页符行不是空行）；
    //     对照 `甲\n\n\n`                ⇒ 2..4 各 1 根（正常）。
    //   两个根因：① 分页符块不产单元（`_buildUnits` 直接 `continue`）⇒ 那 19 格没有命中盒、没有主；
    //            ② 末页槽的 `caretHere` 要求 `after >= 0`（上一单元后面必须是**空行**）
    //               ⇒ 上一单元后面跟的是**分页符行**时永远不画。
    //   口径（用户 2026-10-26 拍板 **甲-1**）：
    //     · **末页**那片白 = "文末那片空白"：点它 = 起一行空行（既有口径，本次只放宽成立条件）；
    //     · **非末页**那片白 = **接缝带**：点它**只落光标、不改文档**（⇒ 不重排、不翻页）；
    //     · 接缝带里的位置（含分页符那 19 格）由该槽认领光标条。
    final bool isLastPage = p == layout.pageCount - 1;
    final double free = (_m.bodyHeight - bottom)
        .clamp(textCaretHeight(_s.bodyFontSize), _m.bodyHeight);

    // ★★★ 2026-10-27（自动分页）：尾部空行被推到**新的一页**时，那一页没有任何单元
    //   （`prevUnit == null`）⇒ 用"**全文最后一个单元**"兜底 —— 否则新页上没人画光标，
    //   用户看到的还是"光标出页消失"。
    final _Unit? tailPrev = prevUnit ?? (_units.isEmpty ? null : _units.last);
    if (isLastPage && tailPrev != null) {
      // ★★ ⑥ 丙 · **文末那片空白 = 一行空行**（2026-10-17 用户拍板 **甲**）：
      //   「添加空行有两条途径：Enter、点下方空白」—— 两条**都会改文档**（和 Enter 一样）：
      //   点一下就在文末起一行空行、光标落在那儿；已经有一行就不再加（**幂等**）。
      //   槽的高度取**这一页剩下的正文高度** ⇒ 那片空白**整片**都能点；
      //   竖条**贴顶**画在最后一行下面。
      final int after = _blankOffsetAfter(tailPrev);
      final int tail = after >= 0 ? after : widget.buffer.buf.length;
      // ★★ 批 38：**认领范围**从"上一单元之后那一格"起 —— 不再要求后面是空行。
      //   实测现场：文末是 `…$$⏎<!-- pagebreak -->⏎⏎…`（用户在文末插了分页符），
      //   `_blankOffsetAfter` 返回 -1（下一行是分页符，不是空行）⇒ 改前 caretHere 永假
      //   ⇒ 用户"按 Enter 到下一个空行却看不见光标"（打字照旧能进，位置是真的）。
      // ★★★ 批 40（2026-10-26，用户：「每一次打完字符都有双光标」）：**认领只能在
      //   "上一单元之后还有位置"时成立** ——
      //     ① 文末真有那一行空行（`after >= 0`，2026-10-17 的旧口径）；或
      //     ② 文末紧跟**分页符行**（那 19 格确实没人认领，批 38 要解决的就是它）。
      //   ★ 否则（文档以正文结尾、**连尾换行都没有** —— 那正是"打字中"的缓冲区形态）
      //     那一格是**单元自己**的：再画一根 = 用户看到的"每打一个字就双光标"
      //     （探针实测：`aa⏎⏎bb⏎⏎cc` 在 EOF 处 175/199 两根，正好差一行）。
      final int seamTap = _seamTapTarget(tailPrev);
      // ★ 批 46：认领范围与"点击落点"分开算 —— 点击落在**最后一行行尾**（分页符之前），
      //   但**认领**仍从 `acceptTo + 1` 起（分页符那 19 格与它后面的空行都要有主）；
      //   只有"后面真的还有字符"才算（否则 `…cc` 打字的文末会与单元叠成两根）。
      final int owned = after >= 0
          ? after
          : (tailPrev.acceptTo + 1 < widget.buffer.buf.length
              ? tailPrev.acceptTo + 1
              : -1);
      // ★★★ 2026-10-27（**一次按键 = 一行**，`notes/design/行与段-空行基准.md` §三 B2）：
      //   文末有 n 行空行时，光标可能站在其中**任意一行**上，所以竖条必须按"第几个空行"落：
      //   `dy = gapBefore + k × lineH`（§11.46 P5 的算式，本来就有）。
      //   改前 `caretDy` 恒取 `_gapBefore`（等价于 k 恒 0）⇒ 用户连按 Enter，
      //   缓冲区在长、**光标一动不动**（探针：三次 Enter 光标都停在 133.79）⇒ "推不动"。
      final List<int> tailRun =
          after >= 0 ? _blankRunFrom(after) : const <int>[];
      // ★ k 取到 `run.length`：文末最后一个空行之后就是"新段落会落脚"的那一行
      //   （文末空行按 `trailingBlankHeight = n × 行高` 结算，所以 EOF 正好在最下面那行的下一行）。
      final int tailK = tailRun.isEmpty
          ? 0
          : ((_caret ?? -1) - after).clamp(0, tailRun.length);
      children.add(_BlankSlot(
        id: 'blank@$tail',
        height: free,
        offset: seamTap,
        // ★★ 2026-10-17 用户实测："enter 和点空白都能到空行了，但光标显示不出来"：
        //   插入 `\n\n` 之后缓冲区是 `…\n\n`，**光标落在 after + 1**（末尾那行空行的行首），
        //   而空行的**起点**是 `after` ⇒ 原来 `_caret == after` 永远不成立 ⇒ 一根竖条都不画。
        //   ⇒ 文末槽只要是"光标停在末尾那片空白里"就画。
        // ★★ 2026-10-18 晚：**竖条要画在"新段落真正会落脚"的位置**。
        //   用户实测：「enter 之后光标在这儿，但打出来的字符比它低一截」——
        //   差的就是这一截**段距**（新段落在上一段底下再让开 `gapBefore`）。
        caretHere: tailLinesOnPage == 0 &&
            !widget.hideCaretAndSelection &&
            widget.caretVisible &&
            owned >= 0 &&
            (_caret ?? -1) >= owned,
        // ★ 2026-10-27（统一行高）：尾部那几行现在**各自有槽、各自画光标**（`tailline@k`），
        //   这个槽只负责"剩下的那片白"（点击 + 没有尾部行时的兜底光标），所以 dy 用旧的兜底值。
        caretDy:
            after >= 0 ? tailK * _blankLineHeight + _caretInset : null,
        caretHeight: textCaretHeight(_s.bodyFontSize),
        caretWidth: 1.5,
        caretColor: const Color(kCaretColorValue),
        topAligned: true,
        // ★ 批 43：点它落在**第一个真实可落位置**（空行首 / 分页符行首）；
        //   只有"文末还没有那一行空行"时才走"补一行"的老行为。
        onTap: (int at, Offset global) => _onTailBlankTap(
            (after >= 0 && after < widget.buffer.buf.length)
                ? after
                : (seamTap > tailPrev.acceptTo &&
                        seamTap < widget.buffer.buf.length
                    ? seamTap
                    : null)),
        onBox: (String id, RenderBox box) => _blankBoxes[id] = box,
      ));
    } else if (isLastPage && _units.isEmpty) {
      // ★★ 2026-10-18 晚（用户报「**新建文档点不出光标**」）·
      //   根因不是光标没画，而是**整页一个可点单元都没有**：
      //   `BlockIndex.parse('')` 里空行全被 R1 跳过 ⇒ `blocks = []` ⇒ `flowUnits = []`
      //   ⇒ 上面的分支要求 `prevUnit != null`（不成立）⇒ 页面里连一个命中盒都不存在
      //   ⇒ 点哪儿都落不了光标（打字也就无从插入）。
      //   修法（**最小、不动分页、不动块模型**）：整页铺一个空行槽 ——
      //   落点 0、高度 = 正文高（与"文末那片空白"同一套件），点哪儿都落到 0。
      //   ★ 这是 §11.46（"空块不产出单元"）的**最小补丁**；真正的模型级修法
      //     （真空段落占一行高）留给结构层那一批，两者不冲突：这里只补"零单元"这一种。
      children.add(_BlankSlot(
        id: 'blank@empty',
        height: _m.bodyHeight,
        offset: 0,
        caretHere: !widget.hideCaretAndSelection &&
            widget.caretVisible &&
            (_caret ?? 0) == 0,
        caretHeight: textCaretHeight(_s.bodyFontSize),
        caretWidth: 1.5,
        caretColor: const Color(kCaretColorValue),
        topAligned: true,
        onTap: (int at, Offset global) => widget.onTapOffset?.call(at, global, TapSource.text),
        onBox: (String id, RenderBox box) => _blankBoxes[id] = box,
      ));
    } else if (!isLastPage && prevUnit != null && _pageHasUnit(layout, p + 1)) {
      // ★★ 批 38 新增：**接缝带**（非末页的剩余白）。
      //
      // 为什么"下一页有单元"才建：末页**没有单元**时，那段接缝归末页的文末槽认领
      // （否则两页各画一根竖条 —— 同一格像素两个主人，平权/一像素一语义都不允许）。
      final int tapAt = _seamTapTarget(prevUnit);
      final int end = _seamEnd(layout, p);
      // ★★ 2026-10-26 用户手测追加（批 38 回归 + 批 39）：**认领起点 = 上一单元之后那一格**。
      //   · 不许从 `tapAt` 起算：自然分页时 `tapAt == prevUnit.acceptTo`，那格是**单元自己**的
      //     （旁边还有空行槽/块边界条）⇒ 直接叠成 3 根（用户看到"文末和下面空行各一个光标"）；
      //   · 也不许"只在越过 acceptTo 时才画"（上一版）：那样**页尾那几行真空行没人管** ——
      //     用户在页尾空行上按 Enter，光标就看不见了（他的原话："光标会消失，实际到空行了但不显示"）。
      //   ⇒ 起算点是 acceptTo + 1，右端是下一页第一个单元的左边界。
      final int ownedFrom =
          (prevUnit.acceptTo + 1).clamp(0, widget.buffer.buf.length);
      // ★★★ 2026-10-27（用户实测：「分页原页的文末下一个空行，继续按 Enter，光标位置看上去不变，
      //   但退格次数会增加」）：接缝槽原来**没有 `caretDy` / `lineOffsets`** ⇒ 光标恒画在槽顶，
      //   缓冲区在长（Enter 生效、退格变多）而屏幕上看不出光标在动。
      //   ⇒ 与末页槽同一条：`dy = 段距 + k × 行高`（k = 光标在这串空行里的第几个）。
      // ★★★ 2026-10-27（只读基准 4「末页 / 分页原页一致」）：
      //   **这一页底部那些"行"用同一条规则算出来**（见 `_rowsAfter`）：已有空行 + 一个待写行。
      //   分页符块零像素、不产单元 ⇒ 它那一行没人画，必须由接缝槽补上；
      //   补上之后，"分页原页底部那片空白"就和"文末那片空白"是同一个东西了。
      final List<int> seamSlots = _rowSlotsAfter(prevUnit);
      // 空行串非空 ⇒ 第 0 个只是段距那一截；为空 ⇒ 第 0 个就是待写行本身。
      final int seamFirstRow = _blankRunAfter(prevUnit).isEmpty ? 0 : 1;
      final int seamK = _caretRowIndexIn(seamSlots);
      children.add(_BlankSlot(
        id: 'seam@p$p',
        height: free,
        offset: tapAt,
        lineOffsets: seamSlots,
        lineDys: _blankDys(seamSlots.length, firstRow: seamFirstRow),
        gapBefore: _paraGap,
        lineHeight: _blankLineHeight,
        caretHere: breakRowsOnPage == 0 &&
            !widget.hideCaretAndSelection &&
            widget.caretVisible &&
            (_caret ?? -1) >= ownedFrom &&
            (_caret ?? -1) < end,
        // ★ 同一把尺子：`槽顶 + 段间距 + k × 一行 + 行内内缩`
        caretDy: _blankDy(seamK, firstRow: seamFirstRow),
        caretHeight: textCaretHeight(_s.bodyFontSize),
        caretWidth: 1.5,
        caretColor: const Color(kCaretColorValue),
        topAligned: true,
        // ★ 只落光标：**不改文档**（改了会重排/翻页，而"点页面白"不该有这种后果）
        onTap: (int at, Offset global) =>
            widget.onTapOffset?.call(at, global, TapSource.text),
        onBox: (String id, RenderBox box) => _blankBoxes[id] = box,
      ));
    }

    return Listener(
      // ★★ 2026-10-19（L18）：页边距那一片（含"行首公式左边 4 px"）原来**没人接指针**
      //   ⇒ 点它什么都不发生。`opaque` 让这一页**整片**都进命中路径（页边距也算），
      //   具体判断在 `_onPagePointerDown` 里（只在左缘带内才动手，其余一律让开）。
      //   ★ `Listener` 只"听"指针、不参加手势竞技场 ⇒ 不影响滚动、不影响单元自己的点击。
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPagePointerDown,
      child: PageSheet(
        settings: _s,
        metrics: _m,
        pageNumber: p + 1,
        pageCount: layout.pageCount,
        warnings: warnings,
        // ★ S4-d③：图片集 / 图片式 PDF 的抓取点（同一棵子树 = 同一张图）
        sheetKey: _sheetKeyOf(p),
        children: children,
      ),
    );
  }

  /// 第 [p] 页有没有**内容**（单元或"尾部空行占位项"）。
  ///
  /// ★ 2026-10-27（用户实测：自动分页之后，原页下部空白点不动）：
  ///   原来的判据只看**单元**，而自动分页把尾部空行推到新页时，那一页**只有占位项、没有单元**
  ///   ⇒ 判成"空页" ⇒ 上一页不建接缝槽 ⇒ 原页底部那片白没有点击判定。
  bool _pageHasUnit(PageLayout layout, int p) {
    if (p < 0 || p >= layout.pages.length) return false;
    return layout.pages[p].isNotEmpty;
  }

  /// 接缝带的**右端（不含）**：下一页第一个单元的左边界（没有下一页 ⇒ 文末）。
  int _seamEnd(PageLayout layout, int p) {
    final int len = widget.buffer.buf.length;
    if (p + 1 >= layout.pages.length) return len;
    for (final PageSlot s in layout.pages[p + 1]) {
      final _Unit? u = _unitById[s.item.id];
      if (u == null) continue;
      return u.acceptFrom.clamp(0, len);
    }
    return len;
  }

  /// 接缝带的**落点**：上一页最后一行之后那一格。
  ///
  /// · 下一行是**分页符** ⇒ 落在分页符行首（那 19 格在批 38 之前**没有任何主人** ——
  ///   分页符块不产单元、也不认领源码，实测整行是光标死区）；
  /// · 否则 ⇒ 落在"这一页最后一格"（`acceptTo`，最后一行的行尾），点了就停在页尾。
  int _seamTapTarget(_Unit prev) {
    final String buf = widget.buffer.buf;
    final int at = prev.acceptTo.clamp(0, buf.length);
    if (at >= buf.length || buf[at] != '\n') return at;
    final int next = at + 1;
    if (next >= buf.length) return at;
    final int nl = buf.indexOf('\n', next);
    final String line = buf.substring(next, nl < 0 ? buf.length : nl);
    // ★★★ 批 47（2026-10-26，用户纠正）：落点**就是分页符行首** —— 那片空白对应的真实位置。
    //   批 46 曾把这里改成"最后一行行尾"，等于把 批 43 的目标（点空白落空白）改回去了，
    //   用户当场指出。真正该修的是**插入侧**：`insert_guard` 规则⑥ 原来把"行首插入"
    //   也挪到标记之后 ⇒ 字跑到下一页。现在规则⑥ 对行首不再挪位 ⇒ 落在这一格打字，
    //   内容补后缀换行后落在**标记之前**（本页）。
    if (BlockMarkers.isPageBreak(line)) return next;
    if (line.trim().isEmpty) return next;            // ★ 批 43：空行首（用户要的落点）
    return at;
  }

  /// 点"文末那片空白" ⇒ **把光标放到最后一行下面那一行**（**不改文档**）。
  ///
  /// ★★★ 2026-10-27（撤批 43 的"点击补一行"；用户："点击下部空白让光标落到文末下一个空行，
  ///   这符合直觉和操作习惯 —— 但没必要和改文档冲突"）：
  ///   "文末下一个空行"**不需要造出来** —— 它就是这个位置：最后一行之后那一格
  ///   （= `buf.length`，也就是再按一次 Enter 会落脚的那一行）。
  ///   ⇒ 点击只移光标；要真的多一行按 Enter（现在一次 Enter 正好一行）。
  ///   两种口径在**看不见一个字符**上是等价的，区别只在"点一下会不会把文档改脏"。
  void _onTailBlankTap([int? at]) {
    final DocBuffer b = widget.buffer;
    final String s = b.buf;
    if (s.isEmpty) {
      b.setCaret(0);
      return;
    }
    // 槽给出了"第一个真实可落位置"（空行行首 / 分页符行首）⇒ 落到那儿，同样不改文档。
    if (at != null && at >= 0 && at < s.length) {
      b.setCaret(at);
      return;
    }
    b.setCaret(s.length);
  }

  /// 上一个单元之后如果跟着**空行**，返回那个空行的起点；否则 -1。
  ///
  /// 判据：上一个单元的最后一行之后是 `\n`，而**下一行是空的**（或以文末结束）。
  int _blankOffsetAfter(_Unit prev) {
    final String buf = widget.buffer.buf;
    var o = prev.acceptTo.clamp(0, buf.length);
    if (o >= buf.length || buf[o] != '\n') return -1;
    o++; // 跳过上一行的换行 ⇒ 空行的行首
    if (o > buf.length) return -1;
    final bool blank = o >= buf.length || buf[o] == '\n';
    return blank ? o : -1;
  }

  @override
  Widget build(BuildContext context) {
    _measurePool.beginFrame();
    _renderPool.beginFrame();

    final BlockIndex idx = BlockIndex.parse(widget.buffer.buf);
    _units = _buildUnits(idx);
    _blockCount = idx.blocks.length;
    _unitById = <String, _Unit>{for (final _Unit u in _units) u.id: u};
    _caret = widget.buffer.caret;
    // ★★ ⑤ 选区（绝对偏移）—— 高亮**纯绘制**，不影响测量与分页
    _selStart = widget.buffer.selectionStart;
    _selEnd = widget.buffer.selectionEnd;

    // ① 离屏测量树：与真实渲染**同样的宽度、同样的 widget**，所以高度完全一致。
    //    ★ 光标也要一起传 —— 否则两棵树对同一个单元建出的 widget 不同，"渲染即测量"就不成立了。
    final Widget measureTree = Offstage(
      offstage: true,
      child: SizedBox(
        width: _m.contentWidth,
        child: Column(
          key: _measureRootKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final _Unit u in _units)
              _measurePool.widgetFor(
                _poolKeyFor(u),
                () => _buildUnitWidget(u, u.relFor(_caret)),
              ),
          ],
        ),
      ),
    );

    // ② 渲染树：用上一次的分页结果
    final PageLayout? layout = _layout;
    final Widget pages = layout == null
        ? Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '正在分页…（${_units.length} 个流单元）',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (var p = 0; p < layout.pageCount; p++) _pageWidget(layout, p),
            ],
          );

    _scheduleMeasure();
    _scheduleCaretRect();
    // 渲染池的大小要等这一帧把页面建出来才知道 → 帧末再报一次统计
    if (_layout != null) _scheduleStatsOnce();

    _measurePool.endFrame();
    _renderPool.endFrame();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[measureTree, pages],
    );
  }
}
