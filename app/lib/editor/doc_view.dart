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
  final void Function(int at) onTap;
  final void Function(String id, RenderBox box) onBox;

  /// 竖条是否**贴顶**（末尾槽占整片剩余空白时，光标要紧贴最后一行下面，不浮在中间）
  final bool topAligned;

  /// ★★ 2026-10-18 晚（§11.46 真修）：这个槽代表的**真空段落里有哪几行**（每行行首偏移）。
  ///
  /// 一个槽可能覆盖 **n 个空行**（用户连按 Enter 出来的）。有了这张表：
  ///   · 点槽里第 k 行 ⇒ 光标落到第 k 行（而不是永远落第一行）；
  ///   · 光标在第 k 行 ⇒ 竖条画在那个行高上（`caretDy`）。
  final List<int> lineOffsets;

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
      onTapDown: widget.lineOffsets.isEmpty
          ? null
          : (TapDownDetails d) {
              final RenderBox? box = context.findRenderObject() as RenderBox?;
              if (box == null || !box.hasSize) {
                widget.onTap(widget.offset);
                return;
              }
              final double dy = box.globalToLocal(d.globalPosition).dy;
              // ★ 空行的行盒从 `gapBefore` 起算（上面那截是段距，不算"某一行"）
              final double rel = dy - widget.gapBefore;
              final int k = rel <= 0
                  ? 0
                  : (rel / widget.lineHeight).floor();
              final int i = k.clamp(0, widget.lineOffsets.length - 1);
              widget.onTap(widget.lineOffsets[i]);
            },
      onTap: widget.lineOffsets.isEmpty ? () => widget.onTap(widget.offset) : null,
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
  final void Function(int offset)? onTapOffset;

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
    final List<Uint8List> out = <Uint8List>[];
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
    return out;
  }

  /// 本帧的光标（绝对偏移）—— S3-2
  int? _caret;

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
    final void Function(int)? cb = widget.onTapOffset;
    if (cb == null) return;
    final int? off = _offsetAt(u, ctx.findRenderObject(), global);
    if (off != null) cb(off);
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
      final int? texRel = _mathTapTexOffset(
        tex: rawTex,
        renderTex: _renderTexFor(rawTex, caretRel),
        root: mr,
        global: global,
        displayStyle: true,
      );
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
    final SlotMarkResult m = injectSlotMarks(tex, caretRel: caretRel ?? -1);
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
  }) {
    final Offset localPos = (root as RenderBox).globalToLocal(global);

    // ★★ P2-D（2026-10-18）：多行环境**按格子**判落点。
    //   原因：`aligned` / `cases` 的一行里只有 `=` 之类有墨迹，其它位置是空白；
    //   旧的"最近字形"会把远处点击吸到别处（用户实测：点第一行左侧空白，
    //   光标落到**第二个等号**旁边）。格子有行/列的矩形可算 ⇒ 先按格子定，再退回旧判据。
    if (hasEnv(tex)) {
      final EnvCellHit? cell = envCellHitAt(
        root: root,
        localPos: localPos,
        tex: renderTex,
        displayStyle: displayStyle,
      );
      if (cell != null) {
        final int? cellOffset = envCellOffset(tex, cell);
        if (cellOffset != null) return cellOffset;
      }
    }
    final MathHit hit = hitTestMathTex(
      root: root,
      localPos: localPos,
      tex: renderTex, // ★ 必须用渲染时的 tex（见 injection_map.dart）
      // ★ 原子表必须是**渲染顺序**（尾垫/占位垫由词法自己在走查顺序里认出）
      atoms: renderOrderAtoms(renderTex, displayStyle: displayStyle),
      displayStyle: displayStyle,
    );
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
    final void Function(int)? cb = widget.onTapOffset;
    if (cb == null) return;
    // ★★ §6.1.1（2026-10-18）：**空公式没有字形盒** ⇒ 走不了命中表。
    //   但它是**看得见的对象**（`EmptyMathMark` 那个虚线小框），点它必须"落进公式里"
    //   —— 空公式唯一的内容位点就是它的 contentStart。
    if (seg.tex.trim().isEmpty) {
      cb(u.renderBase + seg.start);
      return;
    }
    final RenderObject? ro = key.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return;
    final int? texRel = _mathTapTexOffset(
      tex: seg.tex,
      renderTex: renderTex,
      root: ro,
      global: global,
      displayStyle: false, // ★ 行内 = text 样式（`\sum` 的上下限退回脚本位）
    );
    if (texRel == null) return;
    // ★ 位点吸附：落点必须是合法位点（设计稿 §2.4 的 P3）
    final int rel = buildCaretSites(seg.tex).snap(texRel).offset;
    cb(u.renderBase + seg.start + rel);
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
    if (widget.hideCaretAndSelection) return null; // 失焦
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
    if (widget.hideCaretAndSelection) return null;
    return u.renderBase + rel;
  }
  ({int from, int to})? _localSelFor(_Unit u) {
    if (widget.hideCaretAndSelection || _selEnd <= _selStart) return null;
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
    if (rel == null) return '${u.contentKey}$selKey$caretKey';
    // ★ 组合态也要进键：拼音变化会改变"含光标那个单元"的 widget 内容，
    //   不进键就会从池里拿回上一帧的旧拼音（叠字/不刷新）。
    final String comp = _composingFor(u, rel).isEmpty
        ? ''
        : '#k${_composingFor(u, rel).hashCode}';
    return '${u.contentKey}#c$rel$comp$selKey$caretKey';
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
            // ★ 与行内公式的「两端各多认领一格」对称：**块前那一格**也算（否则光标从上面
            //   往下走进块时，最后一格没人管 ⇒ 又是"光标消失"）
            BlockType.math => sliceStart > 0 ? sliceStart - 1 : 0,
            _ => null,
          },
          acceptTo: b.type == BlockType.math ? sliceStart + src.length : null,
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
          onMathTap: onMathTap,
          textStyle: TextStyle(
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
        final bool beforeBlock = rawCaret != null && rawCaret < u.renderBase;
        final bool afterBlock =
            rawCaret != null && rawCaret > u.renderBase + u.renderLength;
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
              showCaret: caretAbs != null,
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
            child: MathWithCaret(
              tex: tex,
            // ★ ⑤ 选区：行间公式整块是一个对象（用户拍板）—— 被选中就铺整块
            selFrom: selFrom,
            selTo: selTo,
            // 块前那一格（`renderBase - 1`）也要画 —— 它已被本单元认领（acceptFrom）
            showCaret: caretAbs != null,
            caretEdge: beforeBlock
                ? CaretEdge.before
                : (afterBlock ? CaretEdge.after : CaretEdge.none),
            textFontSize: body,
            mathKey: mathKey,
            fontSize: display,
            mathStyle: MathStyle.display,
            onErrorFallback: (e) => Tooltip(
              message: e.messageWithType,
              child: const Text(
                '［公式不完整］',
                style: TextStyle(color: Color(0xFFB08968), fontSize: 13),
              ),
            ),
            ),
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
        return const Divider(height: 12, thickness: 1);

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

  List<FlowItem> _itemsFrom(List<double> hs) => <FlowItem>[
        for (var i = 0; i < _units.length; i++)
          FlowItem(
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
            label: _units[i].label,
          ),
      ];

  /// 一行空行的**高度**（用正文字号算，与文本行盒同一把尺子）
  double get _blankLineHeight => textCaretHeight(_s.bodyFontSize);

  /// 从 [from]（**必须是行首**）起的连续**空行**，返回每个空行的行首偏移。
  ///
  /// ★ 判据本体在 `blank_runs.dart`（纯函数，可单测 —— 它决定"要不要占一整行高"）。
  List<int> _blankRunFrom(int from) => blankRunFrom(widget.buffer.buf, from);

  /// 上一个单元之后那串空行的**行首偏移**（没有 ⇒ 空表）
  List<int> _blankRunAfter(_Unit prev) =>
      blankRunAfter(widget.buffer.buf, prev.acceptTo);

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
        if (run.isNotEmpty) {
          final int? idx = _caretLineIndexInRun(run);
          // ★ 段距那一截：空隙里除了"真空段落的行"之外，前面还有一段**段距**
          final double gapBefore =
              (prevUnit == null || u == null) ? 0.0 : _gapBefore(u.type);
          children.add(_BlankSlot(
            id: 'blank@${run.first}',
            height: gap,
            offset: run.first,
            lineOffsets: run,
            gapBefore: gapBefore,
            lineHeight: _blankLineHeight,
            caretHere: !widget.hideCaretAndSelection &&
                widget.caretVisible &&
                idx != null,
            // 空行的行盒从 gapBefore 起算 ⇒ 光标落在"它真正会落脚"的那一行上
            caretDy: idx == null ? null : gapBefore + idx * _blankLineHeight,
            caretHeight: textCaretHeight(_s.bodyFontSize),
            caretWidth: 1.5,
            caretColor: const Color(kCaretColorValue),
            onTap: (int at) => widget.onTapOffset?.call(at),
            onBox: (String id, RenderBox box) => _blankBoxes[id] = box,
          ));
        } else {
          children.add(SizedBox(height: gap));
        }
      }
      if (u == null) continue;
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

    // ★★ ⑥ 丙 · **文末那片空白 = 一行空行**（2026-10-17 用户拍板 **甲**）：
    //   「添加空行有两条途径：Enter、点下方空白」—— 两条**都会改文档**（和 Enter 一样）：
    //   点一下就在文末起一行空行、光标落在那儿；已经有一行就不再加（**幂等**）。
    //   槽的高度取**这一页剩下的正文高度** ⇒ 那片空白**整片**都能点；
    //   竖条**贴顶**画在最后一行下面。
    //   ★ 只有**文末真的有那一行空行**时才画竖条（否则会和最后一行字尾的光标叠成两根）。
    if (p == layout.pageCount - 1 && prevUnit != null) {
      final int after = _blankOffsetAfter(prevUnit);
      final int tail = after >= 0 ? after : widget.buffer.buf.length;
      final double free = (_m.bodyHeight - bottom)
          .clamp(textCaretHeight(_s.bodyFontSize), _m.bodyHeight);
      children.add(_BlankSlot(
        id: 'blank@$tail',
        height: free,
        offset: tail,
        // ★★ 2026-10-17 用户实测："enter 和点空白都能到空行了，但光标显示不出来"：
        //   插入 `\n\n` 之后缓冲区是 `…\n\n`，**光标落在 after + 1**（末尾那行空行的行首），
        //   而空行的**起点**是 `after` ⇒ 原来 `_caret == after` 永远不成立 ⇒ 一根竖条都不画。
        //   ⇒ 文末槽只要是"光标停在末尾那片空白里"就画。
        // ★★ 2026-10-18 晚：**竖条要画在"新段落真正会落脚"的位置**。
        //   用户实测：「enter 之后光标在这儿，但打出来的字符比它低一截」——
        //   差的就是这一截**段距**（新段落在上一段底下再让开 `gapBefore`）。
        caretHere: !widget.hideCaretAndSelection &&
            widget.caretVisible &&
            after >= 0 &&
            (_caret ?? -1) >= after,
        // 文末的空行 = 下一个段落的行首 ⇒ 从段距处起画
        caretDy: after >= 0 ? _gapBefore(BlockType.paragraph) : null,
        caretHeight: textCaretHeight(_s.bodyFontSize),
        caretWidth: 1.5,
        caretColor: const Color(kCaretColorValue),
        topAligned: true,
        onTap: (int at) => _onTailBlankTap(),
        onBox: (String id, RenderBox box) => _blankBoxes[id] = box,
      ));
    } else if (p == layout.pageCount - 1 && _units.isEmpty) {
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
        onTap: (int at) => widget.onTapOffset?.call(at),
        onBox: (String id, RenderBox box) => _blankBoxes[id] = box,
      ));
    }

    return PageSheet(
      settings: _s,
      metrics: _m,
      pageNumber: p + 1,
      pageCount: layout.pageCount,
      warnings: warnings,
      // ★ S4-d③：图片集 / 图片式 PDF 的抓取点（同一棵子树 = 同一张图）
      sheetKey: _sheetKeyOf(p),
      children: children,
    );
  }

  /// ★★ 点"文末那片空白" = **在文末起一行空行**（⑥ 甲；与 `Enter` 同一条路、同样会改文档）。
  ///
  /// 幂等：文末已经是一行空行（`…\n\n`）就只把光标放上去；末尾只有一个换行 ⇒ 补一个；
  /// 没有换行 ⇒ 补两个。一次插入 = 一步编辑（`Ctrl+Z` 可一步回退）。
  void _onTailBlankTap() {
    final DocBuffer b = widget.buffer;
    final String s = b.buf;
    if (s.isEmpty) {
      b.setCaret(0);
      return;
    }
    final String add =
        s.endsWith('\n\n') ? '' : (s.endsWith('\n') ? '\n' : '\n\n');
    if (add.isEmpty) {
      b.setCaret(s.length); // 已经有一行空行 ⇒ 只移光标（落点自动在那一行行首）
    } else {
      b.replace(s.length, s.length, add); // 落点自动到插入之后 = 新行行首
    }
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
