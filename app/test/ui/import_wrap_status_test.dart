// ★★ F18 守卫（2026-10-21，用户实测）：
// 「导入后弹了包裹 6 处，但是**在底部浮条**里，而不是状态栏」 ⇒ 状态栏那条「自动包裹 N 处 · 查看清单 ›」
// **永远不出现** ⇒ 「查看清单 → 跳转并高亮」**没有任何入口**（T-A 只见过空态）。
//
// 根因：`_autoWrapped` 只由粘贴链 `_commitText → _stampWrapped` 盖；导入走 `loadDocument`
// （整篇替换），从来不经过那条链 ⇒ 计数恒为 0（F2 的 docEpoch 清零又保证它每次都被清）。
//
// 修法：导入后调 `EditViewState.noteExternalWrap(n, spans:)` 把"几处 + 在哪"补给它。
//
// 本文件守三件事：
//   ① 导入后有裸 LaTeX ⇒ 状态栏出现「自动包裹 N 处」；N = 包裹点数
//   ② 点它 ⇒ 弹出诊断清单，条目数 = N
//   ③ 点第一条 ⇒ 光标/选区落到**那一处**（区间与扫描出的数学段一致）
//   反例：导入一份**已规范**的 md（没有裸 LaTeX）⇒ 状态栏**不出现**这一条（不许常驻）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/io/file_gateway.dart';
import 'package:mathlang/io/session_data.dart';
import 'package:mathlang/io/session_store.dart';
import 'package:mathlang/lang/math_spans.dart';
import 'package:mathlang/lang/smart_wrap.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/fake_file_gateway.dart';
import '../support/symbol_fixture.dart';

/// 只返回一份固定会话的假 store
class _FakeSession implements SessionStore {
  _FakeSession(this.data);
  final SessionData? data;

  @override
  int saveCount = 0;

  @override
  Future<SessionData?> load() async => data;

  @override
  Future<bool> save(SessionData d) async {
    saveCount++;
    return true;
  }

  @override
  Future<void> clear() async {}

  @override
  Future<String> describe() async => '假的暂存位置';
}

/// 干净的空白文档（savedText 与正文一致 ⇒ 不脏 ⇒ 导入不会弹"未保存"确认框）
const String kClean = '甲';

const String kBareLatex = '设函数 f(x)=\\frac{1}{x}，当 x>0 时它单调递减。\n\n'
    '若 a_n=\\sqrt{n^2+1}-n，则 lim_{n\\to\\infty}a_n=0。';

const String kCleanMd = '# 标题\n\n已经规范好的行内公式 \$x^2\$ 不该被再包一次。\n';

Future<void> _pump(WidgetTester tester, DocBuffer buf, FakeFileGateway gw) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(
      library: testSymbolLibrary(),
      gateway: gw,
      buffer: buf,
      session: _FakeSession(const SessionData(
        text: kClean,
        title: '未命名文档',
        savedText: kClean,
        caret: 0,
        anchor: 0,
      )),
    ),
  ));
  await tester.pumpAndSettle();
}

/// 导入后"补出来的那几处"（与 `importDocument` 里同一套内容匹配）
List<MathSpan> _wrappedSpans(String raw, SmartWrapPlan plan, String imported) {
  final Set<String> tex = <String>{
    for (final WrapRun r in plan.runs) raw.substring(r.start, r.end).trim(),
  };
  return <MathSpan>[
    for (final MathSpan s in scanMathSpans(imported))
      if (tex.contains(s.tex.trim())) s,
  ];
}

void main() {
  testWidgets('★★ 导入裸 LaTeX ⇒ 状态栏出现「自动包裹 N 处」，点进去能跳到那一处',
      (WidgetTester tester) async {
    final DocBuffer buf = DocBuffer(kClean);
    final FakeFileGateway gw = FakeFileGateway(
      toOpen: const OpenedFile(
        path: r'C:\x\验收-自动包裹.txt',
        name: '验收-自动包裹.txt',
        text: kBareLatex,
      ),
    );
    await _pump(tester, buf, gw);

    final EditorPageState st = tester.state<EditorPageState>(find.byType(EditorPage));
    await st.importDocument();
    await tester.pumpAndSettle();

    final SmartWrapPlan plan = planSmartWrap(kBareLatex);
    expect(plan.runs, isNotEmpty, reason: '样本本身必须能被包裹（否则测不到）');
    final int n = plan.runs.length;

    // ① 状态栏那条必须出现（改前：永远为 0 ⇒ 什么都不显示）
    expect(find.byKey(const Key('diag-open')), findsOneWidget,
        reason: '导入 $n 处之后，状态栏必须给「自动包裹 $n 处 · 查看清单 ›」一个入口');
    expect(find.textContaining('自动包裹 $n 处'), findsOneWidget);

    // ② 点它 ⇒ 清单弹出来，条目数 = N
    await tester.tap(find.byKey(const Key('diag-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('diagnostics-dialog')), findsOneWidget);
    for (var i = 0; i < n; i++) {
      expect(find.byKey(Key('diagnostic-item-$i')), findsOneWidget,
          reason: '第 $i 条应该在清单里');
    }

    // ③ 点第一条 ⇒ 落到那一处（与"按内容匹配"的扫描结果一致）
    final String imported = applySmartWrap(kBareLatex, plan);
    final List<MathSpan> spans = _wrappedSpans(kBareLatex, plan, imported);
    expect(spans, isNotEmpty, reason: '清单里的区间必须能在导入后的文本里定位到');
    await tester.tap(find.byKey(const Key('diagnostic-item-0')));
    await tester.pumpAndSettle();
    expect(buf.selectionStart, spans.first.start,
        reason: '点第一条 ⇒ 选区从那一处开始');
    expect(buf.selectionEnd, spans.first.end,
        reason: '点第一条 ⇒ 选区到那一处结束（高亮的就是它）');
  });

  testWidgets('★ 反例：导入**已规范**的 md ⇒ 状态栏不出现这一条（不许常驻）',
      (WidgetTester tester) async {
    final DocBuffer buf = DocBuffer(kClean);
    final FakeFileGateway gw = FakeFileGateway(
      toOpen: const OpenedFile(path: r'C:\x\规范.md', name: '规范.md', text: kCleanMd),
    );
    await _pump(tester, buf, gw);

    final EditorPageState st = tester.state<EditorPageState>(find.byType(EditorPage));
    await st.importDocument();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('diag-open')), findsNothing,
        reason: '一处都没补 ⇒ 状态栏不该出现"自动包裹 0 处"');
  });
}
