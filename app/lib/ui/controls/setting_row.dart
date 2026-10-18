// 数语引擎 · **设置行**（控件库 K0，S4-b②）
//
// 规格：《界面与布局.md》§6.2。设置页里**每一行**都长这个样子：
//
//   ┌ 正文字号 ●(改动标记) ─────────── ↺(单项恢复) ┐
//   │ 一句话说明（灰小字）                          │
//   │ [  控件本体（滑杆 / 分段 / 开关 / 数字框）  ]  │
//   └──────────────────────────────────────────────┘
//
// 三条原则（§6.2 P1/P3）：
//   ① **默认值常显 + 单项 ↺**：只在该项**被改过**时才亮出 ↺（不干扰），免得"改了不知道改了哪个"；
//   ② 说明文字永远在标题下面（不是 tooltip —— 手机上 hover 不存在）；
//   ③ 行内不画分割线，靠留白分组。

import 'package:flutter/material.dart';

/// 一行的**统一外壳**（标题 / 说明 / 控件 / 改动标记 / 单项恢复）
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.title,
    this.subtitle,
    this.child,
    this.modified = false,
    this.onReset,
    this.dense = false,
  });

  final String title;
  final String? subtitle;

  /// 控件本体；`null` ⇒ 只有标题（用于分组小标题）
  final Widget? child;

  /// 与默认值不同 ⇒ 标题旁亮 `●`、并显示 ↺
  final bool modified;
  final VoidCallback? onReset;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 4 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (modified) ...<Widget>[
                          const SizedBox(width: 5),
                          Container(
                            key: Key('modified-$title'),
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF1E88E5),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF718096)),
                        ),
                      ),
                  ],
                ),
              ),
              if (onReset != null && modified)
                Tooltip(
                  message: '恢复默认',
                  child: InkWell(
                    key: Key('reset-$title'),
                    onTap: onReset,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(Icons.restore,
                          size: 15, color: Color(0xFF1E88E5)),
                    ),
                  ),
                ),
            ],
          ),
          if (child != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: child!),
        ],
      ),
    );
  }
}

/// 二元开关（K1）—— ★ 开关旁必须能展开"那么细节是什么"（原则 2）
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.detail,
    this.modified = false,
    this.onReset,
  });

  final String title;
  final String? subtitle;

  /// 开关打开时才显示的细节行（例：状态栏显示项）
  final Widget? detail;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool modified;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      title: title,
      subtitle: subtitle,
      modified: modified,
      onReset: onReset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Switch(
                key: Key('switch-$title'),
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 8),
              Text(
                value ? '开' : '关',
                style: TextStyle(
                  fontSize: 11,
                  color: value
                      ? const Color(0xFF1E88E5)
                      : const Color(0xFFA0AEC0),
                ),
              ),
            ],
          ),
          if (value && detail != null) ...<Widget>[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: detail!,
            ),
          ],
        ],
      ),
    );
  }
}

/// 分组小标题（设置页里把条目再分堆用）
class SettingSection extends StatelessWidget {
  const SettingSection({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4A5568),
              letterSpacing: 0.4,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}
