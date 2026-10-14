// 数语引擎 · 平台文本值 → 一维缓冲区编辑（S3-2「编辑面」的地基）
//
// 背景：S3-1b 的实验结论是 —— 输入设备必须是**平台的文本输入通道**
// （中文 IME 的组合过程发生在 DOM/平台层，`Focus.onKeyEvent` + `e.character` 拿不到），
// 所以"隐藏的镜像输入框 + 真相留在 DocBuffer"是编辑面的架构。
//
// 本文件负责这条链的换算部分：**平台侧的两次文本值 → 缓冲区的一次区间替换**。
//
// **纯 Dart，不依赖 Flutter。**

import 'dart:math' as math;

/// 一次平台层的文本编辑（偏移**相对镜像文本**）。
class PlatformEdit {
  const PlatformEdit(this.start, this.end, this.removed, this.inserted);

  final int start;
  final int end;
  final String removed;
  final String inserted;

  int get delta => inserted.length - removed.length;

  @override
  String toString() => 'Edit[$start,$end) −「$removed」 +「$inserted」';
}

/// 两次平台文本值 → **一次**源区间替换（公共前缀 / 公共后缀法）。
///
/// ★ 为什么必须是"一次替换"：IME 提交、粘贴、自动更正、自动补全都是一次语义编辑。
/// 逐字符 diff 会把它们拆成多次插入 → **撤销栈炸开**（用户按一次撤销只回一个字）。
///
/// 已知限制：按 UTF-16 码元比较，**不含代理对（emoji 等）的边界修正** ——
/// 若一次编辑的边界落在代理对中间，会切出半个字符。S3-2 按需补（验收时用 emoji 试一次）。
PlatformEdit? diffPlatformText(String oldText, String newText) {
  if (oldText == newText) return null;

  var prefix = 0;
  final int maxPrefix = math.min(oldText.length, newText.length);
  while (prefix < maxPrefix &&
      oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
    prefix++;
  }

  var suffix = 0;
  final int maxSuffix =
      math.min(oldText.length - prefix, newText.length - prefix);
  while (suffix < maxSuffix &&
      oldText.codeUnitAt(oldText.length - 1 - suffix) ==
          newText.codeUnitAt(newText.length - 1 - suffix)) {
    suffix++;
  }

  return PlatformEdit(
    prefix,
    oldText.length - suffix,
    oldText.substring(prefix, oldText.length - suffix),
    newText.substring(prefix, newText.length - suffix),
  );
}
