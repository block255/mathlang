// ============================================================
//  数语引擎 · S3-2「编辑面」演示页
//  依据：notes/design/位点与结构导航.md §11.6 / §11.7
//
//  能做什么：在 A4 分页视图里**真的打字**（含中文 IME）、光标可见、缓冲区实时更新。
//  还不能做：点屏幕定位（S3-2b）、结构内导航（S3-3）、结构感知删除（S3-4）。
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/doc_buffer.dart';
import '../../core/doc_settings.dart';
import '../../editor/edit_view.dart';

/// 样本：段落 + 标题 + 行内公式 + 行间公式 + 列表（正好覆盖各类单元）
const String kEditSample = r'''# 例 1 · 一元二次方程

设 $x^2+1$ 为多项式，$\frac{a}{b}=\sqrt{2}$ 为常数，求 $x$ 的值。

$$
x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}
$$

- 判别式 $\Delta = b^2-4ac$
- 两根之和 $x_1+x_2 = -\frac{b}{a}$
- 两根之积 $x_1 x_2 = \frac{c}{a}$
''';

class S3EditPage extends StatefulWidget {
  const S3EditPage({super.key});

  @override
  State<S3EditPage> createState() => _S3EditPageState();
}

class _S3EditPageState extends State<S3EditPage> {
  /// 光标一开始停在**文末** —— 点页面就能直接打字（不用先解决点屏幕定位）
  static DocBuffer _newBuf() {
    final DocBuffer b = DocBuffer(kEditSample);
    b.setCaret(b.length);
    return b;
  }

  late DocBuffer _buf = _newBuf();
  final GlobalKey<EditViewState> _editKey = GlobalKey<EditViewState>();
  EditViewStats _stats = const EditViewStats(
    length: 0,
    caret: 0,
    edits: 0,
    composing: false,
    composingText: '',
  );

  void _reload() {
    setState(() {
      _buf = _newBuf();
      _stats = const EditViewStats(
        length: 0,
        caret: 0,
        edits: 0,
        composing: false,
        composingText: '',
      );
    });
  }

  String get _probeTitle => 'S3|len=${_stats.length}|caret=${_stats.caret}'
      '|edits=${_stats.edits}|comp=${_stats.composingText}$_benchText';

  // ---------------- 性能基准（★ 跨平台同一把尺子） ----------------
  //
  // 为什么要有它：debug web（DDC/JS）与 release web（dart2js -O4）、Android（AOT）
  // 跑的是**同一段 Dart 代码的三种执行方式**，手感差异主要来自这里。
  // 用同一段基准在同一份文档上跑，数字才可比。
  //
  // ★ 两个数字必须分开报，否则会自欺：
  //   · **wall（端到端）**：插入 1 个字符 → 等 2 帧画完。它含 **vsync 等待**（60Hz 下 2 帧≈33ms），
  //     所以它更像"用户感知的延迟"，**但不代表代码有多重**。
  //   · **build / raster（帧工作量）**：来自 `FrameTiming`，**不含等待** → 这才是能跨平台比的量。

  static const int _kBenchChars = 20;
  final List<double> _benchWall = <double>[];
  final List<double> _benchBuild = <double>[];
  final List<double> _benchRaster = <double>[];
  bool _benchRunning = false;
  bool _collectTimings = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!_collectTimings) return;
    for (final FrameTiming t in timings) {
      _benchBuild.add(t.buildDuration.inMicroseconds / 1000.0);
      _benchRaster.add(t.rasterDuration.inMicroseconds / 1000.0);
    }
  }

  Future<void> _runBench() async {
    if (_benchRunning) return;
    setState(() {
      _benchRunning = true;
      _benchWall.clear();
      _benchBuild.clear();
      _benchRaster.clear();
    });
    _buf.setCaret(_buf.length);
    _collectTimings = true;
    for (var i = 0; i < _kBenchChars; i++) {
      final Stopwatch sw = Stopwatch()..start();
      _buf.insertText('字');
      // ★ 固定节拍，**不用 `endOfFrame`**：浏览器页面被隐藏时 Flutter Web 会停止出帧，
      //   那时 `endOfFrame` 永远不返回（实测：`visibilityState=hidden` → 基准挂死在 2 次上）。
      //   固定节拍也让"每键一帧"这件事显式可控。
      await Future<void>.delayed(const Duration(milliseconds: 80));
      _benchWall.add(sw.elapsedMicroseconds / 1000.0);
    }
    _collectTimings = false;
    setState(() => _benchRunning = false);
  }

  static String _stats3(List<double> xs, String name) {
    if (xs.isEmpty) return '|$name=n/a';
    final List<double> s = List<double>.of(xs)..sort();
    double at(double q) => s[(q * (s.length - 1)).round()];
    return '|$name.50=${at(0.5).toStringAsFixed(1)}'
        '|$name.95=${at(0.95).toStringAsFixed(1)}';
  }

  /// 同时报**采到的帧数**：帧数明显不对就说明这次测量不可信（比给个假数字好）。
  String get _benchText {
    if (_benchWall.isEmpty && _benchBuild.isEmpty) return '|bench=-';
    return '|bench_n=${_benchWall.length}|frames=${_benchBuild.length}'
        '${_stats3(_benchBuild, 'build')}'
        '${_stats3(_benchRaster, 'raster')}';
  }

  @override
  Widget build(BuildContext context) {
    // ★ 探针：`Title` 在 Web 上会直接写 `document.title`
    //   （引擎 `platform_dispatcher.dart`：`case 'SystemChrome.setApplicationSwitcherDescription' → domDocument.title = label`）
    //   CanvasKit 下文字不进 DOM，这是**唯一零成本、100% 精确**的读数通道 ——
    //   一条 `browser_dock_evaluate` 就能拿回缓冲区长度/光标/编辑次数，不用截图 OCR、也不用来回开语义树。
    return Title(
      title: _probeTitle,
      color: const Color(0xFF1E88E5),
      child: Scaffold(
      appBar: AppBar(
        title: const Text('★ S3-2 · 编辑面（能打字了）'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(22),
          child: Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('点页面任意处 → 直接打字（中文也可以）；Enter = 新块',
                style: TextStyle(fontSize: 12)),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            color: const Color(0xFFF7FAFC),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '$_stats$_benchText',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => _editKey.currentState?.focusInput(),
                  child: const Text('聚焦输入'),
                ),
                const SizedBox(width: 8),
                // ★ 跨平台基准：同一段代码在 debug web / release web / Android 上各跑一次即可对比
                OutlinedButton(
                  onPressed: _benchRunning ? null : _runBench,
                  child: Text(_benchRunning ? '测试中…' : '基准(20字)'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _reload, child: const Text('重载样本')),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: EditView(
                key: _editKey,
                buffer: _buf,
                settings: DocSettings.defaults,
                onStats: (EditViewStats s) {
                  // 帧内回调 → 下一帧再 setState，避免打断当前帧
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _stats = s);
                  });
                },
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
