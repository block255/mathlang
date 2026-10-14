// ============================================================
//  数语引擎 · 问 0「流内数学映射可行性」实验页（S1-A / A 组）
//  验收依据：notes/design/技术选型与风险.md 第 9.3 节「问 0」四子项
//    ① 文字与数学【同行混排】的基线对齐
//    ② 用 \cursor 把【光标画进数学内部】（引擎内置命令，默认已注册）
//    ③ 点击公式能否拿到坐标、能否【反查回源偏移】（引擎公开 API 面已查明）
//    ④ 100 行含行内公式的段落【滚动/构建性能】
//
//  架构主张：真相 = 一条一维字符串（_buf），光标 = 一个整数（_caret）。
//  数学不是"对象"，只是缓冲区里被 $ 包起来的一段文本，渲染时投影成二维。
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_math_fork/tex.dart'
    show TexParser, TexParserSettings, SyntaxTree, SyntaxNode;
// ③ 的关键：RenderEditableLine（含 getCaretIndexForPoint / getEndpointForCaretIndex）
// 在 src/ 内且未被公开导出（flutter_math.dart 只 show SelectableMath）。
// 这里做一次"实现导入（implementation import）"的最小验证：能否编译？Math 的渲染对象是不是它？
// ignore: implementation_imports
import 'package:flutter_math_fork/src/render/layout/line_editable.dart' show RenderEditableLine;

const double kFont = 20;

class InlineMathPage extends StatefulWidget {
  const InlineMathPage({super.key});

  @override
  State<InlineMathPage> createState() => _InlineMathPageState();
}

class _InlineMathPageState extends State<InlineMathPage> {
  /// ★ 唯一事实来源：一维字符缓冲区（= md + LaTeX 源）
  String _buf = r'设 $x^2+1$ 为多项式，$\frac{a}{b}=\sqrt{2}$ 为常数，求 $x$ 的值。';

  /// ★ 光标 = 整数偏移
  int _caret = 0;

  final FocusNode _focus = FocusNode();
  bool _baselineAlign = false; // ① 的开关：baseline vs middle
  bool _showPerf = false; // ④
  bool _showDiag = true;
  String _tapInfo = '（还没点过公式）';
  int _tapCount = 0;

