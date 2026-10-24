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
import 'tex_fixups.dart';
import 'visible_atoms.dart';

/// **给命中测试用的原子表**：渲染 tex 的可见原子，**按渲染顺序**（= 叶盒顺序）。
///
/// ★ 2026-10-17 起它就是 `lexVisibleAtoms(renderTex)` —— 两类注入物
///   （空槽宽度垫 `kSlotPadFiller` · 结构尾垫 `kStructTailTex`）都**由词法自己
///   在走查顺序里**认出来（见 `visible_atoms.dart` 里的两条注释），本函数不再补账。
///
/// ★★ **为什么删掉原来那段"补尾垫再按源偏移排序"**（这是修正，不是简化）：
///   排序会毁掉词法刻意维持的渲染顺序 —— 实测 `\sqrt[3]{x}` 在源码里次数在前、
///   叶盒里次数在**后**，排完序两列就整体错位（点次数落到被开方数，§11.26 三）。
///   同一件事在 `\sum` 的上下限上更明显（引擎把上限画在算子**之前**）。
List<VisibleAtom> atomsForHitTest(String renderTex) =>
    lexVisibleAtoms(renderTex);

/// 一个被注入的常量串
class _Marker {
  const _Marker(this.text,
      {this.isStructTail = false, this.atOffset = 0, this.lenOverride});

  final String text;

  /// ★ 是不是**结构尾垫**（§11.18）：它的语义是"**结构末尾**"——
  /// 注入点在**内容末尾**（花括号之内，装饰才会跟着变长），
  /// 但点击它要回到**结构末尾**（= 内容末尾 + 收尾 `}`）——
  /// 因为整段尾垫在视觉上属于**装饰**（横线的那一截），指它 = 指这个结构。
  final bool isStructTail;

  /// 插入点在匹配串里的**偏移**（默认 0 = 串首）。目前只有 `\dfrac` 用到：
  /// 它是在 `\frac` 里插一个 `d`，插入点是串内第 1 个字符处。
  final int atOffset;

  /// 实际插入的长度（默认 = 整个串长）。`\dfrac` 只插入 1 个字符。
  final int? lenOverride;

  int get len => lenOverride ?? text.length;
}

/// 所有可能被注入的常量串（长串在前，避免短串把长串的一部分也匹配上）
List<_Marker> get _kMarkers => <_Marker>[
      _Marker(kCursorSplitTex),
      _Marker(kCurrentSlotTex),
      _Marker(kEmptySlotTex),
      _Marker(kCursorTex),
      _Marker(kEnvCellFillTex),
      // ★★ 2026-10-24（批 4 · C1）：行内 `\frac` → `\dfrac` 只多插一个 `d`
      //   （`\` **之后**），所以插入点 = 串内第 1 个字符处、长度 1。
      _Marker(kBigFrac, atOffset: 1, lenOverride: 1),
      _Marker(kStructTailTex, isStructTail: true),
    ];

/// 渲染 tex 的偏移 [renderOffset] → **原始 tex** 的偏移。
///
/// 点在被注入的串内部（占位方框、光标条、**结构尾垫**）时返回**该插入点** —— 于是
/// "点空槽的方框"会落到空槽的偏移上、"点尾垫"会落到**结构末尾**，再经位点吸附就是合法落点 ✓
///
/// ★★ 2026-10-18 晚（性能实测）：**插入点表按 tex 缓存**。
///   原来每次调用都要对 5 个注入串各跑一遍 `indexOf`（全串扫描）、再过滤、排序
///   —— 实测**每次约 2.5 µs**；而选区铺底对**每个叶盒**都要换两次（90 个盒 = 180 次）
///   ⇒ 单段公式一次拖选就要 **0.45 ms**，一页几十段就上百毫秒（"大面积拖选卡"的元凶之一）。
///   它是个**纯函数**、只依赖 tex ⇒ 缓存最后一条 tex 的插入点表，重复调用降到 O(插入点数)。
int renderToSourceOffset(String renderTex, int renderOffset) {
  if (renderOffset <= 0) return 0;
  final List<({int at, int len, bool tail})> ins = _insertionsOf(renderTex);

  var shift = 0;
  for (final ({int at, int len, bool tail}) e in ins) {
    if (renderOffset <= e.at) break;
    // ★ 尾垫（§11.18）：**严格越过起点**才算"结构末尾"——
    //   起点那一格是 `2` 的右边界（点式子的右半边必须仍落到"内容末尾"，
    //   否则用户再也点不到内容末尾）；与其它原子一致：左半取左边界、右半取右边界。
    final bool inside = e.tail
        ? renderOffset <= e.at + e.len // 尾垫：连它的**末端**也算结构末尾
        : renderOffset < e.at + e.len; // 其它注入串：严格内部（保持原语义）
    if (inside) {
      return e.tail
          ? _tailSourceOffset(renderTex, e.at, e.len, e.at - shift)
          : e.at - shift; // 点在注入串内部 → 插入点
    }
    shift += e.len;
  }
  return renderOffset - shift;
}

/// 上一条 tex 的插入点表（缓存；纯函数 ⇒ 安全）
String? _cachedTex;
List<({int at, int len, bool tail})>? _cachedIns;

/// 找出这条渲染 tex 里**真正生效**的注入串（去掉被更长匹配完全包住的那些，按位置排序）
List<({int at, int len, bool tail})> _insertionsOf(String renderTex) {
  // ★ 用 `==`（值相等）而不是 `identical`：`renderMathTex` 每次构建都会给出**新的**
  //   String 实例，内容一样 ⇒ 只看实例就会一直不命中（等于没缓存）。
  if (_cachedTex == renderTex && _cachedIns != null) {
    return _cachedIns!;
  }
  final List<({int at, int len, bool tail})> found =
      <({int at, int len, bool tail})>[];
  for (final _Marker m in _kMarkers) {
    if (m.text.isEmpty) continue;
    var i = renderTex.indexOf(m.text);
    while (i >= 0) {
      found.add((
        at: i + m.atOffset,
        len: m.len,
        tail: m.isStructTail,
      ));
      i = renderTex.indexOf(m.text, i + 1);
    }
  }
  // 丢掉"被更长的匹配完全包住"的那些（否则 `}`+光标+`\text{` 会把里面的光标再算一遍）
  final List<({int at, int len, bool tail})> ins =
      <({int at, int len, bool tail})>[
    for (final ({int at, int len, bool tail}) a in found)
      if (!found.any((({int at, int len, bool tail}) b) =>
          b.at <= a.at && b.at + b.len >= a.at + a.len && b.len > a.len))
        a,
  ]..sort((({int at, int len, bool tail}) a,
          ({int at, int len, bool tail}) b) =>
      a.at.compareTo(b.at));
  _cachedTex = renderTex;
  _cachedIns = ins;
  return ins;
}

/// 尾垫的源偏移 = **插入点 + 收尾 `}`**（若紧跟着一个 `}`）。
///
/// 插入点本身是**内容末尾**（尾垫塞在花括号之内），而尾垫代表的是**结构末尾**；
/// 花括号形式下两者刚好差一个 `}`（`\sqrt{2}` → 内容末尾 7、结构末尾 8）；
/// 裸参数形式（`\sqrt2`）没有 `}` ⇒ 两者相同 ✓。
int _tailSourceOffset(String renderTex, int at, int len, int insertionPoint) {
  final int after = at + len;
  if (after < renderTex.length && renderTex[after] == '}') {
    return insertionPoint + 1;
  }
  return insertionPoint;
}
