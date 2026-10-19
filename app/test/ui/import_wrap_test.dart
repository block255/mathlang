// ★★ U2 守卫（2026-10-19）：**导入 .md 也走智能包裹**（用户拍板方案 E）
//
// 起因（用户实测）：导入 `作业辅导1.md` 后满屏裸编码 —— 那份 md 里的 LaTeX **没有 `$…$`**
//   （`\varepsilon` / `\left| \sum…\right| \le …`），而原来的口径是"md 原样、只有 txt 包裹"
//   ⇒ 正确但不符合预期（违反原则 2：用户永远不需要看数学编码）。
//
// 新口径：**所有文本导入都走同一条链**（`planSmartWrap` + `applySmartWrap`，与粘贴完全一致）：
//   · 裸 LaTeX ⇒ 补 `$…$`（整行式子 4 处以上判成 `$$…$$` 行间块）；
//   · 已经规范的 md（`$…$` 齐全）⇒ **一个字符都不改**（扫描器跳过已在 `$…$` 里的内容）；
//   · 纯中文 ⇒ 不误包。
// ★ 诚实边界：`loadDocument` 会清撤销栈 ⇒ 导入**不参与撤销**，所以文案不承诺 Ctrl+Z，
//   安全网是"**从不写回源文件**"（原件一直没动）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/io/file_gateway.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/fake_file_gateway.dart';
import '../support/symbol_fixture.dart';

Future<(EditorPageState, DocBuffer, FakeFileGateway)> _pump(
    WidgetTester tester) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final FakeFileGateway gw = FakeFileGateway();
  final DocBuffer buf = DocBuffer('abc')..setCaret(3);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(library: testSymbolLibrary(), buffer: buf, gateway: gw),
  ));
  await tester.pumpAndSettle();
  return (tester.state<EditorPageState>(find.byType(EditorPage)), buf, gw);
}

/// 用户那份真实文件里的三段（裸 LaTeX，不带 `$`）
const String kUserMd = '在这个题里，\\{a_n\\} 本身不一定是单调的\n\n'
    '对任意 \\varepsilon > 0，存在 N，当 m > n > N 时。\n\n'
    '|a_m - a_n| = \\left| \\sum_{k=n+1}^m (a_k - a_{k-1}) \\right| \\le 1\n';

void main() {
  group('㉕ 导入 .md 也走智能包裹（U2）', () {
    testWidgets('★★ 裸 LaTeX 的 md ⇒ 被包成 `\$…\$`（改前：原样入库，满屏编码）',
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf, FakeFileGateway gw) =
          await _pump(tester);
      gw.toOpen = const OpenedFile(
        path: r'C:\docs\作业辅导1.md',
        name: '作业辅导1.md',
        text: kUserMd,
      );
      await st.importDocument();
      await tester.pumpAndSettle();

      expect(buf.buf, isNot(kUserMd), reason: '改前是逐字原样；现在必须被包裹');
      expect(buf.buf, contains(r'$\{a_n\}$'), reason: 'braces 那处要包起来');
      expect(buf.buf, contains(r'\varepsilon > 0$'),
          reason: r'\varepsilon > 0 必须在 $…$ 里（否则用户会看到编码）');
      // ★ 更有意义的判据：**公式外面不许还剩反斜杠**（= 用户看不到任何编码）
      final String outside = buf.buf
          .replaceAll(RegExp(r'\$\$[\s\S]*?\$\$'), '') // 去掉行间块
          .replaceAll(RegExp(r'\$[^\$\n]*\$'), ''); // 去掉行内公式
      final List<String> rest = outside
          .split('\n')
          .where((String l) => l.contains(r'\'))
          .toList();
      expect(rest, isEmpty, reason: '还有裸编码留在公式外：');
      // 中文一个字都不许丢
      expect(buf.buf, contains('本身不一定是单调的'));
    });

    testWidgets('★★ 已经规范的 md（`\$…\$` 齐全）⇒ 逐字不变，一处都不改',
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf, FakeFileGateway gw) =
          await _pump(tester);
      const String good = '# 标题\n\n设 \$x^2+1\$ 是多项式，\$\\frac{a}{b}=2\$。\n';
      gw.toOpen = const OpenedFile(
        path: r'C:\docs\规范.md',
        name: '规范.md',
        text: good,
      );
      await st.importDocument();
      await tester.pumpAndSettle();
      expect(buf.buf, good, reason: '规范 md 必须逐字不动（智能包裹只吃裸 LaTeX）');
    });

    testWidgets('★★ 纯中文 md ⇒ 不误包（一个 `\$` 都不加）',
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf, FakeFileGateway gw) =
          await _pump(tester);
      const String plain = '这是一段中文说明。\n没有任何式子。\n';
      gw.toOpen = const OpenedFile(
        path: r'C:\docs\说明.md',
        name: '说明.md',
        text: plain,
      );
      await st.importDocument();
      await tester.pumpAndSettle();
      expect(buf.buf, plain);
      expect(buf.buf.contains(r'$'), isFalse);
    });

    testWidgets('★ 导入后**没有**撤销可退（诚实口径：导入 = 新文档，靠"原件没动"兜底）',
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf, FakeFileGateway gw) =
          await _pump(tester);
      gw.toOpen = const OpenedFile(
        path: r'C:\docs\作业辅导1.md',
        name: '作业辅导1.md',
        text: kUserMd,
      );
      await st.importDocument();
      await tester.pumpAndSettle();
      expect(buf.canUndo, isFalse,
          reason: 'loadDocument 清撤销栈 ⇒ 文案里不许承诺 Ctrl+Z（这条守卫防"说了做不到"）');
    });
  });
}
