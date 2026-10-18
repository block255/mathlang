// 数语引擎 · **矩阵 / 行列式的尺寸面板**（PC-5，2026-10-18 用户定的形态）
//
// 用户的四条口径：
//   ① 面板**固定在页面中央**（不是跟着右键位置弹）；
//   ② 行列数**可以键入数字**（不是只能点 2–6 的按钮）；
//   ③ 括号：矩阵 `[ ]` / `( )`，行列式固定 `| |`；
//   ④ 键盘可用：`Enter` 应用、`Esc` 取消（可访问性那批要的）。
//
// 语义有两处调用方：
//   · 右键渲染页里的矩阵/行列式 ⇒ **改现有的**（带上当前行列，应用后就地重写）；
//   · 点符号面板里的「矩阵 / 行列式」格子 ⇒ **先定义再插入**（默认 2×2 / 记住上次）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../lang/env_resize.dart';

/// 面板返回的一次选择。
class EnvSizeChoice {
  const EnvSizeChoice({required this.rows, required this.cols, required this.style});

  final int rows;
  final int cols;
  final EnvStyle style;

  @override
  String toString() => 'EnvSizeChoice(${rows}x$cols, ${style.name})';
}

/// 打开尺寸面板；取消 ⇒ null。
Future<EnvSizeChoice?> showEnvSizeDialog(
  BuildContext context, {
  EnvStyle style = EnvStyle.bracket,
  int rows = 2,
  int cols = 2,
  /// 行列式：列数强制跟行数联动（输入框置灰）
  bool determinant = false,
  /// 记住上次的选择（面板格子那条路用）
  String title = '矩阵',
}) {
  return showDialog<EnvSizeChoice>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext c) => _EnvSizeDialog(
      style0: style,
      rows0: rows,
      cols0: cols,
      determinant: determinant,
      title: title,
    ),
  );
}

class _EnvSizeDialog extends StatefulWidget {
  const _EnvSizeDialog({
    required this.style0,
    required this.rows0,
    required this.cols0,
    required this.determinant,
    required this.title,
  });

  final EnvStyle style0;
  final int rows0;
  final int cols0;
  final bool determinant;
  final String title;

  @override
  State<_EnvSizeDialog> createState() => _EnvSizeDialogState();
}

class _EnvSizeDialogState extends State<_EnvSizeDialog> {
  late final TextEditingController _rows =
      TextEditingController(text: '${widget.rows0}');
  late final TextEditingController _cols =
      TextEditingController(text: '${widget.cols0}');
  late EnvStyle _style = widget.style0;
  String? _error;

  static const int kMin = 1;
  static const int kMax = 12;

  @override
  void dispose() {
    _rows.dispose();
    _cols.dispose();
    super.dispose();
  }

  int? _parse(TextEditingController c) {
    final int? v = int.tryParse(c.text.trim());
    if (v == null || v < kMin || v > kMax) return null;
    return v;
  }

  void _apply() {
    final int? r = _parse(_rows);
    final int c = widget.determinant ? (r ?? 0) : (_parse(_cols) ?? 0);
    if (r == null || c == 0) {
      setState(() => _error = '请输入 $kMin–$kMax 之间的整数');
      return;
    }
    Navigator.of(context).pop(EnvSizeChoice(rows: r, cols: c, style: _style));
  }

  @override
  Widget build(BuildContext context) {
    final int r = _parse(_rows) ?? widget.rows0;
    final int c = widget.determinant ? r : (_parse(_cols) ?? widget.cols0);
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): _ApplyIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): _ApplyIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ApplyIntent: CallbackAction<_ApplyIntent>(
            onInvoke: (_) {
              _apply();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: AlertDialog(
            key: const Key('env-size-dialog'),
            title: Text(widget.title, style: const TextStyle(fontSize: 17)),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (widget.determinant)
                    // ★★ 2026-10-18 晚（用户）：**行列式只给一栏「尺寸」**。
                    //   原来给"行数 / 列数"两栏、列数置灰 ⇒ 用户改了行数看不到列数跟着动
                    //   （虽然生成出来的确实是 n×n），一眼像是没生效。
                    //   方阵只有一个自由度 ⇒ 界面上也只该有一个框。
                    Row(
                      children: <Widget>[
                        const SizedBox(width: 56, child: Text('尺寸')),
                        SizedBox(
                          width: 72,
                          child: TextField(
                            key: const Key('env-size-rows'),
                            controller: _rows,
                            keyboardType: TextInputType.number,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (_) => setState(() => _error = null),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text('× $r（方阵）',
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF718096))),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: <Widget>[
                        const SizedBox(width: 56, child: Text('行数')),
                        SizedBox(
                          width: 72,
                          child: TextField(
                            key: const Key('env-size-rows'),
                            controller: _rows,
                            keyboardType: TextInputType.number,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (_) => setState(() => _error = null),
                          ),
                        ),
                        const SizedBox(width: 16),
                        const SizedBox(width: 56, child: Text('列数')),
                        SizedBox(
                          width: 72,
                          child: TextField(
                            key: const Key('env-size-cols'),
                            controller: _cols,
                            keyboardType: TextInputType.number,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (_) => setState(() => _error = null),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      const SizedBox(width: 56, child: Text('括号')),
                      if (widget.determinant)
                        const Text('| |', style: TextStyle(fontSize: 13))
                      else
                        SegmentedButton<EnvStyle>(
                          key: const Key('env-size-style'),
                          segments: const <ButtonSegment<EnvStyle>>[
                            ButtonSegment<EnvStyle>(
                                value: EnvStyle.bracket, label: Text('[ ]')),
                            ButtonSegment<EnvStyle>(
                                value: EnvStyle.paren, label: Text('( )')),
                          ],
                          selected: <EnvStyle>{_style},
                          onSelectionChanged: (Set<EnvStyle> s) =>
                              setState(() => _style = s.first),
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('预览：$r × $c',
                      key: const Key('env-size-preview'),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF4A5568))),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!,
                          style: const TextStyle(fontSize: 11, color: Color(0xFFC53030))),
                    ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                key: const Key('env-size-cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const Key('env-size-apply'),
                onPressed: _apply,
                child: const Text('应用'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApplyIntent extends Intent {
  const _ApplyIntent();
}
