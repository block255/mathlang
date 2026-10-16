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

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../core/block.dart';
import '../core/doc_buffer.dart';
import '../core/doc_settings.dart';
import '../layout/page_metrics.dart';
import '../layout/paginator.dart';
import '../render/caret_ownership.dart';
import '../render/caret_sites.dart';
import '../render/hit_map.dart';
import '../render/inline_math_text.dart';
import '../render/injection_map.dart';
import '../render/leaf_boxes.dart';
import '../render/math_caret.dart';
import '../render/projection.dart';
import '../render/slot_marks.dart';
import '../render/structure_geometry.dart';
import 'page_sheet.dart';
import 'unit_pool.dart';

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
    this.onCaretRect,
    this.composingText = '',
  });

  final DocBuffer buffer;
  final DocSettings settings;

  /// 每次分页结果变化时回调（给状态栏用）
  final void Function(DocViewStats stats)? onStats;

  /// ★ S3-2：点屏幕 → **L0 里的绝对偏移**（调用方负责落光标）。
  /// 文字走 `RenderParagraph.getPositionForOffset` + 段落↔源坐标换算；
  /// 行内公式与行间公式走 S1 验证过的 `hitTestMathTex`（叶盒 ↔ 可见原子）再做位点吸附。
  final void Function(int offset)? onTapOffset;

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

  @override
  State<DocView> createState() => _DocViewState();
}

class _DocViewState extends State<DocView> {
  late DocSettings _s = widget.settings;
  late PageGeometry _m = PageGeometry.from(_s);

  List<_Unit> _units = <_Unit>[];
  Map<String, _Unit> _unitById = <String, _Unit>{};

  final GlobalKey _measureRootKey = GlobalKey();
  final UnitPool _measurePool = UnitPool();
  final UnitPool _renderPool = UnitPool();

  List<double> _heights = <double>[];
  PageLayout? _layout;
  bool _measureScheduled = false;
  int _blockCount = 0;
  DocViewStats? _lastStats;

  int get measurePoolSize => _measurePool.size;
  int get renderPoolSize => _renderPool.size;
  int get pageCount => _layout?.pageCount ?? 0;

  /// 本帧的光标（绝对偏移）—— S3-2
  int? _caret;

  /// 行间公式块的 Math 渲染盒（仅渲染树用；键按**单元 id** 稳定，不会跨位置迁移）
  final Map<String, GlobalKey> _mathBlockKeys = <String, GlobalKey>{};

  /// 渲染树里每个单元的渲染盒（由 `_UnitHitBox` 帧末上报）—— 光标定位要用
  final Map<String, RenderBox> _unitBoxes = <String, RenderBox>{};

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
    final RenderObject? root = context.findRenderObject();
    final int? caret = _caret;
    if (root is! RenderBox || caret == null) return null;

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

    // ① 行间公式块：整块就是一个数学段
    if (u.type == BlockType.math) {
      _onMathBlockTap(u, global, _renderParts(u.type, u.source).text);
      return;
    }

