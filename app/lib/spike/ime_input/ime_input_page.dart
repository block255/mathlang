// ============================================================
//  数语引擎 · S3-1b「中文 IME 输入通道」实验页
//  依据：notes/design/位点与结构导航.md（S3-1b）
//
//  要回答三个问题：
//    Q1  中文（IME 组合）能不能到达 Flutter？
//    Q2  问 0 spike 现在用的 `Focus.onKeyEvent` + `e.character` 能不能拿到中文？
//        → 预期**不能**：IME 组合发生在 DOM/平台层，走的是**文本输入通道**，不是按键事件。
//    Q3  平台文本值（含 composing 组合区）怎么换算成**一维缓冲区的一次编辑**？
//        → 这是 S3-2「编辑面」的地基：隐藏的镜像输入框当"输入设备"，
//          真相仍在 `DocBuffer` 里，两侧用**一次替换**对齐。
//
//  ⚠️ 本页所有日志都用 `Text`（不用 SelectableText）—— 内容要能被自动化读回（全局经验）。
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../editor/platform_text_diff.dart';

class ImeInputPage extends StatefulWidget {
  const ImeInputPage({super.key});

  @override
  State<ImeInputPage> createState() => _ImeInputPageState();
}

class _ImeInputPageState extends State<ImeInputPage> {
  // ---------------- A 路：按键事件（问 0 现在的做法） ----------------

  final FocusNode _keyFocus = FocusNode(debugLabel: 'key-path');
  final List<String> _keyLog = <String>[];
  int _keySeen = 0; // 收到的 KeyDownEvent 次数
  int _keyWithChar = 0; // 其中 character 非空的次数
  int _keyNonAscii = 0; // 其中含非 ASCII（中文/全角）的次数

  // ---------------- B 路：平台文本输入（镜像输入框当输入设备） ----------------

  /// ★ 唯一事实来源（一维缓冲区）。镜像输入框只是"输入设备"，真相在这里。
  String _buf = r'设 $x^2+1$ 为多项式，$\frac{a}{b}$ 为常数。';
  final TextEditingController _mirror = TextEditingController();
  final FocusNode _mirrorFocus = FocusNode(debugLabel: 'mirror-path');
  final List<String> _mirrorLog = <String>[];
  int _mirrorEdits = 0;

  /// ★ IME 组合中间态（= 平台文本值的 `composing` 区间）。
  /// 单独提成一行显示 —— 它就是要看的东西，不该埋在日志里。
  String _composing = '（无）';
  bool _isComposing = false;

  @override
  void initState() {
    super.initState();
    _mirror.text = _buf;
    _mirror.addListener(_onMirrorChanged);
  }

  @override
  void dispose() {
    _mirror.removeListener(_onMirrorChanged);
    _mirror.dispose();
    _keyFocus.dispose();
    _mirrorFocus.dispose();
    super.dispose();
  }

  /// ★ 代理换算：镜像文本变了 → 相对**缓冲区**求一次编辑
  void _onMirrorChanged() {
    final TextEditingValue v = _mirror.value;
    final TextRange c = v.composing;
    final bool composing = c.isValid && !c.isCollapsed;
    final PlatformEdit? e = diffPlatformText(_buf, v.text);
    setState(() {
      _isComposing = composing;
      _composing = composing
          ? '⟪${v.text.substring(c.start, c.end)}⟫  @${c.start}..${c.end}'
          : '（无）';
      if (e == null) return;
      _mirrorEdits++;
      _buf = v.text;
      _push(
        _mirrorLog,
        '#$_mirrorEdits $e'
        '${composing ? "  ⟪组合中⟫" : ""}'
        '  光标 ${v.selection.baseOffset}',
      );
    });
  }

