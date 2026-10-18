// 数语引擎 · **数值控件**（控件库 K3 / K3c，S4-b②）
//
// 这是"控制上限"的主承重墙（《界面与布局》§6.2 原则 1）：
//   ★ 滑杆只是**粗调**；**永远**有一条路能直接键入精确值。
//
//   ┌ 正文字号 ●                        ↺ ┐
//   │ 决定正文与行内公式的基准大小           │
//   │ ├────────●───────────┤               │   ← 拖 = 粗调
//   │ 8                    28               │
//   │ [ 16.0 ] px   [14][16][18]            │   ← 键入 = 精确；预设 = 常用
//   └───────────────────────────────────────┘

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'setting_row.dart';

/// 数字文本格式：最多 [decimals] 位，去掉无意义的尾零（`16.0` → `16`，`1.70` → `1.7`）
String formatNum(double v, int decimals) {
  String s = v.toStringAsFixed(decimals);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}

/// 可键入的数字框（**精确入口**）。失焦时把文本归一化，回车/失焦提交。
class NumText extends StatefulWidget {
  const NumText({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.decimals = 0,
    this.width = 72,
    this.fieldKey,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int decimals;
  final double width;
  final Key? fieldKey;

  @override
  State<NumText> createState() => _NumTextState();
}

class _NumTextState extends State<NumText> {
  late final TextEditingController _c =
      TextEditingController(text: formatNum(widget.value, widget.decimals));
  final FocusNode _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(NumText old) {
    super.didUpdateWidget(old);
    // 外部改（拖滑杆 / ↺ 恢复）时同步文本；**正在输入时不动**，否则光标会跳
    if (widget.value != old.value && !_f.hasFocus) _sync();
  }

  @override
  void dispose() {
    _f.removeListener(_onFocus);
    _f.dispose();
    _c.dispose();
    super.dispose();
  }

  void _sync() =>
      _c.text = formatNum(widget.value, widget.decimals);

  void _onFocus() {
    if (!_f.hasFocus) {
      _commit();
      _sync();
    }
  }

  void _commit() {
    final double? v = double.tryParse(_c.text.trim());
    if (v == null) {
      _sync();
      return;
    }
    widget.onChanged(v.clamp(widget.min, widget.max));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        key: widget.fieldKey,
        controller: _c,
        focusNode: _f,
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 12),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        onSubmitted: (_) => _commit(),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          border: OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// K3：带滑杆的数值项（粗调 + 精确键入 + 预设 + 单项恢复）
class NumField extends StatelessWidget {
  const NumField({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.unit = 'px',
    this.decimals = 0,
    this.presets = const <double>[],
    this.subtitle,
    this.note,
    this.modified = false,
    this.onReset,
    this.keyPrefix = 'num',
  });

  final String title;
  final String? subtitle;
  final double value;
  final double min;
  final double max;
  final double step;
  final String unit;
  final int decimals;

  /// 常用值按钮（点一下就到位）
  final List<double> presets;
  final ValueChanged<double> onChanged;

  /// 控件下方的读数（例："⇒ 面板宽 418 px"）
  final String? note;
  final bool modified;
  final VoidCallback? onReset;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final int divisions =
        ((max - min) / step).round().clamp(1, 10000);
    return SettingRow(
      title: title,
      subtitle: subtitle,
      modified: modified,
      onReset: onReset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 28,
            child: Slider(
              key: Key('$keyPrefix-slider-$title'),
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: (double v) => onChanged(v),
            ),
          ),
          Row(
            children: <Widget>[
              NumText(
                fieldKey: Key('$keyPrefix-field-$title'),
                value: value,
                min: min,
                max: max,
                decimals: decimals,
                onChanged: onChanged,
              ),
              const SizedBox(width: 6),
              Text(unit,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF718096))),
              const Spacer(),
              for (final double p in presets)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: InkWell(
                    key: Key('$keyPrefix-preset-$title-${formatNum(p, decimals)}'),
                    onTap: () => onChanged(p),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        formatNum(p, decimals),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF4A5568)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                note!,
                key: Key('$keyPrefix-note-$title'),
                style: const TextStyle(fontSize: 11, color: Color(0xFF1E88E5)),
              ),
            ),
        ],
      ),
    );
  }
}

/// K3c：**紧凑数值行**（标题左、数字框右）—— 页边距这类要并排四个的用它
class NumRow extends StatelessWidget {
  const NumRow({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.unit = 'mm',
    this.decimals = 0,
    this.note,
    this.keyPrefix = 'numrow',
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final double step;
  final String unit;
  final int decimals;
  final ValueChanged<double> onChanged;
  final String? note;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 44,
            child: Text(title,
                style: const TextStyle(fontSize: 12, color: Color(0xFF4A5568))),
          ),
          NumText(
            fieldKey: Key('$keyPrefix-field-$title'),
            value: value,
            min: min,
            max: max,
            decimals: decimals,
            onChanged: onChanged,
            width: 62,
          ),
          const SizedBox(width: 4),
          Text(unit,
              style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
          if (note != null) ...<Widget>[
            const SizedBox(width: 8),
            Text(note!,
                style: const TextStyle(fontSize: 11, color: Color(0xFF1E88E5))),
          ],
        ],
      ),
    );
  }
}
