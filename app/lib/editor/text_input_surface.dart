// 数语引擎 · 文本输入面（S3-2 输入层重做，2026-10-14）
//
// ============================ 为什么推翻「透明镜像框」 ============================
// 旧做法：一个透明 `TextField` 装着**整个缓冲区**（含 `$...$` 与 LaTeX）当输入设备。
// 2026-10-14 实测判定：**这条路不可能对齐**。
//   Web 引擎把「隐藏 textarea」的插入符交给**浏览器**去算 IME 候选框的位置，
//   而镜像框里装的原始缓冲区（`$\frac{a}{b}=\sqrt{2}$`…）用 16px 比例字体排出来之后，
//   插入符落在它自己的某行某个 x 上，与我们在页面上画的光标**没有函数关系**。
//   （实测样本：元素 value 201 字符、selStart=29、fontSize 16px —— 两者各排各的。）
//
// 读 `flutter_web_sdk/lib/_engine/engine/text_editing/text_editing.dart` 源码后确认，
// Web 上真正可用的杠杆**只有三条**：
//   ① `TextInput.setEditingState`            → `element.value = text; element.setSelectionRange(min,max)`
//   ② `TextInput.setEditableSizeAndTransform` → `element.style.width/height/transform`
//   ③ `TextInput.setStyle` / `updateStyle`    → `element.style.font*`（CSS 字体）
// ★ 而 `TextInput.setCaretRect` 在 Web 上是**空函数**（源码原文）：
//     `class TextInputSetCaretRect { void run(...) { // No-op: not supported on this platform. } }`
//   （SDK 的 Dart 侧注释也只说它给 macOS 放重音候选菜单用。）
//   ⇒ 任何「只把 setCaretRect 接上」的方案都是白写。
//
// ============================ 现在的做法 ============================
// **让元素里几乎什么都不装**，把元素摆到「我们的光标」处：
//   · 不组合时：元素文本 = `''`        → 元素的插入符就在**元素原点**
//   · 组合时：  元素文本 = `'zhong'`  → 插入符在组合串之后（候选框跟着组合串走，与真人输入法一致）
//   ⇒ **元素插入符位置 ≈ 我们的光标**，与字体、与 `$`/LaTeX 的宽度**彻底解耦**。
//
// 分工（与设计稿 §11.1 的结论一致，且这次是**真的**分工了）：
//   · **文本**（含 IME 提交）走平台文本通道 → 本文件
//   · **命令键**（退格 / 方向键 / …）走**键事件** → 由 `EditView` 的 `Focus.onKeyEvent` 处理
//     ★ 镜像框时代把两者混在文本通道里，所以「方向键只改选区不改文本」要靠补丁同步 ——
//       那是症状不是设计。现在两条通道各归各位。
//   · 组合中间态**一个字都不写进缓冲区**（§11.7），组合结束才一次提交。
//
// ★ 附带收益：**不用再把缓冲区回写输入设备** → 「为显示而注入的东西反过来破坏数据映射」
//   那一整类自干扰 bug（§11.12 的 ⑤）在结构上消失了。

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'platform_text_diff.dart';

/// 清空平台元素的值。
///
/// ⚠️ **不能用 `TextEditingValue.empty`** —— 它的 selection 是 `offset: -1`，
/// 引擎侧 `EditingState.isValid` 要求 `baseOffset >= 0`，会**直接 return 不做任何事**。
const TextEditingValue _kClearedValue = TextEditingValue(
  text: '',
  selection: TextSelection.collapsed(offset: 0),
);

/// 文本输入面：自己实现 `TextInputClient`，直接驱动 Web 的隐藏 textarea。
///
/// 生命周期由 [focusNode] 驱动：拿到焦点 → 接上平台文本通道；失去焦点 → 断开。
class TextInputSurfaceController extends ChangeNotifier with TextInputClient {
  TextInputSurfaceController({required this.focusNode});

  final FocusNode focusNode;

