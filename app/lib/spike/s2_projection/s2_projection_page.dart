// ============================================================
//  数语引擎 · S2-2 行内投影验证页
//
//  要回答的问题（★ = S2 的待验证项）：
//    ★ ① 段落内「自动折行 + $...$ 不被拆开」能否由 Text.rich + WidgetSpan 免费得到？
//    ② baseline / middle 两种对齐在【折行后的每一行】上分别落在哪儿？（Δ上 / Δ下，相对行盒）
//    ③ 高结构（分式 / 求和 / 根号）参与折行时，行高会被撑到多少？
//    ④ 超长公式（比 A4 内容区还宽）会怎样？（S5 折行的输入数据）
//
//  取数办法（RenderParagraph 只有这些公开 API）：
//    · 行盒：逐字符探针 getOffsetForCaret 扫出每一行的 top，换行处 top 会跳
//      行高 = getFullHeightForCaret(该行首字符)
//    · 公式盒：InlineMathText 的 mathKeys → RenderBox，用 localToGlobal 换算到段内坐标
//
//  ★ 踩坑记录（2026-10-14）：
//    超长公式会让引擎的 RenderLine 报 "overflowed by N pixels"，这个异常在 **paint 期**抛出；
//    而错误钩子里若同步 setState 就会再触发 "Build scheduled during frame"，
//    **帧管线被打断之后，这一页上所有点击都会失效**（表现为按钮点不动）。
//    两条修法：① 超长公式样本单独放进"足够宽的容器"里渲染；② 错误钩子只在帧末刷新。
// ============================================================
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/doc_settings.dart';
import '../../render/inline_math_text.dart';

/// mm → 逻辑 px（Web/CSS 约定：1 inch = 96 px）
const double kPxPerMm = 96 / 25.4;

/// 超长公式样本需要的容器宽度（比它自身宽度大就行，否则引擎会报溢出）
const double kWideProbeWidth = 1200;

class _Sample {
  const _Sample(this.id, this.title, this.source, {this.wide = false});

  final String id;
  final String title;
  final String source;

  /// true = 放进"加宽容器"里渲染（只为不触发引擎溢出），超宽判定仍按 A4 内容区宽算
  final bool wide;
}

const List<_Sample> _samples = <_Sample>[
  _Sample(
    's1',
    '① 长段落 · 含 3 个行内公式（应当折行）',
    r'设 $x^2+1$ 为多项式，又已知 $\frac{a}{b}=\sqrt{2}$ 为常数，'
    r'且有 $a_{i,j}+b^2$ 成立，求 $x$ 的取值范围与最小值。',
  ),
  _Sample(
    's2',
    '② 高结构参与折行 · 求和 / 分式 / 根号 / 积分',
    r'由 $\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$ 可得，代入 $\sqrt{x^2+y^2}$ '
    r'与 $\int_{0}^{\infty} e^{-t^2}\,dt$ 之后，结论依然成立，且对一切 $n \ge 1$ 都适用。',
  ),
  _Sample(
    's3',
    '③ 超长单公式 · 比 A4 内容区还宽（S5 的输入：需要折行策略）',
    r'$(a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p)^2 = a^2+b^2+c^2+d^2+e^2+f^2+g^2+h^2+i^2$',
    wide: true,
  ),
  _Sample(
    's4',
    '④ 纯文字对照 · 同一宽度下的折行基线',
    '这一段故意不放任何公式，用来做同一宽度下折行行数的对照基线，'
    '方便判断公式有没有影响折行位置与行高。再补一句把它撑到三行左右，'
    '这样对照才有意义，不至于只有一行。',
  ),
];

class S2ProjectionPage extends StatefulWidget {
  const S2ProjectionPage({super.key});

  @override
  State<S2ProjectionPage> createState() => _S2ProjectionPageState();
}

class _S2ProjectionPageState extends State<S2ProjectionPage> {
  final DocSettings _s = DocSettings.defaults;
  final Map<String, GlobalKey> _paraKeys = <String, GlobalKey>{};
  final Map<String, Map<int, GlobalKey>> _mathKeys =
      <String, Map<int, GlobalKey>>{};
  final List<String> _errors = <String>[];
  String _report = '（正在测量…）';
  String _tapInfo = '（还没点过公式）';

