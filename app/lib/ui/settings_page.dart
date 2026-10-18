// 数语引擎 · **设置页（半透明覆盖层）**（S4-b②，2026-10-17 用户定稿）
//
// 规格：《界面与布局.md》§6 / §6.2 / §6.4。用户原话：
//   「设置可以设置一个单独的**设置页面**，而不是这样一个按钮列表，这样不太好精细调整。」
//   「把设置页面做成**半透明**，让用户在改动时也能透过它看到编辑器页面如何」
//
// 所以本页**不是路由**（`Navigator.push` 会让编辑器状态与焦点换一套生命期）——它在同一
// `Scaffold` 里**叠一层**：
//   · 卡片**贴右**（页面默认偏左，正好露出来）、占 62% 宽、最大 860；
//   · 卡片 90% 白（不做毛玻璃：CanvasKit 上 `BackdropFilter` 是真花钱）；
//   · 按住 `👁` ⇒ 卡片淡到 10%（**peek**：看清背后那一段），松手弹回；
//   · 卡片外**完全透**，点一下 = 关闭，滚轮照样滚文档。
//
// ★ 与"缩略图预览"相比它**零维护、零失真**（看到的是真文档真重排），代价只是会挡住页面 ⇒ 靠 peek + 关闭解决。

import 'package:flutter/material.dart';

import '../core/doc_settings.dart';
import '../lang/shortcut_registry.dart';
import '../lang/symbol_library.dart';
import '../lang/word_triggers.dart';
import '../layout/page_metrics.dart';
import 'app_settings.dart';
import 'controls/num_field.dart';
import 'controls/segmented.dart';
import 'controls/setting_row.dart';
import 'controls/stepper_row.dart';
import 'shortcut_page.dart';

/// 设置页里的一级分组（顺序 = 用户 2026-10-17 定的九组）
class SettingGroup {
  const SettingGroup(this.title, this.icon, {this.live = true});
  final String title;
  final IconData icon;

  /// `false` ⇒ 本段还没接入（灰显 + 说明），**不假装能用**
  final bool live;
}

const List<SettingGroup> kSettingGroups = <SettingGroup>[
  SettingGroup('文档与排版', Icons.text_fields),
  SettingGroup('布局', Icons.dashboard_outlined),
  SettingGroup('面板', Icons.grid_view),
  SettingGroup('快捷栏', Icons.star_outline),
  SettingGroup('状态栏', Icons.view_headline),
  SettingGroup('快捷键', Icons.keyboard),
  SettingGroup('智能输入', Icons.auto_fix_high),
  SettingGroup('高级', Icons.build_outlined, live: false),
  SettingGroup('关于', Icons.info_outline),
];

class SettingsOverlay extends StatefulWidget {
  const SettingsOverlay({
    super.key,
    required this.settings,
    required this.doc,
    required this.onSettings,
    required this.onDoc,
    required this.onClose,
    this.library,
    this.initialGroup = 0,
    this.shortcuts,
    this.triggers,
    this.onShortcuts,
    this.onTriggers,
    this.pageSpace,
  });

  final AppSettings settings;
  final DocSettings doc;
  final ValueChanged<AppSettings> onSettings;
  final ValueChanged<DocSettings> onDoc;
  final VoidCallback onClose;
  final SymbolLibrary? library;

  /// ★★ 页面横向**可用宽度**（由外壳按真实布局算给设置页）。
  ///
  /// 用途：横条旁边那行"⇒ 可移动 N px"—— 用户 2026-10-18 报"拖了页面不动"，
  /// 根因是覆盖式下 dock 被写死成 0.5；修完之后还要让"**能动多少**"可见，
  /// 否则窗口真的没余量时，用户还是只能说"它不动"。
  final double? pageSpace;

  /// ★ 快捷键偏好（`lang/shortcut_registry.dart`）与词表（`lang/word_triggers.dart`）
  final ShortcutSettings? shortcuts;
  final TriggerSettings? triggers;
  final ValueChanged<ShortcutSettings>? onShortcuts;
  final ValueChanged<TriggerSettings>? onTriggers;

  /// 从"文件 ▾ → 设置"或"关于"进来时直接落到某一组
  final int initialGroup;

