// 数语引擎 · **快捷键设置表 / 词触发表**（S4-b②）
//
// 规格：《界面与布局》**§6.5** —— 用户拍板的边界：
//   · 全表 39 条默认绑定，**每条带"接入状态"**（`● 已接入` / `○ 未接入(批次)`）——这一页**不撒谎**；
//   · **"添加"= 给已有动作加一条副绑定**（每动作 ≤ 2 条），**不能凭空造新动作**；
//   · 默认项**删不得**，只能"停用"或"单条恢复默认"；
//   · **浏览器独占键拒收**（`Ctrl+Shift+R` 这类页面拦不住）；
//   · 词触发表是**另一种东西**：词是用户自己编的 ⇒ **可以加行、可以删行**。
//
// 2026-10-17 的实情：39 条里真正接上的 17 条（其余随 S4-c / S4-d / S5）。

import 'package:flutter/material.dart';

import '../lang/shortcut_registry.dart';
import '../lang/word_triggers.dart';
import 'controls/key_capture.dart';
import 'controls/setting_row.dart';

/// 分组顺序（= 规格里的类目顺序）
const List<String> kShortcutGroupOrder = <String>[
  '编辑类',
  '结构内',
  '数学类',
  '结构类',
  '面板',
];

// ============================================================================
// 快捷键表
// ============================================================================

