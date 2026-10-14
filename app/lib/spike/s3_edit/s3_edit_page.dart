// ============================================================
//  数语引擎 · S3-2「编辑面」演示页
//  依据：notes/design/位点与结构导航.md §11.6 / §11.7
//
//  能做什么：在 A4 分页视图里**真的打字**（含中文 IME）、光标可见、缓冲区实时更新。
//  还不能做：点屏幕定位（S3-2b）、结构内导航（S3-3）、结构感知删除（S3-4）。
// ============================================================
import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    '$_stats',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => _editKey.currentState?.focusInput(),
                  child: const Text('聚焦输入'),
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
    );
  }
}