  @override
  State<SettingsOverlay> createState() => SettingsOverlayState();
}

class SettingsOverlayState extends State<SettingsOverlay> {
  late int _group = widget.initialGroup.clamp(0, kSettingGroups.length - 1);
  bool _peek = false;

  /// 页边距默认**联动**（原则 5：默认简化，想细调才解锁）
  late bool _marginLock = _marginsEqual;

  bool get _marginsEqual =>
      widget.doc.marginTopMm == widget.doc.marginBottomMm &&
      widget.doc.marginLeftMm == widget.doc.marginRightMm;

  @override
  void didUpdateWidget(SettingsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ★ 外壳用同一个 `initialGroup` 重新打开另一组时，State 是复用的
    //   （`late` 初始化只跑一次）⇒ 必须在这里跟一次，否则"从文件菜单进设置"会停在旧分组。
    if (widget.initialGroup != oldWidget.initialGroup) {
      _group = widget.initialGroup.clamp(0, kSettingGroups.length - 1);
    }
  }

  AppSettings get s => widget.settings;
  DocSettings get d => widget.doc;

  void setS(AppSettings v) => widget.onSettings(v);
  void setD(DocSettings v) => widget.onDoc(v);

  /// 测试/自动化用：切到第 n 组
  void showGroup(int i) => setState(() => _group = i);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (BuildContext c, BoxConstraints cons) {
      final double cardW =
          (cons.maxWidth * 0.62).clamp(320.0, 860.0).toDouble();
      final bool narrow = cardW < 640;
      return Stack(
        children: <Widget>[
          // 卡片外：几乎不遮（4% 黑）＋ 点一下关闭；**不拦滚轮**（还能滚文档看别处）
          Positioned.fill(
            child: GestureDetector(
              key: const Key('settings-scrim'),
              behavior: HitTestBehavior.translucent,
              onTap: widget.onClose,
              child: const ColoredBox(color: Color(0x0A000000)),
            ),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _peek ? 0.10 : 1,
              duration: const Duration(milliseconds: 90),
              child: Container(
                key: const Key('settings-card'),
                width: cardW,
                decoration: const BoxDecoration(
                  color: Color(0xE6FFFFFF), // 90% 白 —— 透过它看得见真文档
                  border: Border(left: BorderSide(color: Color(0xFFE2E8F0))),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 16,
                        offset: Offset(-2, 0)),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _header(),
                      const Divider(height: 1),
                      Expanded(
                        child: narrow
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  _navNarrow(),
                                  const Divider(height: 1),
                                  Expanded(child: _content()),
                                ],
                              )
                            : Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  SizedBox(width: 148, child: _navWide()),
                                  const VerticalDivider(width: 1),
                                  Expanded(child: _content()),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  // ---------------- 卡片头 ----------------

  Widget _header() {
    return SizedBox(
      height: 44,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 8),
          TextButton.icon(
            key: const Key('settings-back'),
            onPressed: widget.onClose,
            icon: const Icon(Icons.arrow_back, size: 15),
            label: const Text('返回编辑', style: TextStyle(fontSize: 12)),
          ),
          const Spacer(),
          _peekButton(),
          TextButton(
            key: const Key('settings-reset-all'),
            onPressed: () {
              setS(const AppSettings());
              setD(DocSettings.defaults);
              setState(() => _marginLock = true);
            },
            child: const Text('全部恢复默认', style: TextStyle(fontSize: 12)),
          ),
          IconButton(
            key: const Key('settings-close'),
            tooltip: '关闭（Esc）',
            icon: const Icon(Icons.close, size: 16),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  /// ★ 按住看：松开就弹回（比拖动快，"我要看清那一段"一按就有）
  Widget _peekButton() {
    return GestureDetector(
      key: const Key('settings-peek'),
      onTapDown: (_) => setState(() => _peek = true),
      onTapUp: (_) => setState(() => _peek = false),
      onTapCancel: () => setState(() => _peek = false),
      child: Tooltip(
        message: '按住看文档',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.visibility_outlined, size: 13),
              SizedBox(width: 4),
              Text('按住看', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- 分组导航 ----------------

  Widget _navWide() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: <Widget>[
        for (var i = 0; i < kSettingGroups.length; i++)
          InkWell(
            key: Key('settings-group-${kSettingGroups[i].title}'),
            onTap: () => setState(() => _group = i),
            child: Container(
              color: _group == i ? const Color(0xFFEBF4FF) : null,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: <Widget>[
                  Icon(kSettingGroups[i].icon,
                      size: 14,
                      color: kSettingGroups[i].live
                          ? (_group == i
                              ? const Color(0xFF1E88E5)
                              : const Color(0xFF4A5568))
                          : const Color(0xFFCBD5E0)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      kSettingGroups[i].title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _group == i
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: kSettingGroups[i].live
                            ? (_group == i
                                ? const Color(0xFF1E88E5)
                                : const Color(0xFF2D3748))
                            : const Color(0xFFA0AEC0),
                      ),
                    ),
                  ),
                  if (!kSettingGroups[i].live)
                    const Text('待接入',
                        style: TextStyle(
                            fontSize: 9, color: Color(0xFFCBD5E0))),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _navNarrow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < kSettingGroups.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: Key('settings-group-${kSettingGroups[i].title}'),
                label: Text(kSettingGroups[i].title,
                    style: const TextStyle(fontSize: 11)),
                selected: _group == i,
                onSelected: (_) => setState(() => _group = i),
              ),
            ),
        ],
      ),
    );
  }

  Widget _content() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: switch (_group) {
        0 => _docGroup(),
        1 => _layoutGroup(),
        2 => _panelGroup(),
        3 => _quickBarGroup(),
        4 => _statusGroup(),
        5 => <Widget>[_shortcutGroup()],
        6 => _triggerGroup(),
        7 => <Widget>[
            _pending('高级',
                '源码视图（S5）· 清空本地缓存（S4-e）。\n★ 诊断清单已经做好了：在**状态栏**点「自动包裹 N 处 · 查看清单 ›」。')
          ],
        _ => _aboutGroup(),
      },
    );
  }

  /// ⑤ 快捷键（★ **会说实话的表**：39 条里真正接上的 17 条带徽标）
  Widget _shortcutGroup() {
    final ShortcutSettings? sc = widget.shortcuts;
    if (sc == null) {
      return _pending('快捷键', '这一份设置没有接入快捷键状态（测试注入时可能出现）。');
    }
    return ShortcutSettingsView(
      settings: sc,
      onChanged: (ShortcutSettings v) => widget.onShortcuts?.call(v),
    );
  }

  /// ⑥ 智能输入：三个"打字即渲染"的开关 ＋ 词触发表（词是用户自己编的 ⇒ 可加行可删行）
  List<Widget> _triggerGroup() {
    final TriggerSettings? t = widget.triggers;
    final AppSettings s = widget.settings;
    void set(AppSettings v) => widget.onSettings(v);
    return <Widget>[
      const SettingSection(title: '自动展开（S4-c 已接入）'),
      SwitchRow(
        key: const Key('auto-slash'),
        title: '打字「/」就变成分式',
        subtitle: '光标前那个符号当分子，光标落进分母（Word 的 Autoformat 同款）。'
            '不想要就关掉 —— 关掉后「/」就是普通斜杠。',
        value: s.autoSlashFraction,
        modified: !s.autoSlashFraction,
        onChanged: (bool v) => set(s.copyWith(autoSlashFraction: v)),
      ),
      SwitchRow(
        key: const Key('auto-word'),
        title: '词触发（打字即模板）',
        subtitle: '打 sqrt 再按空格 / Tab ⇒ 变成根号模板（整词匹配，summer 不会触发）。',
        value: s.autoWordTriggers,
        modified: !s.autoWordTriggers,
        onChanged: (bool v) => set(s.copyWith(autoWordTriggers: v)),
      ),
      SwitchRow(
        key: const Key('auto-shorthand'),
        title: '符号缩写（>= <= != +- ->）',
        subtitle: '连着打两个字符 ⇒ 变成一个数学符号。',
        value: s.autoShorthand,
        modified: !s.autoShorthand,
        onChanged: (bool v) => set(s.copyWith(autoShorthand: v)),
      ),
      const SettingSection(title: '词表'),
      if (t == null)
        _pending('智能输入', '这一份设置没有接入词表状态（测试注入时可能出现）。')
      else
        WordTriggerView(
          settings: t,
          onChanged: (TriggerSettings v) => widget.onTriggers?.call(v),
        ),
    ];
  }

  Widget _pending(String title, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.schedule, size: 14, color: Color(0xFF718096)),
                const SizedBox(width: 6),
                Text('$title · 待接入',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            Text(text,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF4A5568), height: 1.5)),
          ],
        ),
      ),
    );
  }

  // ---------------- ①文档与排版 ----------------

  List<Widget> _docGroup() {
    final PageGeometry geo = PageGeometry.from(d);
    final String sizeNote =
        '正文宽 ${geo.contentWidth.toStringAsFixed(1)} px · 正文区 '
        '${d.contentWidthMm.toStringAsFixed(0)}×${d.contentHeightMm.toStringAsFixed(0)} mm';
    return <Widget>[
      const SettingSection(title: '页面'),
      SettingRow(
        title: '页边距',
        subtitle: '毫米。改它会改正文宽 ⇒ 会重新分页（文档级设置，允许）',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Checkbox(
                  key: const Key('margin-lock'),
                  value: _marginLock,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (bool? v) => setState(() => _marginLock = v ?? false),
                ),
                const Text('上下左右统一', style: TextStyle(fontSize: 11)),
                const Spacer(),
                Text(sizeNote,
                    key: const Key('doc-size-note'),
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF1E88E5))),
              ],
            ),
            NumRow(
              title: '上',
              value: d.marginTopMm,
              min: 0,
              max: 60,
              onChanged: (double v) => _setMargin(top: v),
            ),
            NumRow(
              title: '下',
              value: d.marginBottomMm,
              min: 0,
              max: 60,
              onChanged: (double v) => _setMargin(bottom: v),
            ),
            NumRow(
              title: '左',
              value: d.marginLeftMm,
              min: 0,
              max: 60,
              onChanged: (double v) => _setMargin(left: v),
            ),
            NumRow(
              title: '右',
              value: d.marginRightMm,
              min: 0,
              max: 60,
              onChanged: (double v) => _setMargin(right: v),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('margin-reset'),
                onPressed: () => setD(d.copyWith(
                  marginTopMm: DocSettings.defaults.marginTopMm,
                  marginBottomMm: DocSettings.defaults.marginBottomMm,
                  marginLeftMm: DocSettings.defaults.marginLeftMm,
                  marginRightMm: DocSettings.defaults.marginRightMm,
                )),
                child: const Text('恢复默认页边距', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
      ),
      const SettingSection(title: '排版'),
      NumField(
        title: '正文字号',
        subtitle: '正文与行内公式的基准大小',
        value: d.bodyFontSize,
        min: 8,
        max: 28,
        step: 0.5,
        decimals: 1,
        unit: 'px',
        presets: const <double>[14, 16, 18],
        modified: d.bodyFontSize != DocSettings.defaults.bodyFontSize,
        onReset: () => setD(d.copyWith(bodyFontSize: DocSettings.defaults.bodyFontSize)),
        onChanged: (double v) => setD(d.copyWith(bodyFontSize: v)),
      ),
      NumField(
        title: '行距',
        subtitle: '字号的倍数',
        value: d.lineHeight,
        min: 1.0,
        max: 3.0,
        step: 0.05,
        decimals: 2,
        unit: '×',
        presets: const <double>[1.5, 1.7, 2.0],
        modified: d.lineHeight != DocSettings.defaults.lineHeight,
        onReset: () => setD(d.copyWith(lineHeight: DocSettings.defaults.lineHeight)),
        onChanged: (double v) => setD(d.copyWith(lineHeight: v)),
      ),
      NumField(
        title: '行间公式字号',
        subtitle: '不设 = 跟随正文 × 1.25',
        value: d.effectiveDisplayFontSize,
        min: 8,
        max: 60,
        step: 0.5,
        decimals: 1,
        unit: 'px',
        presets: const <double>[18, 20, 24],
        modified: d.displayFontSize != null,
        onReset: () => setD(d.copyWith(clearDisplayFontSize: true)),
        onChanged: (double v) => setD(d.copyWith(displayFontSize: v)),
        note: d.displayFontSize == null
            ? '当前跟随正文（正文 ${d.bodyFontSize.toStringAsFixed(1)} × 1.25 = '
                '${d.effectiveDisplayFontSize.toStringAsFixed(1)}）'
            : '自定义 ${d.displayFontSize!.toStringAsFixed(1)} px',
      ),
      const SettingSection(title: '页眉'),
      SettingRow(
        title: '页眉文字',
        subtitle: '姓名 / 学号；留空则不预留页眉高度',
        child: Row(
          children: <Widget>[
            Expanded(
              child: _HeaderField(
                value: d.headerText,
                onChanged: (String v) => setD(d.copyWith(headerText: v)),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 62,
              child: NumText(
                fieldKey: const Key('header-fontsize'),
                value: d.headerFontSize,
                min: 6,
                max: 20,
                decimals: 1,
                onChanged: (double v) => setD(d.copyWith(headerFontSize: v)),
              ),
            ),
            const Text(' px', style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
          ],
        ),
      ),
    ];
  }

  /// 页边距：**锁着 ⇒ 四个一起动**（原则 5：默认联动）；解锁 ⇒ 只动那一个
  void _setMargin({double? top, double? bottom, double? left, double? right}) {
    if (_marginLock) {
      final double? all = top ?? bottom ?? left ?? right;
      if (all != null) {
        setD(d.copyWith(
          marginTopMm: all,
          marginBottomMm: all,
          marginLeftMm: all,
          marginRightMm: all,
        ));
        return;
      }
    }
    setD(d.copyWith(
      marginTopMm: top,
      marginBottomMm: bottom,
      marginLeftMm: left,
      marginRightMm: right,
    ));
  }

  // ---------------- ②布局 ----------------
  List<Widget> _layoutGroup() {
    final String mode =
        s.autoPanelMode ? 'auto' : (s.panelMode == PanelMode.sideBySide ? 'side' : 'overlay');
    return <Widget>[
      const SettingSection(title: '页面'),
      SettingRow(
        title: '页面位置',
        subtitle: '拖横条：页面在可用空间里的位置（只平移，不改正文宽 ⇒ 分页不变）',
        modified: s.pageXDock != 0,
        onReset: () => setS(s.copyWith(pageXDock: 0)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: 26,
              child: Slider(
                key: const Key('dock-slider'),
                value: s.pageXDock.clamp(0.0, 1.0),
                divisions: 20,
                onChanged: (double v) => setS(s.copyWith(pageXDock: v)),
              ),
            ),
            Row(
              children: <Widget>[
                Text('左缘 ${(s.pageXDock * 100).round()}%',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                const SizedBox(width: 10),
                // ★★ 诚实读数（2026-10-18）：**能动多少像素**。
                //   窗口真的没余量时这里会写"没有余量" —— 免得用户以为功能坏了。
                Flexible(
                  child: Text(
                    _dockSpanLabel(),
                    key: const Key('dock-span'),
                    style: TextStyle(
                      fontSize: 11,
                      color: _dockSpan() <= 0
                          ? const Color(0xFFDD6B20)
                          : const Color(0xFF38A169),
                    ),
                  ),
                ),
                const Spacer(),
                Segmented<double>(
                  keyPrefix: 'dock',
                  options: const <SegOption<double>>[
                    SegOption<double>(0, '贴左'),
                    SegOption<double>(0.5, '居中'),
                    SegOption<double>(1, '贴右'),
                  ],
                  selected: _nearestDock(),
                  onChanged: (double v) => setS(s.copyWith(pageXDock: v)),
                ),
              ],
            ),
          ],
        ),
      ),
      const SettingSection(title: '面板形态'),
      SettingRow(
        title: '并排 / 覆盖',
        subtitle: '「自动」= 窗口宽 ≥ ${LayoutMetrics.sideBySideThreshold.toStringAsFixed(0)} px 时并排',
        modified: mode != 'auto',
        onReset: () => setS(s.copyWith(autoPanelMode: true)),
        child: Segmented<String>(
          keyPrefix: 'mode',
          options: const <SegOption<String>>[
            SegOption<String>('auto', '自动'),
            SegOption<String>('side', '并排'),
            SegOption<String>('overlay', '覆盖'),
          ],
          selected: mode,
          onChanged: (String v) {
            if (v == 'auto') {
              setS(s.copyWith(autoPanelMode: true));
            } else {
              setS(s.copyWith(
                autoPanelMode: false,
                panelMode: v == 'side' ? PanelMode.sideBySide : PanelMode.overlay,
              ));
            }
          },
        ),
      ),
      SwitchRow(
        title: '手机整页适应宽度',
        subtitle: '只缩放绘制，不改排版 ⇒ 分页不变',
        value: s.fitWidthOnPhone,
        modified: !s.fitWidthOnPhone,
        onChanged: (bool v) => setS(s.copyWith(fitWidthOnPhone: v)),
      ),
    ];
  }

  double _nearestDock() {
    const List<double> stops = <double>[0, 0.5, 1];
    double best = stops.first;
    for (final double p in stops) {
      if ((p - s.pageXDock).abs() < (best - s.pageXDock).abs()) best = p;
    }
    return best;
  }

  /// 页面**横向能移动多少像素**（`pageSpace` 没给时返回 -1 = 未知）
  double _dockSpan() {
    final double? avail = widget.pageSpace;
    if (avail == null) return -1;
    return LayoutMetrics.pageSpan(
      availableWidth: avail,
      pageWidth: PageGeometry.from(widget.doc).pageWidth,
    );
  }

  /// 横条旁边的诚实读数（0 余量时必须说清楚，否则用户以为功能坏了）
  String _dockSpanLabel() {
    final double span = _dockSpan();
    if (span < 0) return '';
    if (span <= 0.5) return '⇒ 当前窗口没有余量（贴左）';
    return '⇒ 可移动 ${span.toStringAsFixed(0)} px';
  }

  // ---------------- ③面板 ----------------

  List<Widget> _panelGroup() {
    return <Widget>[
      const SettingSection(title: '网格'),
      StepperRow(
        title: '网格列数',
        subtitle: '面板一排几格（快捷栏默认读同一个值）',
        value: s.gridColumns,
        min: 4,
        max: 10,
        modified: s.gridColumns != LayoutMetrics.defaultGridColumns,
        onReset: () => setS(s.copyWith(gridColumns: LayoutMetrics.defaultGridColumns)),
        note: '⇒ 面板宽 ${LayoutMetrics.panelWidth(s.gridColumns, cell: s.cellSize).toStringAsFixed(0)} px',
        onChanged: (int v) => setS(s.copyWith(gridColumns: v)),
      ),
      NumField(
        title: '格子尺寸',
        subtitle: '越大越好点，但一排能放的字号越小',
        value: s.cellSize,
        min: 36,
        max: 64,
        step: 2,
        decimals: 0,
        unit: 'px',
        presets: const <double>[40, 44, 52],
        modified: s.cellSize != LayoutMetrics.cellSize,
        onReset: () => setS(s.copyWith(cellSize: LayoutMetrics.cellSize)),
        note: '⇒ 面板宽 ${LayoutMetrics.panelWidth(s.gridColumns, cell: s.cellSize).toStringAsFixed(0)} px',
        onChanged: (double v) => setS(s.copyWith(cellSize: v)),
      ),
      SwitchRow(
        title: '格子里显示中文名',
        subtitle: '关掉 ⇒ 预览更大（标签被截就是这个原因）',
        value: s.showCellLabels,
        modified: !s.showCellLabels,
        onChanged: (bool v) => setS(s.copyWith(showCellLabels: v)),
      ),
    ];
  }

  // ---------------- ④快捷栏 ----------------

  List<Widget> _quickBarGroup() {
    final SymbolLibrary? lib = widget.library;
    return <Widget>[
      const SettingSection(title: '快捷栏（= 收藏）'),
      Segmented<QuickBarPlacement>(
        keyPrefix: 'quick-placement',
        options: const <SegOption<QuickBarPlacement>>[
          SegOption<QuickBarPlacement>(QuickBarPlacement.abovePanel, '面板上方'),
          SegOption<QuickBarPlacement>(QuickBarPlacement.bottomBar, '底部横条'),
        ],
        selected: s.quickBarPlacement,
        onChanged: (QuickBarPlacement v) => setS(s.copyWith(quickBarPlacement: v)),
      ),
      StepperRow(
        title: '格数',
        subtitle: '不随面板筛选变化，永远是这几格',
        value: s.quickBarSlots,
        min: 4,
        max: 12,
        modified: s.quickBarSlots != LayoutMetrics.defaultGridColumns,
        onReset: () => setS(s.copyWith(quickBarSlots: LayoutMetrics.defaultGridColumns)),
        onChanged: (int v) => setS(s.copyWith(quickBarSlots: v)),
      ),
      const SettingSection(title: '每一格装什么'),
      for (var i = 0; i < s.quickBarSlots; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 46,
                child: Text('第 ${i + 1} 格',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF4A5568))),
              ),
              Expanded(
                child: Text(
                  _slotLabel(lib, i),
                  key: Key('quick-slot-label-$i'),
                  style: TextStyle(
                    fontSize: 12,
                    color: s.favoriteAt(i) == null
                        ? const Color(0xFFA0AEC0)
                        : const Color(0xFF2D3748),
                  ),
                ),
              ),
              if (s.favoriteAt(i) != null)
                InkWell(
                  key: Key('quick-slot-clear-$i'),
                  onTap: () => setS(s.withFavorite(i, null)),
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(Icons.close, size: 13, color: Color(0xFFA0AEC0)),
                  ),
                ),
            ],
          ),
        ),
      const SizedBox(height: 6),
      const Text('赋值的更快办法：在快捷栏里点一个空格 ⇒ 再点面板里任意符号（Esc 取消）',
          style: TextStyle(fontSize: 10, color: Color(0xFF718096))),
    ];
  }

  String _slotLabel(SymbolLibrary? lib, int i) {
    final String? id = s.favoriteAt(i);
    if (id == null) return '（空）';
    final SymbolItem? item = lib?.byId(id);
    return item == null ? id : '${item.label}   ${item.tex}';
  }

  // ---------------- ⑤状态栏 ----------------

  List<Widget> _statusGroup() {
    return <Widget>[
      SwitchRow(
        title: '显示状态栏',
        subtitle: '手机默认隐藏',
        value: s.showStatusBar,
        modified: !s.showStatusBar,
        onChanged: (bool v) => setS(s.copyWith(showStatusBar: v)),
        detail: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final StatusItem it in StatusItem.values)
              FilterChip(
                key: Key('status-item-${it.label}'),
                label: Text(it.label, style: const TextStyle(fontSize: 11)),
                selected: s.statusItems.contains(it),
                onSelected: (bool on) {
                  final Set<StatusItem> next = <StatusItem>{...s.statusItems};
                  if (on) {
                    next.add(it);
                  } else {
                    next.remove(it);
                  }
                  setS(s.copyWith(statusItems: next));
                },
              ),
          ],
        ),
      ),
    ];
  }

  // ---------------- ⑨关于 ----------------

  List<Widget> _aboutGroup() {
    return <Widget>[
      const SettingSection(title: '数语引擎（mathlang）'),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text('用户永远不需要看数学编码 —— 数学只以渲染态出现。',
            style: TextStyle(fontSize: 12, color: Color(0xFF2D3748))),
      ),
      const Text('阶段 S4-b②（界面与设置）· 平台 web / android · 自研内核 + flutter_math_fork',
          style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
    ];
  }
}

/// 页眉文字框：**自己持有 controller**（不能在 `build` 里 new，否则每次重建光标都跳到末尾）
class _HeaderField extends StatefulWidget {
  const _HeaderField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_HeaderField> createState() => _HeaderFieldState();
}

class _HeaderFieldState extends State<_HeaderField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_HeaderField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('header-text'),
      controller: _c,
      style: const TextStyle(fontSize: 12),
      onChanged: widget.onChanged,
      decoration: const InputDecoration(
        isDense: true,
        hintText: '例：张三 · 高一(3)班',
        border: OutlineInputBorder(),
      ),
    );
  }
}
