// 数语引擎 · **按键捕获**（控件库 K7，S4-b②）
//
// 用法：点一下框 → 变黄"请按键" → 按下组合键 → 自动填进去；`Esc` 取消。
// 只做三件事：读修饰键、读主键、把结果写成 `Ctrl+Alt+F` 这种**规范化字符串**
// （规范化的意义：冲突检测与持久化都只认字符串，见 `lang/shortcut_registry.dart`）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 把 Flutter 的键码翻译成规格里的写法（`Z` / `1` / `/` / `=` / `Enter` / `ArrowUp` …）
String keyNameOf(LogicalKeyboardKey k) {
  final Map<LogicalKeyboardKey, String> named = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.numpadEnter: 'Enter',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.escape: 'Esc',
    LogicalKeyboardKey.space: 'Space',
    LogicalKeyboardKey.backspace: 'Backspace',
    LogicalKeyboardKey.delete: 'Delete',
    LogicalKeyboardKey.arrowUp: 'ArrowUp',
    LogicalKeyboardKey.arrowDown: 'ArrowDown',
    LogicalKeyboardKey.arrowLeft: 'ArrowLeft',
    LogicalKeyboardKey.arrowRight: 'ArrowRight',
    LogicalKeyboardKey.home: 'Home',
    LogicalKeyboardKey.end: 'End',
    LogicalKeyboardKey.pageUp: 'PageUp',
    LogicalKeyboardKey.pageDown: 'PageDown',
    LogicalKeyboardKey.equal: '=',
    LogicalKeyboardKey.minus: '-',
    LogicalKeyboardKey.slash: '/',
    LogicalKeyboardKey.backslash: r'\',
    LogicalKeyboardKey.comma: ',',
    LogicalKeyboardKey.period: '.',
    LogicalKeyboardKey.semicolon: ';',
    LogicalKeyboardKey.quote: "'",
    LogicalKeyboardKey.bracketLeft: '[',
    LogicalKeyboardKey.bracketRight: ']',
    LogicalKeyboardKey.backquote: '`',
  };
  final String? hit = named[k];
  if (hit != null) return hit;
  final String label = k.keyLabel;
  if (label.isNotEmpty && label.length <= 2) return label.toUpperCase();
  // 兜底：`LogicalKeyboardKey.keyZ.debugName == 'KeyZ'` ⇒ 取末位当字母
  final String dbg = (k.debugName ?? '').replaceAll(' ', '');
  if (dbg.startsWith('Key') && dbg.length == 4) return dbg.substring(3);
  if (dbg.startsWith('Digit') && dbg.length == 6) return dbg.substring(5);
  return dbg.isEmpty ? '?' : dbg;
}

/// 一个"按键框"：显示当前组合，点击后进入捕获态
class KeyCaptureField extends StatefulWidget {
  const KeyCaptureField({
    super.key,
    required this.value,
    required this.onCapture,
    this.width = 104,
    this.fieldKey,
    this.enabled = true,
    this.hint = '未设置',
  });

  final String value;
  final ValueChanged<String> onCapture;
  final double width;
  final Key? fieldKey;
  final bool enabled;
  final String hint;

  @override
  State<KeyCaptureField> createState() => KeyCaptureFieldState();
}

class KeyCaptureFieldState extends State<KeyCaptureField> {
  final FocusNode _focus = FocusNode(debugLabel: 'key-capture');
  bool _capturing = false;

  bool get capturing => _capturing;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void begin() {
    if (!widget.enabled) return;
    setState(() => _capturing = true);
    _focus.requestFocus();
  }

  void cancel() {
    if (!mounted) return;
    setState(() => _capturing = false);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!_capturing) return KeyEventResult.ignored;
    if (e is! KeyDownEvent) return KeyEventResult.handled;
    final LogicalKeyboardKey k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      cancel();
      return KeyEventResult.handled;
    }
    final String name = keyNameOf(k);
    if (ShortcutComboNames.isModifier(name)) return KeyEventResult.handled;
    final HardwareKeyboard kb = HardwareKeyboard.instance;
    final String combo = <String>[
      if (kb.isControlPressed) 'Ctrl',
      if (kb.isAltPressed) 'Alt',
      if (kb.isShiftPressed) 'Shift',
      if (kb.isMetaPressed) 'Meta',
      name,
    ].join('+');
    setState(() => _capturing = false);
    widget.onCapture(combo);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final bool hot = _capturing;
    final String text = hot
        ? '请按键…'
        : (widget.value.isEmpty ? widget.hint : widget.value);
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: InkWell(
        key: widget.fieldKey,
        borderRadius: BorderRadius.circular(5),
        onTap: hot ? cancel : begin,
        child: Container(
          width: widget.width,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: hot
                ? const Color(0xFFFFF8E1)
                : (widget.enabled ? Colors.white : const Color(0xFFF7FAFC)),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: hot ? const Color(0xFFF6AD55) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              color: hot
                  ? const Color(0xFF8A6100)
                  : (widget.enabled
                      ? const Color(0xFF2D3748)
                      : const Color(0xFFCBD5E0)),
            ),
          ),
        ),
      ),
    );
  }
}

/// 只有名字转发（避免这个文件依赖 registry 的类型 —— registry 是纯 Dart，本文件是 Flutter）
class ShortcutComboNames {
  const ShortcutComboNames._();

  /// ★ 空格已被去掉（`Control Left` → `ControlLeft`）—— 两种写法都认
  static bool isModifier(String name) {
    final String n = name.replaceAll(' ', '');
    return n.startsWith('Control') ||
        n.startsWith('Shift') ||
        n.startsWith('Alt') ||
        n.startsWith('Meta');
  }
}
