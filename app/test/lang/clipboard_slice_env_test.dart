// 反馈 16（2026-10-30 · R6）守卫：**选区停在环境中间时，切片要把环境补配平**。
//
// 实测病灶（用户那份 2022-2023 期中第 5 题）：从 `\begin{cases}` 选到 `y=3tsint` 松手
//   （尾巴没带上 `\end{cases}`）⇒ 旧代码吐出
//   `$\begin{cases}x=3tcost\\⏎y=3tsint$`（`\begin`/`\end` 不配平）⇒ 粘到行内即 `[公式不完整]`。
//
// 改前必红：`\end{cases}` 不见（或配平数为 0）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/clipboard_slice.dart';

const String kDoc = '\$\$\n'
    r'f(x)=\begin{cases}x=3tcost\\'
    '\n'
    r'y=3tsint'
    '\n'
    r'\end{cases}'
    '\n\$\$\n';

int _count(String s, String pat) => s.split(pat).length - 1;

void main() {
  test('① 从 \\begin 选到第二行末尾 ⇒ 补上 \\end{cases}', () {
    final int s = kDoc.indexOf(r'\begin{cases}');
    final int e = kDoc.indexOf('y=3tsint') + 'y=3tsint'.length;
    final ClipboardSlice sl = clipboardSlice(kDoc, s, e);
    expect(_count(sl.text, r'\begin{cases}'), 1);
    expect(_count(sl.text, r'\end{cases}'), 1, reason: '环境要配平（改前是 0）');
    expect(sl.text.contains('3tsint'), isTrue);
  });

  test('② 嵌套环境一起补齐', () {
    const String d = '\$\$\n'
        r'\begin{cases}a=\begin{matrix}1\\2\end{matrix}\\b'
        '\n'
        r'\end{cases}'
        '\n\$\$\n';
    final int s = d.indexOf(r'\begin{cases}');
    final int e = d.indexOf(r'\end{matrix}') + r'\end{matrix}'.length;
    final ClipboardSlice sl = clipboardSlice(d, s, e);
    expect(_count(sl.text, r'\begin{cases}'), _count(sl.text, r'\end{cases}'));
    expect(_count(sl.text, r'\begin{matrix}'), _count(sl.text, r'\end{matrix}'));
  });

  test('③ 已经完整的选区一个字都不改', () {
    final int s = kDoc.indexOf(r'$$');
    final int e = kDoc.lastIndexOf(r'$$') + 2;
    final ClipboardSlice sl = clipboardSlice(kDoc, s, e);
    expect(sl.text.contains(r'\end{cases}'), isTrue);
    expect(sl.text.contains(r'\begin{cases}'), isTrue);
  });
}