class ShortcutSettingsView extends StatefulWidget {
  const ShortcutSettingsView({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final ShortcutSettings settings;
  final ValueChanged<ShortcutSettings> onChanged;

  @override
  State<ShortcutSettingsView> createState() => ShortcutSettingsViewState();
}

class ShortcutSettingsViewState extends State<ShortcutSettingsView> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  ShortcutSettings get s => widget.settings;
  void set(ShortcutSettings v) => widget.onChanged(v);

  String get _q => _query.text.trim().toLowerCase();

  List<ShortcutAction> _shown() {
    final String q = _q;
    return <ShortcutAction>[
      for (final ShortcutAction a in kShortcutActions)
        if (q.isEmpty ||
            a.name.toLowerCase().contains(q) ||
            a.combo.toLowerCase().contains(q) ||
            a.group.contains(q))
          a,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final Set<String> bad = s.conflicts();
    final List<ShortcutAction> shown = _shown();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _header(),
        if (bad.isNotEmpty) _conflictBanner(bad),
        for (final String g in kShortcutGroupOrder) ..._group(g, shown, bad),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('没有匹配的快捷键',
                key: Key('shortcut-empty'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
          ),
      ],
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const Key('shortcut-search'),
                controller: _query,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 16),
                  hintText: '搜索动作 / 组合键',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '已接入 ${ShortcutSettings.wiredCount} / 共 ${ShortcutSettings.total}',
              key: const Key('shortcut-count'),
              style: const TextStyle(fontSize: 10, color: Color(0xFF718096)),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            '○ 未接入的项现在改键也能存下来（接入那天自动生效）。'
            '「添加」= 给同一个动作加一条备用键，不能凭空造新动作。',
            style: TextStyle(fontSize: 10, color: Color(0xFF718096), height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _conflictBanner(Set<String> bad) {
    return Container(
      key: const Key('shortcut-conflict-banner'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFC8181)),
      ),
      child: Text(
        '有 ${bad.length} 条动作的键重复了：${bad.map((String id) => s.actionOf(id)?.name ?? id).join(' / ')}',
        style: const TextStyle(fontSize: 10, color: Color(0xFFC53030)),
      ),
    );
  }

  List<Widget> _group(String group, List<ShortcutAction> shown, Set<String> bad) {
    final List<ShortcutAction> rows =
        shown.where((ShortcutAction a) => a.group == group).toList();
    if (rows.isEmpty) return const <Widget>[];
    return <Widget>[
      SettingSection(title: group, trailing: Text('${rows.length} 条',
          style: const TextStyle(fontSize: 9, color: Color(0xFFA0AEC0)))),
      for (final ShortcutAction a in rows) _row(a, bad),
    ];
  }

  Widget _row(ShortcutAction a, Set<String> bad) {
    final bool off = s.isDisabled(a.id);
    final List<ShortcutCombo> combos = s.combosOf(a.id);
    final bool conflict = bad.contains(a.id);
    return Container(
      key: Key('shortcut-row-${a.id}'),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: conflict
          ? const BoxDecoration(
              border: Border(left: BorderSide(color: Color(0xFFFC8181), width: 2)))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            a.name,
                            style: TextStyle(
                              fontSize: 12,
                              color: off
                                  ? const Color(0xFFA0AEC0)
                                  : const Color(0xFF2D3748),
                              decoration: off ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        if (s.isModified(a.id) && !off) ...<Widget>[
                          const SizedBox(width: 4),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                                color: Color(0xFF1E88E5),
                                shape: BoxShape.circle),
                          ),
                        ],
                      ],
                    ),
                    if (a.note.isNotEmpty)
                      Text(a.note,
                          style: const TextStyle(
                              fontSize: 9, color: Color(0xFFA0AEC0))),
                  ],
                ),
              ),
              for (var i = 0; i < combos.length; i++) ...<Widget>[
                KeyCaptureField(
                  fieldKey: Key('shortcut-key-${a.id}-$i'),
                  value: combos[i].label,
                  enabled: !off,
                  width: 96,
                  onCapture: (String combo) {
                    final ShortcutCombo c = ShortcutCombo.parse(combo);
                    final String? why = s.rejectionOf(c, except: a.id);
                    if (why != null) {
                      _toast(why);
                      return;
                    }
                    set(s.withCombo(a.id, i, c));
                  },
                ),
                if (i > 0)
                  InkWell(
                    key: Key('shortcut-del-${a.id}-$i'),
                    onTap: () {
                      final ShortcutSettings? next = s.removeCombo(a.id, i);
                      if (next != null) set(next);
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(Icons.close, size: 12, color: Color(0xFFA0AEC0)),
                    ),
                  ),
                const SizedBox(width: 4),
              ],
              if (combos.length < kMaxBindingsPerAction)
                InkWell(
                  key: Key('shortcut-add-${a.id}'),
                  onTap: () {
                    final ShortcutSettings? next =
                        s.addCombo(a.id, ShortcutCombo.empty);
                    if (next == null) {
                      _toast('每个动作最多 $kMaxBindingsPerAction 条键');
                    } else {
                      set(next);
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(Icons.add, size: 13, color: Color(0xFF1E88E5)),
                  ),
                ),
              const SizedBox(width: 4),
              _badge(a, off),
              const SizedBox(width: 4),
              InkWell(
                key: Key('shortcut-enable-${a.id}'),
                onTap: () => set(s.toggleEnabled(a.id)),
                child: Tooltip(
                  message: off ? '已停用（点一下启用）' : '启用中（点一下停用）',
                  child: Icon(
                    off ? Icons.toggle_off_outlined : Icons.toggle_on_outlined,
                    size: 18,
                    color:
                        off ? const Color(0xFFCBD5E0) : const Color(0xFF38A169),
                  ),
                ),
              ),
              if (s.isModified(a.id))
                InkWell(
                  key: Key('shortcut-reset-${a.id}'),
                  onTap: () => set(s.resetOne(a.id)),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.restore, size: 13, color: Color(0xFF1E88E5)),
                  ),
                ),
            ],
          ),
          if (conflict) _conflictLine(a),
        ],
      ),
    );
  }

  Widget _conflictLine(ShortcutAction a) {
    final List<String> problems = <String>[];
    for (final ShortcutCombo c in s.combosOf(a.id)) {
      if (c.isEmpty) continue;
      if (kBrowserOwnedKeys.contains(c.label)) {
        problems.add('${c.label} 是浏览器独占键（页面拦不住）');
        continue;
      }
      final String? owner = s.ownerOf(c, except: a.id);
      if (owner != null) problems.add('${c.label} 已被「$owner」占用');
    }
    if (problems.isEmpty && s.combosOf(a.id).length > 1) {
      problems.add('两条键重复');
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '冲突：${problems.join('；')}',
        key: Key('shortcut-conflict-${a.id}'),
        style: const TextStyle(fontSize: 9, color: Color(0xFFC53030)),
      ),
    );
  }

  Widget _badge(ShortcutAction a, bool off) {
    if (off) {
      return const Text('已停用',
          style: TextStyle(fontSize: 9, color: Color(0xFFA0AEC0)));
    }
    return Row(
      key: Key('shortcut-status-${a.id}'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(a.wired ? Icons.circle : Icons.circle_outlined,
            size: 7,
            color: a.wired ? const Color(0xFF38A169) : const Color(0xFFCBD5E0)),
        const SizedBox(width: 3),
        Text(a.wired ? '已接入' : '未接入',
            style: TextStyle(
                fontSize: 9,
                color:
                    a.wired ? const Color(0xFF38A169) : const Color(0xFFA0AEC0))),
      ],
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 12)),
      duration: const Duration(seconds: 2),
    ));
  }
}