  void _push(List<String> log, String line) {
    log.insert(0, line);
    if (log.length > 12) log.removeLast();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final String? ch = e.character;
    final bool nonAscii =
        ch != null && ch.isNotEmpty && ch.codeUnitAt(0) > 0x7F;
    setState(() {
      _keySeen++;
      if (ch != null && ch.isNotEmpty) _keyWithChar++;
      if (nonAscii) _keyNonAscii++;
      _push(
        _keyLog,
        '${e.logicalKey.keyLabel.isEmpty ? e.logicalKey.debugName : e.logicalKey.keyLabel}'
        '  character=${ch == null ? "<null>" : "「$ch」"}',
      );
    });
    return KeyEventResult.ignored; // 不吞键，方便对照
  }

  void _reset() => setState(() {
        _keyLog.clear();
        _mirrorLog.clear();
        _keySeen = 0;
        _keyWithChar = 0;
        _keyNonAscii = 0;
        _mirrorEdits = 0;
      });

  // ---------------- UI ----------------

  Widget _card({required String title, required String sub, required Widget child}) =>
      Card(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      );

  Widget _log(List<String> lines) => Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFC),
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (lines.isEmpty)
              const Text('（还没有输入）', style: TextStyle(fontSize: 12, color: Colors.black38))
            else
              for (final String l in lines)
                Text(l,
                    style: const TextStyle(
                        fontSize: 12, fontFamily: 'monospace', height: 1.5)),
          ],
        ),
      );

  Widget _keyPath() => _card(
        title: 'A 路 · 按键事件（`Focus.onKeyEvent` + `e.character`）',
        sub: '问 0 spike 现在用的做法。点下面的方框取得焦点，然后打字——',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Focus(
              focusNode: _keyFocus,
              onKeyEvent: _onKey,
              child: GestureDetector(
                onTap: () => _keyFocus.requestFocus(),
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _keyFocus.hasFocus
                        ? const Color(0xFFE3F2FD)
                        : const Color(0xFFF5F5F5),
                    border: Border.all(
                        color: _keyFocus.hasFocus
                            ? const Color(0xFF1E88E5)
                            : Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _keyFocus.hasFocus ? 'A 路：已聚焦，请打字' : 'A 路：点这里取得焦点',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '按键 $_keySeen 次 · 带 character 的 $_keyWithChar 次 · **非 ASCII 的 $_keyNonAscii 次**',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            _log(_keyLog),
          ],
        ),
      );

  Widget _mirrorPath() => _card(
        title: 'B 路 · 平台文本输入（镜像输入框当"输入设备"）',
        sub: '真相仍在一维缓冲区里；镜像框只负责把平台（含 IME）的输入交给我们，'
            '两侧用**一次替换**对齐。在下面的框里打字即可。',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _mirror,
              focusNode: _mirrorFocus,
              maxLines: 2,
              style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: '在这里打字（含中文输入法）',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '组合态（IME 中间态）：$_composing',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _isComposing ? const Color(0xFFE65100) : Colors.black54,
              ),
            ),
            const SizedBox(height: 4),
            Text('缓冲区（唯一真相）$_mirrorEdits 次编辑：',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text('「$_buf」',
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
            const SizedBox(height: 6),
            _log(_mirrorLog),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bool ok = _mirrorEdits > 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('★ S3-1b · 中文 IME 输入通道实验'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(24),
          child: Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('Q1 中文能不能到 Flutter？ Q2 onKeyEvent 拿得到吗？ Q3 怎么换算成缓冲区编辑？',
                style: TextStyle(fontSize: 12)),
          ),
        ),
      ),
      body: ListView(
        children: <Widget>[
          Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            color: const Color(0xFFFFF8E1),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('怎么测', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                    '① 点下面 B 路的输入框 → 用**中文输入法**打几个字（先打拼音、再选字）\n'
                    '② 看「组合态」行：打拼音时是否变成 ⟪拼音串⟫（✅Q1 通过）\n'
                    '③ 再点 A 路方框打字 → 对照它拿不拿得到字符（Q2）',
                    style: TextStyle(fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    ok
                        ? '✅ B 路已收到 $_mirrorEdits 次平台编辑'
                        : '（还没收到平台编辑）',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                OutlinedButton(onPressed: _reset, child: const Text('清空日志')),
              ],
            ),
          ),
          _mirrorPath(), // ★ 要测的就是 B 路 → 放最上面（短窗口也一眼可见）
          _keyPath(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
