// **基准守卫**（2026-10-27）：Enter / 退格 = **一次按键只动一行**。
//
// 规格：[`notes/design/行与段-空行基准.md`](../../../notes/design/行与段-空行基准.md) §三（A1–A4 / B1–B2 / E1–E2）
// + §六 实测（用户 2026-10-27 手测：旧版 1.1.1 与开发版 1.1.2 逐条对照）。
//
// ★ 为什么用"空行数 n"而不是字符数，也不直接量像素：
//   · 字符数是实现细节 —— 同一个 `\n\n` 在段间是 0 行、在行末插入时会变成 +2 行（§二 的陷阱）；
//   · 像素在空行与正文行之间不是同一把尺子（正文行距 ≈38px，空行步长 ≈20px）。
//   · **行数 = n − 1**（`blank_runs.extraBlankHeight` 的判据）⇒ "一次按键多一行"就是 **n 加 1**。
//
// 现状（改前）：A1 / A2 一次 Enter 让 n 加 **2**（红）；B2 第二下 n 不动（红）；A4 绿。
// 修完之后：A1/A2/A4 每按一次 n 加 1；B2 每按一次 n 加 1；E2 逐字还原。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/blank_runs.dart';
import 'package:mathlang/editor/edit_view.dart';

/// 基准文档（用户 2026-10-27 手测用）：`⏎` = 换行
const String kBase = '上上下下\n\naaabbccc\n\n你好你吃饭了吗\n';

Future<DocBuffer> _mount(WidgetTester tester, String doc, int caret) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key, [int n = 1]) async {
  for (var i = 0; i < n; i++) {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }
}

/// "上一行之后那一串空行"的个数（判据同 `extraBlankHeight`：n=1 ⇒ 0 行，n=2 ⇒ 1 行）
int _nAfter(String buf, int acceptTo) => blankRunAfter(buf, acceptTo).length;

/// 文末那串空行的个数
int _nTail(String buf, int from) => blankRunFrom(buf, from).length;

/// 文末**看得见的空行数**：`甲⏎` / `甲⏎⏎` = 0 行；`甲⏎⏎⏎` = 1 行（口径同 `edit_view._visibleTailLines`）
int _tailLines(String s) {
  var m = 0;
  while (m < s.length && s[s.length - 1 - m] == '\n') {
    m++;
  }
  return m <= 2 ? 0 : m - 2;
}

/// 当前光标条的纵坐标（屏幕像素）—— "看得见的一行"就用它量
double _caretY(WidgetTester tester) {
  final List<double> ys = <double>[];
  for (final Element e in find.byType(Container).evaluate()) {
    final Container w = e.widget as Container;
    final BoxConstraints? c = w.constraints;
    if (c == null || c.minWidth != 1.5 || c.maxWidth != 1.5) continue;
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize) continue;
    ys.add(ro.localToGlobal(Offset.zero).dy);
  }
  if (ys.isEmpty) return -1;
  ys.sort();
  return ys.last; // 文末槽那根就是最靠下的一根
}