  /// 组合结束（或普通输入）后，**需要插入缓冲区**的那一段文本。
  ///
  /// 注意这里是「增量」而不是「全文」：组合期的字符串**从来没进过缓冲区**，
  /// 所以提交时只需插入新增的那部分（`'zhong'` → `'中'` 只需插 `'中'`）。
  void Function(String text)? onCommitText;

  /// 提交规则链（`Enter` → 新块 等），语义同 `EditableText.inputFormatters`。
  List<TextInputFormatter> inputFormatters = const <TextInputFormatter>[];

  TextInputConnection? _conn;

  /// 平台元素里**当前装着**的文本（我们最后推过去的 / 最后看到的）
  String _platformText = '';

  /// 组合中间态文本（**不写进缓冲区**）
  String _composing = '';

  /// `inputFormatters` 看到的「旧值」
  TextEditingValue _lastValue = _kClearedValue;

  /// 光标矩形（**全局 / 屏幕坐标**）—— 元素就摆在这儿
  Rect _caretRect = const Rect.fromLTWH(0, 0, 300, 24);
  double _fontSize = 16;

  bool get isAttached => _conn != null;
  bool get isComposing => _composing.isNotEmpty;
  String get composingText => _composing;
  Rect get caretRect => _caretRect;

  // 排查提示（探针已撤，需要时两分钟能加回来）：
  // 在 `updateEditingValue` 开头 `debugPrint('[INPUT-PROBE] $value')` 即可 ——
  // ★ Flutter Web 的 `debugPrint` 走**浏览器控制台**（不进 `run.log`），要用 `browser_dock console` 读。
  //   2026-10-14 就是靠它拿到"选字两段式"的真实事件序列（见下面 [updateEditingValue] 的注释）。

  // ---------------------------------------------------------------- 位置与样式

  /// 光标矩形变了（**全局坐标**）→ 把平台元素搬到那里。
  ///
  /// ★ 这就是「候选框跟着光标走」的全部机制：
  ///   `setEditableSizeAndTransform` → `element.style.{width,height,transform}`。
  void setCaretRect(Rect rect, {required double fontSize}) {
    if (_caretRect == rect && _fontSize == fontSize) return;
    _caretRect = rect;
    _fontSize = fontSize;
    _pushStyle();
    _pushGeometry();
  }

  void _pushGeometry() {
    final TextInputConnection? c = _conn;
    if (c == null) return;
    // 元素的局部原点 → 屏幕：纯平移（本项目还没有缩放/旋转的画布变换）
    c.setEditableSizeAndTransform(
      Size(_caretRect.width, _caretRect.height),
      Matrix4.translationValues(_caretRect.left, _caretRect.top, 0),
    );
  }

  void _pushStyle() {
    final TextInputConnection? c = _conn;
    if (c == null) return;
    // 元素里装的文字极少，但字号仍与正文一致 —— 候选框的纵向落点与组合串宽度都跟着它
    c.updateStyle(TextInputStyle(
      fontSize: _fontSize,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    ));
  }

  // ---------------------------------------------------------------- 连接生命周期

  /// 由**用户手势**里调用，确保平台文本通道已接上（浏览器才肯把 IME 接进来）。
  void ensureAttached() {
    if (_conn != null) return;
    _conn = TextInput.attach(
      this,
      const TextInputConfiguration(
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        // 用 TextInputClient（不是 DeltaTextInputClient）：不需要逐字符增量模型
        enableDeltaModel: false,
      ),
    );
    _lastValue = _kClearedValue;
    _platformText = '';
    _pushStyle();
    _pushGeometry();
    _conn!.show();
    _pushEmpty();
  }

  void detach() {
    final TextInputConnection? c = _conn;
    _conn = null;
    _platformText = '';
    _composing = '';
    _lastValue = _kClearedValue;
    if (c != null && c.attached) c.close();
    notifyListeners();
  }

  /// 清空平台元素 → 插入符回到元素原点（= 我们的光标）。
  void _pushEmpty() {
    _platformText = '';
    _lastValue = _kClearedValue;
    _conn?.setEditingState(_kClearedValue);
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }

  // ---------------------------------------------------------------- TextInputClient

  @override
  TextEditingValue? get currentTextEditingValue => _lastValue;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {

    // ① 提交规则链（沿用 EditableText 的语义：`formatEditUpdate(旧值, 新值)`）
    TextEditingValue v = value;
    for (final TextInputFormatter f in inputFormatters) {
      v = f.formatEditUpdate(_lastValue, v);
    }

    final TextRange c = v.composing;
    final bool composing = c.isValid && !c.isCollapsed;

    if (composing) {
      // ★ 组合中间态：一个字都不写进缓冲区；也**不回推**编辑状态（回推会打断 IME）
      _lastValue = v;
      // ★★ 这里**绝不能**更新 `_platformText` —— 2026-10-14 真人键盘 + 控制台探针抓出来的 bug：
      //   Chrome 选字时，**先把组合串换成候选词、但仍标成"组合中"**，然后才结束组合：
      //       ① text=hao'de'hao'de  composing 0..14   ← 拼音
      //       ② text=好的好的        composing 0..4    ← 候选词，**仍标组合中**
      //       ③ text=好的好的        composing none    ← 组合结束
      //   若在 ② 更新基线，③ 的 `diff('好的好的','好的好的')` = null
      //   → `inserted` 为空 → **刚选中的汉字被自己吃掉**（中文标点同理；英文不经过 ②，所以正常）。
      //   ⇒ 基线的含义是「**缓冲区对应的那份平台文本**」（本设计里恒为 `''`），
      //     不是"平台此刻装着什么"。组合串从来没进过缓冲区，所以它也不该进基线。
      final int s = c.start.clamp(0, v.text.length);
      final int e = c.end.clamp(s, v.text.length);
      final String t = v.text.substring(s, e);
      if (t != _composing) {
        _composing = t;
        notifyListeners();
      }
      return;
    }

    // ② 组合结束（或本来就没有组合）：只取「新出现的那段文本」
    final PlatformEdit? edit = diffPlatformText(_platformText, v.text);
    final String inserted = edit?.inserted ?? '';
    final bool wasComposing = _composing.isNotEmpty;
    _composing = '';
    if (inserted.isNotEmpty) {
      onCommitText?.call(inserted);
    }
    _pushEmpty(); // 元素清空 → 插入符回到原点
    if (wasComposing || inserted.isNotEmpty) notifyListeners();
    _lastValue = _kClearedValue;
  }

  @override
  void performAction(TextInputAction action) {
    // ★ 实测（2026-10-14 · Web/Chrome）：`Enter` **不走文本通道** ——
    //   平台发的是 `TextInputAction.newline`，textarea 并没有自己插 `\n`。
    //   （验证方式：按一次 Enter，缓冲区只 +1 个字符；若是文本通道会走 formatter 变成 +2。）
    //   ⇒ 让它与文本通道**共用同一条提交规则链**，绝不写两套规则。
    if (action == TextInputAction.newline) {
      // Shift+Enter = 块内硬换行（R8：行尾两个空格，任何环节都不许 trim）
      final bool soft = HardwareKeyboard.instance.isShiftPressed;
      _commitThroughFormatters(soft ? '  \n' : '\n');
    }
  }

  /// 把一段「原始插入文本」走一遍提交规则链再提交 —— `performAction` 这条路线的入口。
  void _commitThroughFormatters(String raw) {
    TextEditingValue v = TextEditingValue(
      text: raw,
      selection: TextSelection.collapsed(offset: raw.length),
    );
    for (final TextInputFormatter f in inputFormatters) {
      v = f.formatEditUpdate(_kClearedValue, v);
    }
    if (v.text.isNotEmpty) onCommitText?.call(v.text);
    _pushEmpty();
    notifyListeners();
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    // 平台侧主动断开（例如失焦）—— 只清连接，不动缓冲区
    _conn = null;
    _platformText = '';
    _composing = '';
    _lastValue = _kClearedValue;
    notifyListeners();
  }
}
