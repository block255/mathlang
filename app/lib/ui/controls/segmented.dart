// 数语引擎 · **分段选择**（控件库 K2，S4-b②）
//
// 2–4 个互斥取值、一眼能选完的东西用它（面板形态 / 快捷栏位置 / 每格显示）。
// ★ 超过 4 项或每项要带说明 ⇒ 用下拉（`PopupMenuButton`），不要拿它硬塞。

import 'package:flutter/material.dart';

class SegOption<T> {
  const SegOption(this.value, this.label, {this.enabled = true, this.hint});

  final T value;
  final String label;
  final bool enabled;

  /// 悬停/长按说明（可选）
  final String? hint;
}

class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.keyPrefix = 'seg',
  });

  final List<SegOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  /// 测试/自动化用的 key 前缀：`Key('seg-页面位置-居中')`
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final SegOption<T> o in options) _item(o),
      ],
    );
  }

  Widget _item(SegOption<T> o) {
    final bool on = o.value == selected;
    final Color fg = !o.enabled
        ? const Color(0xFFCBD5E0)
        : on
            ? Colors.white
            : const Color(0xFF2D3748);
    final Widget box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: on ? const Color(0xFF1E88E5) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: on ? const Color(0xFF1E88E5) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Text(o.label, style: TextStyle(fontSize: 12, color: fg)),
    );
    final Widget tap = InkWell(
      key: Key('$keyPrefix-${o.label}'),
      borderRadius: BorderRadius.circular(6),
      onTap: o.enabled ? () => onChanged(o.value) : null,
      child: box,
    );
    return o.hint == null
        ? tap
        : Tooltip(message: o.hint!, waitDuration: const Duration(milliseconds: 500), child: tap);
  }
}