void main() {
  // ─── A1：行末 ───
  testWidgets('A1 行末 Enter ⇒ 空行数 +1（一次只加一行）；退格一次逐字还原',
      (WidgetTester tester) async {
    const int afterXia = 4;
    final DocBuffer buf = await _mount(tester, kBase, afterXia);
    expect(_nAfter(kBase, afterXia), 1, reason: '前置：下 与 aaabbccc 之间本来有 1 个空行（段距）');
    await _press(tester, LogicalKeyboardKey.enter);
    // ignore: avoid_print
    print('[A1] Enter 后 | caret=${buf.caret} n=${_nAfter(buf.buf, afterXia)} | '
        '${buf.buf.replaceAll('\n', '⏎')}');
    expect(_nAfter(buf.buf, afterXia), 2,
        reason: '一次 Enter 只加一行（改前是 3 ⇒ 一下长两行）');
    await _press(tester, LogicalKeyboardKey.backspace);
    expect(buf.buf, kBase, reason: '一次退格逐字还原');
    expect(buf.caret, afterXia);
  });

  // ─── A2：行首 ───
  testWidgets('A2 行首 Enter ⇒ 空行数 +1；光标仍在 a 前；退格一次逐字还原',
      (WidgetTester tester) async {
    const int beforeA = 6;
    final DocBuffer buf = await _mount(tester, kBase, beforeA);
    await _press(tester, LogicalKeyboardKey.enter);
    // ignore: avoid_print
    print('[A2] Enter 后 | caret=${buf.caret} n=${_nAfter(buf.buf, 4)} | '
        '${buf.buf.replaceAll('\n', '⏎')}');
    expect(_nAfter(buf.buf, 4), 2,
        reason: '一次 Enter 只加一行（改前是 3 ⇒ 下两行，要退两次）');
    expect(buf.caret < buf.buf.length && buf.buf[buf.caret] == 'a', isTrue,
        reason: '光标仍在 a 前面（实际 caret=${buf.caret}）');
    await _press(tester, LogicalKeyboardKey.backspace);
    expect(buf.buf, kBase, reason: '一次退格逐字还原（改前要两次）');
    expect(buf.caret, beforeA);
  });

  // ─── A3：行内切段（已符合基准，不许被改坏）───
  testWidgets('A3 行内 Enter ⇒ 断成两行（空行数不变）；退格一次接回',
      (WidgetTester tester) async {
    const String doc = 'aaabbccc\n';
    final DocBuffer buf = await _mount(tester, doc, 3);
    await _press(tester, LogicalKeyboardKey.enter);
    expect(buf.buf, 'aaa\n\nbbccc\n', reason: '行内切段 = 断成两段');
    await _press(tester, LogicalKeyboardKey.backspace);
    expect(buf.buf, doc, reason: '退格一次接回');
    expect(buf.caret, 3);
  });

  // ─── A4：已有空行上（Enter 侧已符合基准）───
  testWidgets('A4 已有空行上 Enter ⇒ 空行数 +1（每按一次一行）',
      (WidgetTester tester) async {
    const String doc = '甲\n\n乙\n';
    final DocBuffer buf = await _mount(tester, doc, 2);
    expect(_nAfter(doc, 1), 1);
    await _press(tester, LogicalKeyboardKey.enter);
    expect(_nAfter(buf.buf, 1), 2, reason: '一次 Enter 加一行');
    await _press(tester, LogicalKeyboardKey.enter);
    expect(_nAfter(buf.buf, 1), 3, reason: '再按再加一行');
  });

  // ─── B1 / B2：文末 ───
  // ★ 文末不能用"空行数"当判据：`甲⏎⏎` 的空行数 = 1（= 0 行），
  //   但尾部槽会给"最后一行下面"画一根光标 ⇒ 用户看到的就是一行。
  //   ⇒ 这里按**看得见的量**断言：每按一次 Enter，缓冲区恰好 +1 个换行、**光标往下走一行**。
  testWidgets('B1/B2 文末 Enter ⇒ 每按一次恰好一行；光标每次下移一行',
      (WidgetTester tester) async {
    const String doc = '甲\n';
    final DocBuffer buf = await _mount(tester, doc, 2);
    final List<int> lens = <int>[buf.buf.length];
    final List<int> lines = <int>[_tailLines(doc)];
    final List<double> ys = <double>[_caretY(tester)];
    for (var i = 0; i < 3; i++) {
      await _press(tester, LogicalKeyboardKey.enter);
      lens.add(buf.buf.length);
      lines.add(_tailLines(buf.buf));
      ys.add(_caretY(tester));
      // ignore: avoid_print
      print('[B${i + 1}] caret=${buf.caret} len=${buf.buf.length} '
          'lines=${lines.last} y=${ys.last} | ${buf.buf.replaceAll('\n', '⏎')}');
    }
    for (var i = 1; i < lens.length; i++) {
      // ★ 判据是**看得见的行数**，不是字符数：`甲⏎` 与 `甲⏎⏎` 都是 0 行，
      //   所以第一下要补两个换行才出现一整行；之后每下补一个。
      expect(lines[i], i, reason: '第 $i 次 Enter 之后应当有 $i 行空白');
      expect(ys[i] - ys[i - 1], greaterThan(10),
          reason: '第 $i 次 Enter 光标要真的往下走一行（改前第二下起封顶 ⇒ 不动）');
    }
  });
}