// ============================================================================
// 词触发表
// ============================================================================

class WordTriggerView extends StatelessWidget {
  const WordTriggerView({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final TriggerSettings settings;
  final ValueChanged<TriggerSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SettingSection(title: '词触发（在公式里打词 + 终止符 ⇒ 展开）'),
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text(
            '○ 还没接入输入链。现在可以先编词表，接入那天按这张表生效。',
            style: TextStyle(fontSize: 10, color: Color(0xFF718096)),
          ),
        ),
        for (var i = 0; i < settings.triggers.length; i++) _row(context, i),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            TextButton.icon(
              key: const Key('trigger-add'),
              onPressed: () => onChanged(settings.add()),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('新增词', style: TextStyle(fontSize: 11)),
            ),
            TextButton(
              key: const Key('trigger-reset'),
              onPressed: () => onChanged(TriggerSettings.defaults()),
              child: const Text('恢复默认词表', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _row(BuildContext context, int i) {
    final WordTrigger t = settings.triggers[i];
    final bool ok = settings.isValid(i);
    return Padding(
      key: Key('trigger-row-$i'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 74,
                child: _field(
                  key: Key('trigger-word-$i'),
                  value: t.word,
                  hint: '词',
                  onChanged: (String v) =>
                      onChanged(settings.withItem(i, t.copyWith(word: v))),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _field(
                  key: Key('trigger-tex-$i'),
                  value: t.tex,
                  hint: r'展开成（\sqrt{}）',
                  mono: true,
                  onChanged: (String v) =>
                      onChanged(settings.withItem(i, t.copyWith(tex: v))),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 92,
                child: _field(
                  key: Key('trigger-term-$i'),
                  value: t.terminators,
                  hint: '终止符',
                  onChanged: (String v) => onChanged(
                      settings.withItem(i, t.copyWith(terminators: v))),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                key: Key('trigger-enable-$i'),
                onTap: () => onChanged(
                    settings.withItem(i, t.copyWith(enabled: !t.enabled))),
                child: Icon(
                  t.enabled ? Icons.toggle_on_outlined : Icons.toggle_off_outlined,
                  size: 18,
                  color:
                      t.enabled ? const Color(0xFF38A169) : const Color(0xFFCBD5E0),
                ),
              ),
              InkWell(
                key: Key('trigger-del-$i'),
                onTap: () => onChanged(settings.removeAt(i)),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.delete_outline, size: 14, color: Color(0xFFA0AEC0)),
                ),
              ),
            ],
          ),
          if (!ok)
            Padding(
              padding: const EdgeInsets.only(left: 78, top: 2),
              child: Text(
                t.word.trim().isEmpty
                    ? '词不能为空'
                    : (t.tex.trim().isEmpty ? '展开成不能为空' : '有两个同名词'),
                key: Key('trigger-invalid-$i'),
                style: const TextStyle(fontSize: 9, color: Color(0xFFC53030)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field({
    required Key key,
    required String value,
    required String hint,
    required ValueChanged<String> onChanged,
    bool mono = false,
  }) {
    return _InlineField(
      fieldKey: key,
      value: value,
      hint: hint,
      mono: mono,
      onChanged: onChanged,
    );
  }
}

/// 行内小输入框（自己持 controller：不能在 build 里 new，否则每次重建光标跳末尾）
class _InlineField extends StatefulWidget {
  const _InlineField({
    required this.fieldKey,
    required this.value,
    required this.hint,
    required this.onChanged,
    this.mono = false,
  });

  final Key fieldKey;
  final String value;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool mono;

  @override
  State<_InlineField> createState() => _InlineFieldState();
}

class _InlineFieldState extends State<_InlineField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final FocusNode _f = FocusNode();

  @override
  void didUpdateWidget(_InlineField old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _f.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: TextField(
        key: widget.fieldKey,
        controller: _c,
        focusNode: _f,
        onChanged: widget.onChanged,
        style: TextStyle(
          fontSize: 11,
          fontFamily: widget.mono ? 'monospace' : null,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hint,
          hintStyle: const TextStyle(fontSize: 10, color: Color(0xFFCBD5E0)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
