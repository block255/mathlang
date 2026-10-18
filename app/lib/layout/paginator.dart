// 数语引擎 · 分页器（纯算法，可单测）
//
// 输入：一串 `FlowItem`（每个 = 一个**分页原子** + 它测量出来的高度）
// 输出：每页放哪些 item、页内 y 偏移，以及"高于一页"的告警清单
//
// 规则（《块模型与md往返.md》§五，2026-10-14 定稿）：
//   · 按顺序累加高度，超过页正文高 → 开新页
//   · **分页符** = 强制换页，自身不占高度（构建 item 时把它变成下一个 item 的 breakBefore）
//   · item 自身**高于一页** → **不切断**，记入溢出告警（原则 5：静默失败必须可见）
//   · `leadingGap`（块间距）在**页首丢弃**（与 Word 一致：页首不留段前距）
//
// 纯 Dart，不依赖 Flutter。

/// 一个分页原子：FlowUnit 的高度 + 它的块间距 / 是否强制换页。
class FlowItem {
  const FlowItem({
    required this.id,
    required this.height,
    this.leadingGap = 0,
    this.breakBefore = false,
    this.label,
  });

  /// 稳定标识（回到 FlowUnit 用），例如 `blk3/u1`
  final String id;

  /// 测量出来的高度（不含 [leadingGap]）
  final double height;

  /// 与上一个 item 之间的间距（块与块之间才有；同块内相邻 flow unit 为 0）
  final double leadingGap;

  /// 该 item **之前**强制换页
  final bool breakBefore;

  /// 告警时显示的名字（如 `公式块 $$\int...$$`）
  final String? label;

  @override
  String toString() =>
      'FlowItem($id, h=${height.toStringAsFixed(1)}, gap=$leadingGap'
      '${breakBefore ? ", break" : ""})';
}

/// 一个 item 在它那一页里的落位。
class PageSlot {
  const PageSlot(this.item, this.y);
  final FlowItem item;
  final double y;
}

/// 分页结果。
class PageLayout {
  const PageLayout({required this.pages, required this.overflow});

  /// 每页的落位（`pages[0]` = 第 1 页）
  final List<List<PageSlot>> pages;

  /// 高于一页、被迫单独占页的 item（**告警清单**）
  final List<FlowItem> overflow;

  int get pageCount => pages.length;

  @override
  String toString() => 'PageLayout($pageCount 页, 溢出 ${overflow.length} 个)';
}

/// 把 item 序列贪心装箱成页。
///
/// [bodyHeight] 来自 `PageMetrics.bodyHeight`。
/// [topInset] = **第一页顶部**预留的高度（2026-10-18 晚新增：文档以空行开头时，
///   那几行空行是"真空段落"，必须占位；它不能挂在 item 的 `leadingGap` 上 ——
///   `paginate` 对页首本来就不留段前距）。
PageLayout paginate({
  required List<FlowItem> items,
  required double bodyHeight,
  double topInset = 0,
}) {
  if (bodyHeight <= 0) {
    throw ArgumentError.value(bodyHeight, 'bodyHeight', '页正文高必须为正');
  }
  final pages = <List<PageSlot>>[];
  final overflow = <FlowItem>[];

  var cur = <PageSlot>[];
  var y = topInset; // ★ 只有第一页从 topInset 起步（flush 会把它复位成 0）

  void flush() {
    if (cur.isEmpty) return;
    pages.add(cur);
    cur = <PageSlot>[];
    y = 0;
  }

  for (final FlowItem it in items) {
    if (it.breakBefore) flush();
    // 页首不留段前距
    final double gap = cur.isEmpty ? 0.0 : it.leadingGap;
    if (cur.isNotEmpty && y + gap + it.height > bodyHeight) {
      flush();
    }
    final double g = cur.isEmpty ? 0.0 : it.leadingGap;
    if (it.height > bodyHeight) overflow.add(it);
    cur.add(PageSlot(it, y + g));
    y += g + it.height;
  }
  flush();

  // 空文档也要有一页（编辑器里总得有个能写字的地方）
  if (pages.isEmpty) pages.add(<PageSlot>[]);

  return PageLayout(pages: pages, overflow: overflow);
}
