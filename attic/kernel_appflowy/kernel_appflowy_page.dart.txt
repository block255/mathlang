// ============================================================
//  B 组 · appflowy_editor 6.2.0 + 自定义数学块（S1-A 对照实验）
//  主打：★问 1「块高度是否可测」（一票否决项）
//  附带：问 0「是否与一维缓冲区同构」· 问 3「能否注册渲染态数学块」· 问 5「工程代价」
//  判定矩阵见 notes/design/技术选型与风险.md 第 9.3 节
// ============================================================
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

const String kMathBlockType = 'math_block';

Node mathBlockNode(String tex) => Node(type: kMathBlockType, attributes: <String, Object>{'tex': tex});

// ---------------- 问 3：自定义"数学块"节点（渲染态，非文本） ----------------

class MathBlockComponentBuilder extends BlockComponentBuilder {
  MathBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) =>
      MathBlockWidget(
        key: blockComponentContext.node.key,
        node: blockComponentContext.node,
        configuration: configuration,
      );

  @override
  BlockComponentValidate get validate => (Node node) => node.type == kMathBlockType;
}

/// 注意：这里**刻意只做渲染**，没有实现 SelectableMixin 那一套选区内脏活
///（对比 `divider_block_component.dart`：一个"一条线"的块光选区内务就 222 行）。
/// 这正是问 3/问 6 要量化的"代价"。
class MathBlockWidget extends BlockComponentStatefulWidget {
  const MathBlockWidget({
    super.key,
    required super.node,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<MathBlockWidget> createState() => _MathBlockWidgetState();
}

class _MathBlockWidgetState extends State<MathBlockWidget> {
  @override
  Widget build(BuildContext context) {
    final String tex = (widget.node.attributes['tex'] as String?) ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Math.tex(
          tex,
          mathStyle: MathStyle.display,
          textStyle: const TextStyle(fontSize: 20),
          onErrorFallback: (e) => Text('❌ ${e.messageWithType}',
              style: const TextStyle(color: Colors.red, fontSize: 13)),
        ),
      ),
    );
  }
}

// ---------------- 实验页 ----------------

class KernelAppFlowyPage extends StatefulWidget {
  const KernelAppFlowyPage({super.key});

  @override
  State<KernelAppFlowyPage> createState() => _KernelAppFlowyPageState();
}

class _KernelAppFlowyPageState extends State<KernelAppFlowyPage> {
  late final EditorState _editorState;
  final List<String> _rows = <String>[];
  String _json = '';
  final List<String> _errors = <String>[];

  @override
  void initState() {
    super.initState();
    FlutterError.onError = (FlutterErrorDetails d) {
      final String m = d.exceptionAsString();
      if (!_errors.contains(m)) {
        _errors.insert(0, m);
        if (_errors.length > 3) _errors.removeLast();
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
      }
      FlutterError.presentError(d);
    };

    final Document document = Document(
      root: Node(
        type: 'page',
        children: <Node>[
          paragraphNode(text: '第一段：设 x²+1 为多项式（普通段落块，用标准 paragraph builder）。'),
          mathBlockNode(r'\frac{a}{b}=\sqrt{2}'),
          paragraphNode(text: '第二段：下面是一个含求和上限的行间公式。'),
          mathBlockNode(r'\sum_{k=1}^{n} k = \frac{n(n+1)}{2}'),
          paragraphNode(text: '第三段：结束。（共 5 个块，其中 2 个是自定义数学块）'),
        ],
      ),
    );
    _editorState = EditorState(document: document);
    _editorState.document.root.children.first;
  }

  @override
  void dispose() {
    _editorState.dispose();
    super.dispose();
  }

  void _measureBlocks() {
    final List<String> rows = <String>[];
    for (final Node n in _editorState.document.root.children) {
      final RenderObject? ro = n.key.currentContext?.findRenderObject();
      final String h = (ro is RenderBox && ro.hasSize)
          ? '✅ 高 ${ro.size.height.toStringAsFixed(1)} px（宽 ${ro.size.width.toStringAsFixed(0)}）'
          : '❌ 拿不到 RenderBox';
      rows.add('${n.type.padRight(12)} $h');
    }
    setState(() {
      _rows
        ..clear()
        ..addAll(rows);
      _json = _editorState.document.toJson().toString();
    });
  }

  Widget _panel() => Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(color: Color(0xFFF7FAFC), border: Border(top: BorderSide(color: Colors.black12))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _measureBlocks,
                  icon: const Icon(Icons.straighten, size: 18),
                  label: const Text('① 测每个块的高度（问 1）'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '问 1 判据：能否对**每个块**取到高度（`Node.key` 是 GlobalKey → `currentContext.findRenderObject()`）',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_rows.isEmpty)
              const Text('（点上面的按钮开始测量）', style: TextStyle(fontSize: 12, color: Colors.black45))
            else
              ...(_rows.map((String r) => Text(r,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace', height: 1.5)))),
            if (_errors.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              const Text('⚠️ 捕获到的异常：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ..._errors.map((String e) => Text(e, style: const TextStyle(fontSize: 11, color: Colors.red))),
            ],
            if (_json.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              const Text('问 0 证据：文档模型是"树 + Delta"，不是一维字符缓冲区：',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              SizedBox(
                height: 96,
                child: SingleChildScrollView(
                  child: SelectableText(_json, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                ),
              ),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('B 组 · appflowy_editor + 自定义数学块'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(24),
          child: Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('appflowy_editor 6.2.0 · 对照实验（重点是问 1 与问 0）', style: TextStyle(fontSize: 12)),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: AppFlowyEditor(
              editorState: _editorState,
              blockComponentBuilders: <String, BlockComponentBuilder>{
                ...standardBlockComponentBuilderMap,
                kMathBlockType: MathBlockComponentBuilder(),
              },
            ),
          ),
          _panel(),
        ],
      ),
    );
  }
}