  void Function(FlutterErrorDetails)? _prevOnError;
  bool _flushScheduled = false;

  double get _contentWidth => _s.contentWidthMm * kPxPerMm;
  double get _pageWidth => _s.pageWidthMm * kPxPerMm;

  @override
  void initState() {
    super.initState();
    // 浏览器控制台只给截断信息 → 把异常全文抓回界面（S1 的老办法，长期保留）
    // 注意：**不能在钩子里同步 setState** —— 异常可能发生在 paint 期，
    // 同步 setState 会再抛 "Build scheduled during frame"，把帧管线打断（点击全失效）。
    _prevOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails d) {
      _errors.add(d.exceptionAsString());
      _scheduleFlush();
      _prevOnError?.call(d);
    };
    // 进页面自动测一次，省得每次手点
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    FlutterError.onError = _prevOnError;
    super.dispose();
  }

  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      if (mounted) setState(() {});
    });
  }

  // ---------------- 测量 ----------------

  void _measure() {
    final sb = StringBuffer();
    sb.writeln('内容区宽 = ${_contentWidth.toStringAsFixed(1)} px'
        '（= ${_s.contentWidthMm} mm；页宽 ${_s.pageWidthMm} mm）\n');

    var mathTotal = 0;
    var overflowTotal = 0;
    var maxLineHeight = 0.0;

    for (final s in _samples) {
      sb.writeln('— ${s.title} —');
      for (final mode in MathAlignMode.values) {
        final id = '${s.id}/${mode.name}';
        final ro = _paraKeys[id]?.currentContext?.findRenderObject();
        if (ro is! RenderParagraph) {
          sb.writeln('  [${mode.name}] 拿不到 RenderParagraph');
          continue;
        }

        // ---- 行盒：用 getBoxesForSelection + 行距样式拿"行级"矩形。
        //      不能用 getOffsetForCaret 推：它随字符/占位符抖动（同一行内 dy 都会变），
        //      实测纯文字样本会被数成 4 行（真值 3 行）。
        final plain = ro.text.toPlainText();
        final List<ui.TextBox> boxes = ro.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: plain.length),
          boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
        );
        final lineMap = <int, (double, double)>{};
        for (final ui.TextBox b in boxes) {
          final int key = b.top.round();
          final (double, double)? cur = lineMap[key];
          lineMap[key] = cur == null
              ? (b.top, b.bottom)
              : (
                  cur.$1 < b.top ? cur.$1 : b.top,
                  cur.$2 > b.bottom ? cur.$2 : b.bottom,
                );
        }
        final keys = lineMap.keys.toList()..sort();
        final bands = <(double, double)>[for (final k in keys) lineMap[k]!];
        for (final b in bands) {
          final h = b.$2 - b.$1;
          if (h > maxLineHeight) maxLineHeight = h;
        }

        // ---- 每个公式盒相对它所在行盒的位置 ----
        final mk = _mathKeys[id] ?? const <int, GlobalKey>{};
        var overflow = 0;
        final det = <String>[];
        for (final e in mk.entries) {
          final mro = e.value.currentContext?.findRenderObject();
          if (mro is! RenderBox) {
            det.add('@${e.key}:无盒');
            continue;
          }
          final Rect r = mro.localToGlobal(Offset.zero, ancestor: ro) & mro.size;
          final double cy = r.center.dy;
          var lineIdx = -1;
          for (var i = 0; i < bands.length; i++) {
            if (cy >= bands[i].$1 && cy <= bands[i].$2) {
              lineIdx = i;
              break;
            }
          }
          final bool wide = r.width > _contentWidth + 0.5;
          if (wide) overflow++;
          final String wideTag = wide ? '⚠超A4宽' : '';
          if (lineIdx >= 0) {
            final double dTop = r.top - bands[lineIdx].$1;
            final double dBot = bands[lineIdx].$2 - r.bottom;
            det.add('L$lineIdx w=${r.width.toStringAsFixed(0)}$wideTag'
                ' Δ上=${dTop.toStringAsFixed(1)} Δ下=${dBot.toStringAsFixed(1)}');
          } else {
            det.add('w=${r.width.toStringAsFixed(0)}$wideTag（不在任何行盒内）');
          }
        }
        mathTotal += mk.length;
        overflowTotal += overflow;

        final String heights =
            bands.map((b) => (b.$2 - b.$1).toStringAsFixed(1)).join('/');
        sb.writeln('  [${mode.name}] 行数=${bands.length}'
            ' 段高=${ro.size.height.toStringAsFixed(1)}'
            ' 段宽=${ro.size.width.toStringAsFixed(1)}'
            ' 公式=${mk.length} 超A4宽=$overflow');
        sb.writeln('      各行行高 = $heights');
        for (var i = 0; i < det.length; i++) {
          sb.writeln('      #$i ${det[i]}');
        }
      }
      sb.writeln('');
    }

    sb.writeln('★ 汇总：共 $mathTotal 个行内公式；超 A4 宽的公式 $overflowTotal 个；'
        '最大行高 ${maxLineHeight.toStringAsFixed(1)} px。');
    setState(() => _report = sb.toString());
  }

  // ---------------- UI ----------------

  Widget _sampleCard(_Sample s, MathAlignMode mode) {
    final id = '${s.id}/${mode.name}';
    final pk = _paraKeys.putIfAbsent(id, () => GlobalKey());
    final mk = _mathKeys.putIfAbsent(id, () => <int, GlobalKey>{});
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${s.title}   ·   align = ${mode.name}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: s.wide ? kWideProbeWidth : _contentWidth,
            child: InlineMathText(
              key: pk,
              source: s.source,
              mathKeys: mk,
              align: mode,
              mathFontSize: _s.bodyFontSize,
              textStyle: TextStyle(
                fontSize: _s.bodyFontSize,
                height: _s.lineHeight,
                color: Colors.black87,
              ),
              onMathTap: (seg, renderTex, pos, _) => setState(() {
                _tapInfo = '点中「${seg.tex}」· 段内起点 ${seg.start} · 全局 '
                    '(${pos.dx.toStringAsFixed(0)}, ${pos.dy.toStringAsFixed(0)})'
                    '${renderTex == seg.tex ? '' : ' · 渲染 tex 与源码不同（有注入）'}';
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageSheet() => Container(
        width: _pageWidth,
        padding: EdgeInsets.symmetric(
          horizontal: _s.marginLeftMm * kPxPerMm,
          vertical: 18,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F4F7),
          boxShadow: <BoxShadow>[
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.08), blurRadius: 8),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final s in _samples)
              if (!s.wide) ...<Widget>[
                _sampleCard(s, MathAlignMode.baseline),
                _sampleCard(s, MathAlignMode.middle),
              ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('数语引擎 · S2-2 行内投影')),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '每个样本都用 A4 内容区宽度（174mm）渲染两次：baseline 与 middle 对照。\n'
                  '判据看数，不看"看起来对"。',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _measure,
                      icon: const Icon(Icons.straighten, size: 18),
                      label: const Text('重新测量'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('点击测试：$_tapInfo',
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _report,
                  style: const TextStyle(
                      fontSize: 11, fontFamily: 'monospace', height: 1.45),
                ),
                const SizedBox(height: 12),
                const Divider(),
                _pageSheet(),
                const SizedBox(height: 16),
                const Text('— 加宽容器（只为不让引擎报溢出；超宽判定仍按 A4 内容区宽）—',
                    style: TextStyle(fontSize: 11, color: Colors.black45)),
                const SizedBox(height: 6),
                for (final s in _samples)
                  if (s.wide) ...<Widget>[
                    _sampleCard(s, MathAlignMode.baseline),
                    _sampleCard(s, MathAlignMode.middle),
                  ],
                if (_errors.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  const Text('⚠️ 捕获到的异常（全文）：',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  for (final e in _errors)
                    Text(e,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
      );
}
