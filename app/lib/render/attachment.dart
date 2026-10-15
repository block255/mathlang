// 数语引擎 · 「挂件」（attachment）—— 脚本与**定宽字形 accent**
//
// ★★ 为什么单开一个文件：这一条判据现在有**三个消费者**，不能挂在其中任意一个身上：
//   ① **删除**（`smart_delete.dart`）：挂件的边缘像素按"一个字符"办（§4.0'）
//   ② **空槽占位**（`slot_marks.dart`）：**挂件槽不画占位框**（§4.8 第三类）
//   ③ **尾垫**（`slot_marks.kTailCommands`）：定宽 accent **不进**尾垫名单
//      （尾垫只撑盒、那个定宽字形不会跟着变长）
//
// ★ 名单是**读引擎源码得来的，不是猜的**：
//   `flutter_math_fork` 的 `parser/tex/functions/katex_base/accent.dart`：
//   ```dart
//   const nonStretchyAccents = {
//     '\\acute', '\\grave', '\\ddot', '\\tilde', '\\bar', '\\breve',
//     '\\check', '\\hat', '\\vec', '\\dot', '\\mathring',
//   };
//   ```
//   非拉伸 accent 的装饰是**一个小字形**，盒子被**强制撑到内容宽**
//   （`ast/nodes/accent.dart` 原话：*"Non stretchy accent can not contribute to overall
//   width, thus they must fit exactly with the width even if it means overflow"*）
//   ⇒ **墨迹不跟着内容变长** ⇒ 结构左右缘 == 内容左右缘 ⇒ 两个位点**永远在同一根像素**。
//   另一半（`\overline` `\underline` `\widehat` `\widetilde` `\overrightarrow` …）是**会拉伸**的，
//   它们的装饰跟着内容变长 ⇒ 不算挂件，走"结构 + 尾垫"那一套。
//
// **纯 Dart。**
import 'caret_sites.dart';

/// 命令名（**不带反斜杠**，与 `TexItem.command` 一致）
const Set<String> kFixedShapeAccents = <String>{
  'acute', 'grave', 'ddot', 'tilde', 'bar', 'breve',
  'check', 'hat', 'vec', 'dot', 'mathring',
};

/// 脚本标记（上标 / 下标）
const Set<String> kScriptMarks = <String>{'^', '_'};

/// 这个命令是不是一个**挂件**（脚本 或 定宽 accent）
bool isAttachmentCommand(String? cmd) =>
    cmd != null && (kScriptMarks.contains(cmd) || kFixedShapeAccents.contains(cmd));

/// 槽路径的最后一步是不是挂件（`slot_marks` 判"挂件槽不画占位框"用它）
bool isAttachmentSlot(SlotSpan s) =>
    s.path.isNotEmpty && isAttachmentCommand(s.path.last.command);