  @override
  void initState() {
    super.initState();
    _caret = _buf.length;
    // 把 Flutter 的未捕获异常文本抓回界面 —— 浏览器控制台只给"Assertion failed: ...box.dart:2251"
    // 这种截断信息，看不到断言正文，排查不了根因。
    FlutterError.onError = (FlutterErrorDetails d) {
      final String msg = d.exceptionAsString();
      if (!_errors.contains(msg)) {
        _errors.insert(0, msg);
        if (_errors.length > 3) _errors.removeLast();
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
      }
      FlutterError.presentError(d);
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  final List<String> _errors = <String>[];

  @override
  void dispose() {
    _tick.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---------------- 编辑操作：全部只是"改字符串 + 移整数" ----------------

  void _insert(String s) => setState(() {
        _buf = _buf.replaceRange(_caret, _caret, s);
        _caret += s.length;
      });

  void _backspace() {
    if (_caret == 0) return;
    setState(() {
      _buf = _buf.replaceRange(_caret - 1, _caret, '');
      _caret -= 1;
    });
  }

  void _move(int d) => setState(() => _caret = (_caret + d).clamp(0, _buf.length));

  /// 面板动作 = 往缓冲区【插字符】+ 把光标【移进第一个占位符】
  /// （这就是"符号面板不需要任何结构魔法"的全部含义）
  void _insertTemplate(String tex) {
    final seg = '\$$tex\$';
    final idx = seg.indexOf('{}');
    setState(() {
      _buf = _buf.replaceRange(_caret, _caret, seg);
      _caret = _caret + (idx < 0 ? seg.length : idx + 1);
    });
  }

  // ---------------- 缓冲区 → 段（文字段 / 数学段） ----------------

  List<Seg> _segments() {
    final segs = <Seg>[];
    var i = 0;
    while (i < _buf.length) {
      if (_buf[i] == r'$') {
        final end = _buf.indexOf(r'$', i + 1);
        if (end == -1) {
          segs.add(Seg.text(i, _buf.substring(i)));
          break;
        }
        segs.add(Seg.math(i + 1, _buf.substring(i + 1, end)));
        i = end + 1;
      } else {
        final next = _buf.indexOf(r'$', i);
        final stop = next == -1 ? _buf.length : next;
        segs.add(Seg.text(i, _buf.substring(i, stop)));
        i = stop;
      }
    }
    return segs;
  }

  // ---------------- 光标"位点"吸附 ----------------
  // 光标只能落在【合法位点】：不能落进控制序列 \frac 的中间，否则注入 \cursor{} 会把命令切开。
  // 这正是"位点显式化"（技术选型与风险.md 5.1.1）在最小规模上的体现。
  static bool _isLetter(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

  static int _snap(String tex, int rel) {
    var r = rel.clamp(0, tex.length);
    bool at(int i) => i >= 0 && i < tex.length && _isLetter(tex.codeUnitAt(i));
    if (at(r - 1) && at(r)) {
      while (at(r)) {
        r++;
      }
    } else if (r > 0 && tex.codeUnitAt(r - 1) == 0x5C && at(r)) {
      while (at(r)) {
        r++;
      }
    }
    return r;
  }

  // ---------------- 渲染投影 ----------------

  final Map<int, GlobalKey> _mathKeys = <int, GlobalKey>{};

  InlineSpan _mathSpan(Seg s) {
    final start = s.start;
    final end = s.start + s.length;
    var tex = s.tex;
    if (_caret >= start && _caret <= end) {
      final rel = _snap(tex, _caret - start);
      tex = tex.substring(0, rel) + r'\cursor{}' + tex.substring(rel);
    }
    final GlobalKey key = _mathKeys.putIfAbsent(start, () => GlobalKey());
    return WidgetSpan(
      alignment: _baselineAlign ? PlaceholderAlignment.baseline : PlaceholderAlignment.middle,
      baseline: _baselineAlign ? TextBaseline.alphabetic : null,
      child: GestureDetector(
        onTapDown: (d) => _handleMathTap(key, start, s.tex, d.globalPosition),
        child: MouseRegion(
          cursor: SystemMouseCursors.text,
          child: Math.tex(
            key: key,
            tex,
            mathStyle: MathStyle.text,
            textStyle: const TextStyle(fontSize: kFont),
            onErrorFallback: (e) => Text('❌ ${e.messageWithType}',
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          ),
        ),
      ),
    );
  }

  /// ③ 的关键探查：Math 的渲染对象到底是什么？是不是可编辑行（RenderEditableLine）？
  String _inspect(RenderObject? ro) {
    if (ro == null) return '拿不到渲染对象';
    final types = <String>[];
    void walk(RenderObject o, int depth) {
      types.add(o.runtimeType.toString());
      if (depth > 0) o.visitChildren((c) => walk(c, depth - 1));
    }

    walk(ro, 3);
    return '根=${ro.runtimeType} · is RenderEditableLine=${ro is RenderEditableLine} · '
        '子树类型=${types.toSet().take(6).join("/")}';
  }

  InlineSpan _caretBar() => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(width: 1.5, height: kFont * 1.25, color: Colors.blue.shade600),
      );

  List<InlineSpan> _spans() {
    final out = <InlineSpan>[];
    for (final s in _segments()) {
      if (s.isMath) {
        out.add(_mathSpan(s));
        continue;
      }
      final t = s.text;
      final start = s.start;
      final end = s.start + t.length;
      if (_caret >= start && _caret <= end) {
        final rel = _caret - start;
        out.add(TextSpan(text: t.substring(0, rel)));
        out.add(_caretBar());
        out.add(TextSpan(text: t.substring(rel)));
      } else {
        out.add(TextSpan(text: t));
      }
    }
    return out;
  }

  // ---------------- ④ 隔离实验：行数 × 是否含公式 ----------------
  // 目的不是追求好数字，而是给 S2 定预算：**一页放多少块、按页渲染多少行是安全的**。

  final Map<String, int> _perf = <String, int>{};
  List<List<Object>> _queue = <List<Object>>[];
  int _jobN = 0;
  bool _jobMath = true;
  bool _measuring = false;

  void _measure() {
    _perf.clear();
    _queue = <List<Object>>[
      <Object>[10, true],
      <Object>[25, true],
      <Object>[100, true],
      <Object>[100, false], // 隔离项：同样 100 行但**不含公式**（纯文字）
    ];
    _runNext();
  }

  void _runNext() {
    if (_queue.isEmpty) {
      setState(() => _measuring = false);
      return;
    }
    final List<Object> job = _queue.removeAt(0);
    setState(() {
      _measuring = true;
      _jobN = job[0] as int;
      _jobMath = job[1] as bool;
    });
    final sw = Stopwatch()..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      sw.stop();
      setState(() {
        _perf['$_jobN行${_jobMath ? "+公式" : "纯文字"}'] = sw.elapsedMicroseconds ~/ 1000;
      });
      // 让"测完的帧"先落地，再测下一项
      WidgetsBinding.instance.addPostFrameCallback((_) => _runNext());
    });
  }

  /// ★ 刻意用 CrossAxisAlignment.stretch + TextWidthBasis.parent：
  /// 若让 Text.rich 走"固有宽度（intrinsic width）"路径，Math 作为 WidgetSpan 子项会抛
  /// `RenderBox was not laid out`（box.dart:2251）—— 这是混排架构的一条真实约束。
  Widget _perfColumn(int n, bool withMath) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List<Widget>.generate(
            n,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
              child: Text.rich(
                textWidthBasis: TextWidthBasis.parent,
                TextSpan(
                  style: const TextStyle(fontSize: kFont, color: Colors.black87),
                  children: <InlineSpan>[
                    TextSpan(text: '第 ${i + 1} 行：'),
                    if (withMath)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Math.tex(
                          '\\frac{a_{$i}}{b}+\\sqrt{x_{$i}} \\le \\sum_{k=1}^{$i} k',
                          mathStyle: MathStyle.text,
                          textStyle: const TextStyle(fontSize: kFont),
                        ),
                      )
                    else
                      const TextSpan(text: 'a_i / b + sqrt(x_i) <= sum_{k=1}^{i} k'),
                    const TextSpan(text: ' 是待验证的公式。'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  // ---------------- ③(b) 自建命中：渲染子树叶盒 ↔ AST 位点表 ----------------
  // 路线 (b)：**零 src 依赖**。原理：
  //   · 渲染侧：遍历 Math 的渲染子树，收集"叶盒"（相对 Math 根盒的局部坐标）
  //   · 结构侧：用公开 API 自己 parse 一次，遍历 AST 收集"叶子原子"的源码区间
  //   · 引擎文档保证 GreenNode.children 的顺序 == **光标访问顺序**（即阅读顺序）
  //   · 两侧按同一次序 zip → 点中第 k 个叶盒即第 k 个原子 → 取左/右边界得源偏移

  /// 收集渲染子树的叶盒（相对 [root] 的局部坐标）
  ///
  /// ★ 关键：必须**过滤装饰盒/尺寸失真盒**。
  /// 实测 `\frac{a}{b}=\sqrt{2}` 的渲染叶盒有 5 个（分子 a / 分母 b / = / √2 的 2 / **根号符号**），
  /// 而 AST 只有 4 个原子 —— 根号的分隔符在 AST 里不是子节点（由父节点绘制）。
  /// 且根号符号那个盒的 `localToGlobal` 结果尺寸失真（x=26..1370, y=-2..1070）。
  /// 判据：**真原子的矩形必然落在 Math 控件自身的边界内**。
  List<AtomBox> _collectLeafBoxes(RenderObject root) {
    final Rect bounds =
        (root is RenderBox && root.hasSize) ? (Offset.zero & root.size) : Rect.largest;
    final Rect ok = bounds.inflate(4);
    final all = <AtomBox>[];
    void walk(RenderObject o) {
      var hasChild = false;
      o.visitChildren((RenderObject c) {
        hasChild = true;
        walk(c);
      });
      if (!hasChild && o is RenderBox && o.hasSize) {
        all.add(AtomBox(o.localToGlobal(Offset.zero, ancestor: root) & o.size));
      }
    }

    walk(root);
    // 过滤：① 必须在 Math 控件边界内（剔除尺寸失真的装饰盒，如根号分隔符）
    //       ② 宽度 ≥ 2px（剔除我们自己注入的 `\cursor{}` 光标条，它宽 1.5px）
    final inside = all
        .where((AtomBox b) =>
            ok.contains(b.rect.topLeft) && ok.contains(b.rect.bottomRight) && b.rect.width >= 2)
        .toList();
    _leafTotal = all.length;
    return inside.isEmpty ? all : inside;
  }

  int _leafTotal = 0;

  // ---------------- ⑤ 单公式重绘（打字延迟预算） ----------------
  // 架构承诺：打字时**只重绘变化的那一个公式**，不整页重排。
  // 这里用 ValueListenableBuilder 把"变化"限制在这一个 Math widget 上，
  // 测"从改值到该帧结束"的耗时 ≈ 敲一个字符到屏幕上看到结果的延迟。

  final ValueNotifier<int> _tick = ValueNotifier<int>(0);
  int? _redrawMs;

  void _measureRedraw() {
    final sw = Stopwatch()..start();
    _tick.value++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      sw.stop();
      if (mounted) setState(() => _redrawMs = sw.elapsedMicroseconds ~/ 1000);
    });
  }

  Widget _redrawRow() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          children: <Widget>[
            const Text('⑤ 单公式重绘：', style: TextStyle(fontSize: 12)),
            ValueListenableBuilder<int>(
              valueListenable: _tick,
              builder: (BuildContext c, int v, Widget? _) => Math.tex('a_{$v}+b',
                  mathStyle: MathStyle.text, textStyle: const TextStyle(fontSize: kFont)),
            ),
            const SizedBox(width: 12),
            OutlinedButton(onPressed: _measureRedraw, child: const Text('测一帧')),
            const SizedBox(width: 8),
            Text(_redrawMs == null ? '（未测）' : '$_redrawMs ms / 帧',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      );

  // ---------------- ① 高结构对齐对比（baseline vs middle 定稿用） ----------------
  // 普通段落看不出差别，必须用**高结构**（\sum 带上限 / 嵌套分式 / 矩阵）才区分得出。
  // ★ 两种模式**同时渲染**（上绿=middle、下黄=baseline），一张截图即可对比，不依赖切换顺序。

  final GlobalKey _tallMidKey = GlobalKey();
  final GlobalKey _tallBaseKey = GlobalKey();
  double? _tallMidH;
  double? _tallBaseH;

  void _measureTall() {
    final RenderObject? a = _tallMidKey.currentContext?.findRenderObject();
    final RenderObject? b = _tallBaseKey.currentContext?.findRenderObject();
    setState(() {
      _tallMidH = (a is RenderBox && a.hasSize) ? a.size.height : null;
      _tallBaseH = (b is RenderBox && b.hasSize) ? b.size.height : null;
    });
  }

  static const List<String> _tallTexs = <String>[
    r'\sum_{k=1}^{n} k^2',
    r'\frac{a}{\frac{b}{c}}',
    r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}',
  ];

  Widget _tallLine(GlobalKey key, bool baseline, String tag) => Container(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
        color: baseline ? const Color(0xFFFFF8E1) : const Color(0xFFE8F5E9),
        child: Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: kFont, height: 1.5, color: Colors.black87),
            children: <InlineSpan>[
              TextSpan(text: '$tag '),
              for (final String t in _tallTexs) ...<InlineSpan>[
                WidgetSpan(
                  alignment: baseline ? PlaceholderAlignment.baseline : PlaceholderAlignment.middle,
                  baseline: baseline ? TextBaseline.alphabetic : null,
                  child: Math.tex(t,
                      mathStyle: MathStyle.text, textStyle: const TextStyle(fontSize: kFont)),
                ),
                const TextSpan(text: ' 中文 '),
              ],
            ],
          ),
        ),
      );

  Widget _alignCompare() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Text('① 高结构对齐（绿=middle / 黄=baseline）：', style: TextStyle(fontSize: 12)),
                OutlinedButton(onPressed: _measureTall, child: const Text('量行高')),
                const SizedBox(width: 8),
                Text(
                  'middle ${_tallMidH?.toStringAsFixed(1) ?? "?"}px · baseline ${_tallBaseH?.toStringAsFixed(1) ?? "?"}px',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            _tallLine(_tallMidKey, false, 'middle：'),
            const SizedBox(height: 3),
            _tallLine(_tallBaseKey, true, 'baseline：'),
          ],
        ),
      );

  /// 收集 AST 的叶子原子（区间是**相对该段 tex 的 0-based 偏移**）
  List<AtomRange> _collectAtoms(String tex) {
    final out = <AtomRange>[];
    try {
      final SyntaxTree tree =
          SyntaxTree(greenRoot: TexParser(tex, const TexParserSettings()).parse());
      void walk(SyntaxNode n) {
        final kids = n.children.where((SyntaxNode? c) => c != null).cast<SyntaxNode>().toList();
        if (kids.isEmpty) {
          // ★ 引擎的坑（已实测）：`GreenNode.getRange(pos)` 返回
          //   TextRange(start: pos + 1, end: pos + capturedCursor)，
          //   而 capturedCursor = editingWidth - 1 → 单字符叶子的区间是 **[pos+1, pos)**（反的！）。
          //   所以：**range.start 才是该原子在 tex 中的 0-based 下标**，end 无意义，
          //   正确的右端点 = start + editingWidth。
          final int start = n.range.start;
          out.add(AtomRange(start, start + n.value.editingWidth, n.value.runtimeType.toString()));
          return;
        }
        for (final SyntaxNode c in kids) {
          walk(c);
        }
      }

      walk(tree.root);
    } catch (_) {
      // 解析失败时返回空表，由调用方显示"数量不等"
    }
    return out;
  }

  void _handleMathTap(GlobalKey key, int spanStart, String tex, Offset globalPos) {
    final RenderObject? rootRo = key.currentContext?.findRenderObject();
    if (rootRo is! RenderBox) {
      setState(() => _tapInfo = '拿不到渲染对象');
      return;
    }
    final Offset local = rootRo.globalToLocal(globalPos);
    final List<AtomBox> boxes = _collectLeafBoxes(rootRo);
    // ★ 用**自己**的可见原子扫描结果做映射（引擎的 range 是渲染空间坐标，不能用）
    final List<AtomRange> atoms = _lexVisibleAtoms(tex);

    var hit = -1;
    for (var i = 0; i < boxes.length; i++) {
      if (boxes[i].rect.inflate(2).contains(local)) {
        hit = i;
        break;
      }
    }
    var how = '包含命中';
    if (hit < 0 && boxes.isNotEmpty) {
      var best = double.infinity;
      for (var i = 0; i < boxes.length; i++) {
        final double d = (boxes[i].rect.center - local).distance;
        if (d < best) {
          best = d;
          hit = i;
        }
      }
      how = '就近命中（${best.toStringAsFixed(1)}px）';
    }

    String detail;
    int? newCaret;
    if (hit >= 0 && boxes.length == atoms.length) {
      final AtomBox box = boxes[hit];
      final AtomRange atom = atoms[hit];
      final bool leftHalf = local.dx < box.rect.center.dx;
      final int rel = leftHalf ? atom.start : atom.end;
      newCaret = (spanStart + rel).clamp(0, _buf.length);
      detail = '叶盒#$hit ${box.rect.left.toStringAsFixed(0)},${box.rect.top.toStringAsFixed(0)} '
          '${box.rect.width.toStringAsFixed(0)}×${box.rect.height.toStringAsFixed(0)}'
          ' ↔ 原子 ${atom.type.split("#").first} [${atom.start},${atom.end})'
          ' → 取${leftHalf ? "左" : "右"}边界 → 段内 $rel → 缓冲区 $_caret→$newCaret';
    } else {
      detail = '⚠️ 有效叶盒 ${boxes.length} 个（原始 $_leafTotal 个） vs 原子 ${atoms.length} 个'
          '（数量不等则下标映射不可靠）';
    }

    setState(() {
      _tapCount++;
      if (newCaret != null) _caret = newCaret;
      _structDump = _dumpStructure(rootRo, tex);
      final String atomList =
          atoms.map((AtomRange a) => '[${a.start},${a.end})').join(' ');
      final String boxList = boxes
          .map((AtomBox b) => '${b.rect.left.toStringAsFixed(0)}..${b.rect.right.toStringAsFixed(0)}')
          .join(' ');
      _tapInfo = '点中「$tex」· 局部 (${local.dx.toStringAsFixed(1)}, ${local.dy.toStringAsFixed(1)}) · $how'
          '\n$detail'
          '\n有效叶盒 x 区间: $boxList'
          '\nAST 原子表: $atomList'
          '\n${_inspect(rootRo)}';
    });
  }

  // ---------------- ③(b) 结构对照 dump（先测量，不猜） ----------------

  String _structDump = '';

  String _dumpStructure(RenderObject root, String tex) {
    final sb = StringBuffer();
    sb.writeln('— 渲染叶盒（相对 Math 根盒，x/y 区间）—');
    var i = 0;
    void walk(RenderObject o, int depth) {
      var hasChild = false;
      o.visitChildren((RenderObject c) {
        hasChild = true;
        walk(c, depth + 1);
      });
      if (!hasChild && o is RenderBox && o.hasSize) {
        final Rect r = o.localToGlobal(Offset.zero, ancestor: root) & o.size;
        sb.writeln('  [$i] d$depth ${o.runtimeType.toString().split("#").first} '
            'x=${r.left.toStringAsFixed(0)}..${r.right.toStringAsFixed(0)} '
            'y=${r.top.toStringAsFixed(0)}..${r.bottom.toStringAsFixed(0)}');
        i++;
      }
    }

    walk(root, 0);
    sb.writeln('  （原始 $i 个；过滤后有效 ${_collectLeafBoxes(root).length} 个）');
    sb.writeln('— AST 原子（引擎渲染空间坐标，仅供对照，不作源偏移用）—');
    final List<AtomRange> atoms = _collectAtoms(tex);
    for (var k = 0; k < atoms.length; k++) {
      sb.writeln('  <$k> ${atoms[k].type.split("#").first} [${atoms[k].start},${atoms[k].end})');
    }
    sb.writeln('— 自建可见原子扫描器（**实际用于源偏移**）—');
    final List<AtomRange> vis = _lexVisibleAtoms(tex);
    for (var k = 0; k < vis.length; k++) {
      final String txt = tex.substring(vis[k].start, vis[k].end);
      sb.writeln('  {$k} ${vis[k].type} [${vis[k].start},${vis[k].end}) = 「$txt」');
    }
    return sb.toString();
  }

  // ---------------- ③(b) 可见原子扫描器（**这才是正确的源偏移来源**） ----------------
  // 为什么不能用引擎的 range/caretPositions：实测它们给出 [2,3) [4,5) [6,7) [8,9)，
  // 那是**渲染空间的编辑坐标**（只覆盖渲染出来的原子，不含 \frac{} ^ _ 等命令/结构字符），
  // 不是源码下标。所以源偏移必须由我们自己从 tex 词法化得到。

  static const Set<String> _kStructureCmds = <String>{
    'frac', 'dfrac', 'tfrac', 'sqrt', 'left', 'right', 'begin', 'end', 'binom',
    'overline', 'underline', 'vec', 'hat', 'bar', 'tilde', 'dot', 'ddot',
    'overrightarrow', 'xrightarrow', 'operatorname', 'mathrm', 'mathbf', 'mathbb',
    'mathcal', 'mathfrak', 'mathit', 'text', 'displaystyle', 'textstyle',
    'quad', 'qquad', 'limits', 'nolimits', 'not', 'color', 'phantom', 'enclose',
    'rule', 'kern', 'hspace', 'middle', 'big', 'Big', 'bigg', 'Bigg',
  };

  /// 把 tex 扫成"可见原子"列表（每个原子的 [start,end) 是**相对该段 tex 的源区间**）
  /// 规则（覆盖我们方言的子集）：
  ///   · 结构命令（\frac \sqrt \left …）本身**不是**可见原子 → 跳过，由参数贡献原子
  ///   · 符号命令（\alpha \le \sum …）**是**一个可见原子
  ///   · `{ } ^ _ &` 与空格、`\\` 行分隔 → 跳过
  ///   · 其余每个字符（字母/数字/运算符）各自是一个可见原子
  List<AtomRange> _lexVisibleAtoms(String tex) {
    final out = <AtomRange>[];
    var i = 0;
    while (i < tex.length) {
      // 行分隔 \\ 跳过
      if (tex.startsWith('\\\\', i)) {
        i += 2;
        continue;
      }
      final String c = tex[i];
      if (c == '\\') {
        if (i + 1 < tex.length && _isLetter(tex.codeUnitAt(i + 1))) {
          var j = i + 1;
          while (j < tex.length && _isLetter(tex.codeUnitAt(j))) {
            j++;
          }
          final String name = tex.substring(i + 1, j);
          if (!_kStructureCmds.contains(name)) {
            out.add(AtomRange(i, j, '\\$name'));
          }
          i = j;
          continue;
        }
        if (i + 1 < tex.length) {
          out.add(AtomRange(i, i + 2, 'esc'));
          i += 2;
          continue;
        }
        i++;
        continue;
      }
      if (c == '{' || c == '}' || c == '^' || c == '_' || c == '&' || c == ' ' || c == '\n') {
        i++;
        continue;
      }
      out.add(AtomRange(i, i + 1, c));
      i++;
    }
    return out;
  }

  // ---------------- ① 诊断（解析预校验 + 耗时） ----------------

  List<String> _diagnose() {
    final out = <String>[];
    final math = _segments().where((s) => s.isMath).toList();
    if (math.isEmpty) out.add('（当前没有数学段）');
    for (final s in math) {
      final sw = Stopwatch()..start();
      try {
        // 实测签名（编译器纠正）：TexParser(String content, TexParserSettings settings).parse()
        // → EquationRowNode（再包成 SyntaxTree）。旧文档里的 TexParser().parse() 是错的。
        TexParser(s.tex, const TexParserSettings()).parse();
        sw.stop();
        out.add('✅ 解析通过  「${s.tex}」  ${(sw.elapsedMicroseconds / 1000).toStringAsFixed(2)} ms');
      } catch (e) {
        sw.stop();
        out.add('❌ 解析失败  「${s.tex}」  $e');
      }
    }
    return out;
  }

  // ---------------- ④ 100 行性能列表 ----------------

  /// ⚠️ A/B 实验（2026-10-13 22:45）：原实现是 `ListView.builder`（100 项），
  /// 结果伴随 `RenderBox was not laid out: RenderRepaintBoundary#…` 断言 ——
  /// 而 ListView 默认会给**每个列表项**包一层 RepaintBoundary（addRepaintBoundaries: true）。
  /// 这里改用 SingleChildScrollView + Column（**不产生 item 级 RepaintBoundary**）并降到 25 行，
  /// 用来隔离"到底是 ListView 的 RepaintBoundary 还是 Math 本身"。
  Widget _perfList() => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List<Widget>.generate(
            25,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
              child: Text.rich(
                textWidthBasis: TextWidthBasis.parent,
                TextSpan(
                  style: const TextStyle(fontSize: kFont, color: Colors.black87),
                  children: <InlineSpan>[
                    TextSpan(text: '第 ${i + 1} 行：'),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Math.tex(
                        '\\frac{a_{$i}}{b}+\\sqrt{x_{$i}} \\le \\sum_{k=1}^{$i} k',
                        mathStyle: MathStyle.text,
                        textStyle: const TextStyle(fontSize: kFont),
                      ),
                    ),
                    const TextSpan(text: ' 是待验证的公式。'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  // ---------------- UI ----------------

  Widget _bar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            // 注意：这里刻意不用 Chip —— Chip 内部对 label 强制 maxLines:1 + fade，
            // 长文本会被"淡出裁切"且没有省略号（全局经验 #11）
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blueGrey.shade100),
              ),
              child: Text(
                  '缓冲区 ${_buf.length} 字符 · 光标 @$_caret · 段 ${_segments().length}'
                  '${_perf.isEmpty ? "" : " · 【${_perf.entries.map((MapEntry<String, int> e) => "${e.key}=${e.value}ms").join(" / ")}】"}',
                  style: const TextStyle(fontSize: 12)),
            ),
            OutlinedButton(
              onPressed: () => _insertTemplate(r'\frac{}{}'),
              child: const Text('面板：分式'),
            ),
            OutlinedButton(
              onPressed: () => _insertTemplate(r'\sqrt{}'),
              child: const Text('面板：根号'),
            ),
            OutlinedButton(
              onPressed: () => _insert(r'\alpha'),
              child: const Text('面板：α'),
            ),
            OutlinedButton(
              onPressed: () => _insert(r'$x^{}$'),
              child: const Text('面板：上标'),
            ),
            OutlinedButton(onPressed: _backspace, child: const Text('退格')),
            Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              const Text('① 基线对齐(baseline)', style: TextStyle(fontSize: 12)),
              Switch(
                value: _baselineAlign,
                onChanged: (v) => setState(() => _baselineAlign = v),
              ),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text('④ 性能隔离实验${_perf.isEmpty ? "" : "（${_perf.length}/4）"}',
                  style: const TextStyle(fontSize: 12)),
              Switch(
                value: _showPerf,
                onChanged: (v) {
                  setState(() => _showPerf = v);
                  if (v) _measure();
                },
              ),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              const Text('诊断', style: TextStyle(fontSize: 12)),
              Switch(value: _showDiag, onChanged: (v) => setState(() => _showDiag = v)),
            ]),
          ],
        ),
      );

  Widget _paragraphCard() => Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: kFont, height: 1.7, color: Colors.black87),
            children: _spans(),
          ),
        ),
      );

  Widget _diagPanel() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFC),
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('① + ③ 诊断（解析预校验 / 点击命中）',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            ..._diagnose().map((t) => Text(t, style: const TextStyle(fontSize: 12))),
            Text('③ 点击测试 $_tapCount 次：$_tapInfo', style: const TextStyle(fontSize: 12)),
            if (_errors.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              const Text('⚠️ 捕获到的异常（全文）：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ..._errors.map((e) => Text(e, style: const TextStyle(fontSize: 11, color: Colors.red))),
            ],
            if (_structDump.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              const Text('③(b) 结构对照（渲染叶盒 ↔ AST 原子）：',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              SelectableText(_structDump,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.4)),
            ],
            const Text(
              '③ 注意：引擎公开 API 面【不含】RenderLine.getCaretIndexForPoint / getEndpointForCaretIndex'
              '（它们在 src/ 内且被 show 限定）→ 坐标→偏移的反查需要用 src 导入或自带渲染层，见实验结论。',
              style: TextStyle(fontSize: 11, color: Colors.red),
            ),
          ],
        ),
      );

  Widget _sourcePanel() => Expanded(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1A202C),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ListView(
            children: <Widget>[
              const Text('高级：查看源码（默认关闭的产品功能，这里用来看真相）',
                  style: TextStyle(fontSize: 11, color: Colors.white38)),
              const SizedBox(height: 6),
              SelectableText(_buf,
                  style: const TextStyle(fontSize: 13, color: Colors.greenAccent, fontFamily: 'monospace')),
              const SizedBox(height: 6),
              Text('光标偏移 = $_caret', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
        ),
      );

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _move(1);
      return KeyEventResult.handled;
    }
    final ch = e.character;
    if (ch != null && ch.isNotEmpty && ch.codeUnitAt(0) >= 0x20) {
      _insert(ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('★ 问 0 · 流内数学映射可行性'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(24),
          child: Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('一维缓冲区 + 渲染投影：数学与文字同权（A 组自研内核的最小验证）',
                style: TextStyle(fontSize: 12)),
          ),
        ),
      ),
      body: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _bar(),
            _paragraphCard(),
            _redrawRow(),
            _alignCompare(),
            if (_showDiag)
              // 用 Expanded 吃掉剩余空间（内部滚动）→ 结构上不会再出现 RenderFlex overflow
              Expanded(child: SingleChildScrollView(child: _diagPanel())),
            const SizedBox(height: 8),
            if (_measuring)
              Expanded(child: _perfColumn(_jobN, _jobMath))
            else if (_showPerf)
              _perfList()
            else
              _sourcePanel(),
          ],
        ),
      ),
    );
  }
}

/// 缓冲区里的一段：文字段或数学段（数学段记录它在缓冲区中的起始偏移）
class Seg {
  Seg.text(this.start, this.text)
      : isMath = false,
        tex = '';
  Seg.math(this.start, this.tex)
      : isMath = true,
        text = '';

  final int start;
  final bool isMath;
  final String text;
  final String tex;

  int get length => isMath ? tex.length : text.length;
}

/// ③(b)：渲染子树里的一个叶盒（相对 Math 根盒的局部坐标）
class AtomBox {
  AtomBox(this.rect);
  final Rect rect;
}

/// ③(b)：AST 的一个叶子原子（区间相对该段 tex，0-based）
class AtomRange {
  AtomRange(this.start, this.end, this.type);
  final int start;
  final int end;
  final String type;
}
