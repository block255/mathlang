// 数语引擎 · **步进器**（控件库 K4，S4-b②）
//
// 小范围整数用它（网格列数 / 快捷栏格数）：
//   ★ 与老实现（"点一下 +2，8→10→12，回不去 7"）的区别是 **双向、可减、步进 1**。
//   ★ 右边那句 `note` 是"**联动量当场算给你看**"（例：⇒ 面板宽 418 px）——
//     原则 4「后果可见」，用户不用自己去心算。

import 'package:flutter/material.dart';

import 'setting_row.dart';

class StepperRow extends StatelessWidget {
  const StepperRow({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.unit = '',
    this.subtitle,
    this.note,
    this.modified = false,
    this.onReset,
    this.keyPrefix = 'stepper',
  });

  final String title;
  final String? subtitle;
  final int value;
  final int min;
  final int max;
  final int step;
  final String unit;
  final ValueChanged<int> onChanged;
  final String? note;
  final bool modified;
  final VoidCallback? onReset;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final bool canDec = value > min;
    final bool canInc = value < max;
    return SettingRow(
      title: title,
      subtitle: subtitle,
      modified: modified,
      onReset: onReset,
      child: Row(
        children: <Widget>[
          _btn(Icons.remove, canDec, Key('$keyPrefix-dec-$title'),
              () => onChanged((value - step).clamp(min, max))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '$value$unit',
              key: Key('$keyPrefix-value-$title'),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
            ),
          ),
          _btn(Icons.add, canInc, Key('$keyPrefix-inc-$title'),
              () => onChanged((value + step).clamp(min, max))),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                note!,
                key: Key('$keyPrefix-note-$title'),
                style:
                    const TextStyle(fontSize: 11, color: Color(0xFF1E88E5)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, bool on, Key key, VoidCallback tap) {
    return InkWell(
      key: key,
      onTap: on ? tap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          color: on ? Colors.white : const Color(0xFFF7FAFC),
        ),
        child: Icon(icon,
            size: 15,
            color: on ? const Color(0xFF2D3748) : const Color(0xFFCBD5E0)),
      ),
    );
  }
}