    // ② 文字（段落 / 标题 / 引用 / 列表项）：交给段落排版器
    final RenderObject? ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return;
    final String text = _renderParts(u.type, u.source).text;
    final int? rel = u.relFor(_caret);
    final List<int> map = paragraphIndexMap(
      text,
      // ★ 光标在本段文字里时，段落会多一个"光标条"码元 → 映射表必须算上它，
      //   否则点击映射整体偏 1（用户实测的"点哪儿都没规律"）
      caretInText: _caretInTextSegment(text, rel),
    );
    final RenderParagraph? para = _contentParagraph(ro, _plainTextOf(text));
    if (para == null) return;
    final TextPosition tp =
        para.getPositionForOffset(para.globalToLocal(global));
    final int p = tp.offset.clamp(0, map.length - 1);
    cb(u.renderBase + map[p]);
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
  /// ★ 顺带收益：叶盒 ↔ 原子配对失败（`\sin` 一族的多字母算子名）时不再"点了没反应"，
  ///   而是落到**结构层**（结构之前 / 之后）—— 精确落点仍要等那条配对缺陷修好。
  int? _mathTapTexOffset({
    required String tex,
    required String renderTex,
    required RenderObject root,
    required Offset global,
  }) {
    final Offset localPos = (root as RenderBox).globalToLocal(global);
    final MathHit hit = hitTestMathTex(
      root: root,
      localPos: localPos,
      tex: renderTex, // ★ 必须用渲染时的 tex（见 injection_map.dart）
      atoms: atomsForHitTest(renderTex), // ★ 且原子表要补上尾垫的合成原子
    );
    if (hit.onGlyph && hit.offset != null) {
      return renderToSourceOffset(renderTex, hit.offset!);
    }

    final StructureGeometry g =
        buildStructureGeometry(tex: tex, renderTex: renderTex, mathRoot: root);
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
  void _onMathBlockTap(_Unit u, Offset global, String rawTex) {
    final void Function(int)? cb = widget.onTapOffset;
    if (cb == null) return;
    final RenderObject? ro = _mathBlockKeys[u.id]?.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return;
    final int? caretRel = _caret == null ? null : u.relFor(_caret);
    final String renderTex = _renderTexFor(rawTex, caretRel);
    final int? texRel = _mathTapTexOffset(
      tex: rawTex,
      renderTex: renderTex,
      root: ro,
      global: global,
    );
    if (texRel == null) return;
    cb(u.renderBase + buildCaretSites(rawTex).snap(texRel).offset);
  }

  /// 行内公式被点中（`InlineMathText.onMathTap` 给的是**段内相对**的 tex、
  /// **渲染用的 tex**、以及渲染盒 key）
  void _onMathTap(_Unit u, ProjectionSegment seg, String renderTex, Offset global,
      GlobalKey key) {
    final void Function(int)? cb = widget.onTapOffset;
    if (cb == null) return;
    final RenderObject? ro = key.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return;
    final int? texRel = _mathTapTexOffset(
      tex: seg.tex,
      renderTex: renderTex,
      root: ro,
      global: global,
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
  String _poolKeyFor(_Unit u) {
    final int? rel = u.relFor(_caret);
    if (rel == null) return u.contentKey;
    // ★ 组合态也要进键：拼音变化会改变"含光标那个单元"的 widget 内容，
    //   不进键就会从池里拿回上一帧的旧拼音（叠字/不刷新）。
    final String comp = _composingFor(u, rel).isEmpty
        ? ''
        : '#k${_composingFor(u, rel).hashCode}';
    return '${u.contentKey}#c$rel$comp';
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
  void didUpdateWidget(DocView old) {
    super.didUpdateWidget(old);
    if (old.buffer != widget.buffer) {
      old.buffer.removeListener(_onBufferChanged);
      widget.buffer.addListener(_onBufferChanged);
    }
    if (old.settings != widget.settings) {
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
    // 光标在本单元内时换算成**绝对偏移**（InlineMathText 用的是绝对偏移）
    final int? caretAbs = caretRel == null ? null : u.renderBase + caretRel;
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
          caretRel: caretAbs == null ? -1 : caretAbs - u.renderBase,
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
        return Center(
          child: MathWithCaret(
            tex: tex,
            // 块前那一格（`renderBase - 1`）也要画 —— 它已被本单元认领（acceptFrom）
            showCaret: caretAbs != null,
            caretEdge: beforeBlock
                ? CaretEdge.before
                : (afterBlock ? CaretEdge.after : CaretEdge.none),
            textFontSize: body,
            mathKey: mathKey,
            fontSize: display,
            mathStyle: MathStyle.display,
            onErrorFallback: (e) => Text(
              '❌ ${e.messageWithType}',
              style: const TextStyle(color: Colors.red, fontSize: 13),
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
      if (!changed) return;

      setState(() {
        _heights = hs;
        _layout = paginate(items: _itemsFrom(hs), bodyHeight: _m.bodyHeight);
      });
      _emitStats();
    });
  }

  List<FlowItem> _itemsFrom(List<double> hs) => <FlowItem>[
        for (var i = 0; i < _units.length; i++)
          FlowItem(
            id: _units[i].id,
            height: hs[i],
            leadingGap:
                _units[i].isFirstInBlock && i > 0 ? _gapBefore(_units[i].type) : 0,
            breakBefore: _units[i].breakBefore,
            label: _units[i].label,
          ),
      ];

  // ---------------- 渲染 ----------------

  Widget _pageWidget(PageLayout layout, int p) {
    final slots = layout.pages[p];
    final children = <Widget>[];
    final warnings = <String>[];
    var bottom = 0.0;

    for (final PageSlot s in slots) {
      final double gap = s.y - bottom;
      if (gap > 0.5) children.add(SizedBox(height: gap));
      final _Unit? u = _unitById[s.item.id];
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
      bottom = s.y + s.item.height;
      if (s.item.height > _m.bodyHeight) {
        warnings.add('${s.item.label ?? u.type.name} 高于一页'
            '（${s.item.height.toStringAsFixed(0)} px > '
            '${_m.bodyHeight.toStringAsFixed(0)} px），已强制放在一页内、未切断');
      }
    }

    return PageSheet(
      settings: _s,
      metrics: _m,
      pageNumber: p + 1,
      pageCount: layout.pageCount,
      warnings: warnings,
      children: children,
    );
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
