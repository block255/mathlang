// ★★ U2 守卫（2026-10-21 用户拍板）：面板 / 快捷栏的**键盘流**。
//
// 口径（用户定）：
//   · `Ctrl+/` **保持纯开关、不抢焦点**（"熟练的人可能不需要搜索框，保持光标在编辑页"）
//   · 另给 `F6`（面板）/ `F7`（快捷栏）两个**显式**入口；`Esc` 立刻把焦点还给编辑器
//   · 面板内：方向键移动高亮、`Enter`/空格插入（**空格=甲，插入当前格**）、`1–8` 跳格、
//     `Tab` 去搜索框；快捷栏内：方向键/1–8 选格、`Enter` 赋值、`Delete` 清空
//   · 焦点要**看得见**（2px 蓝边 + 淡蓝底）
//
// 改前必红：F6/F7 在旧代码里不存在（键盘流没有入口）⇒ 本文件所有断言都红。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/io/session_data.dart';
import 'package:mathlang/io/session_store.dart';
import 'package:mathlang/ui/app_settings.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/fake_file_gateway.dart';
import '../support/symbol_fixture.dart';

class _NoopSession implements SessionStore {
  @override
  int saveCount = 0;

  @override
  Future<SessionData?> load() async => null;
  @override
  Future<bool> save(SessionData d) async => true;
  @override
  Future<void> clear() async {}
  @override
  Future<String> describe() async => '测试暂存';
}

Future<(EditorPageState, DocBuffer)> _pump(
  WidgetTester tester, {
  AppSettings? settings,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer('甲乙');
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(
      library: testSymbolLibrary(),
      gateway: FakeFileGateway(),
      buffer: buf,
      session: _NoopSession(),
      settings: settings,
    ),
  ));
  await tester.pumpAndSettle();
  // ★ 必须让**编辑器拿到焦点**：否则 primaryFocus 停在 ModalScope 上，
  //   键事件不会沿 shell 的 Focus 冒泡（真机上一进来就是编辑器有焦点）。
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return (tester.state<EditorPageState>(find.byType(EditorPage)), buf);
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey k) async {
  await tester.sendKeyEvent(k);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('★★ F6 ⇒ 焦点进面板；方向键移动高亮；Esc 回到编辑器（面板仍开）',
      (WidgetTester tester) async {
    final (EditorPageState st, DocBuffer _) = await _pump(tester);
    expect(st.debugKbdArea, 'none', reason: '一进来焦点在编辑器，面板不该抢');

    await _press(tester, LogicalKeyboardKey.f6);
    expect(st.debugKbdArea, 'panel', reason: 'F6 是"进入面板键盘流"的显式入口');
    expect(find.byKey(const Key('symbol-panel')), findsOneWidget);
    expect(st.debugPanelCount, greaterThan(3), reason: '面板要先把筛出来的顺序回吐给外层');
    expect(st.debugKbdIndex, 0);

    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(st.debugKbdIndex, 1, reason: '→ 下一个格子');

    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(st.debugKbdIndex, 0, reason: '← 上一个（回绕）');

    await _press(tester, LogicalKeyboardKey.escape);
    expect(st.debugKbdArea, 'none', reason: 'Esc 把焦点还给编辑器');
    expect(find.byKey(const Key('symbol-panel')), findsOneWidget,
        reason: 'Esc 只退焦点，**不关面板**（面板开着才能继续看）');
  });

  testWidgets('★★ 面板里 空格 = 插入当前格（甲）；Enter 同义；1–8 直接跳格',
      (WidgetTester tester) async {
    final (EditorPageState st, DocBuffer buf) = await _pump(tester);
    await _press(tester, LogicalKeyboardKey.f6);

    final int before = buf.length;
    await _press(tester, LogicalKeyboardKey.space);
    expect(buf.length, greaterThan(before),
        reason: '空格要插入当前格（用户拍板：甲）');
    expect(st.debugKbdArea, 'panel', reason: '插完焦点留在面板 ⇒ 可连插');

    final int afterSpace = buf.length;
    await _press(tester, LogicalKeyboardKey.enter);
    expect(buf.length, greaterThan(afterSpace), reason: 'Enter 与空格同义');

    await _press(tester, LogicalKeyboardKey.digit3);
    expect(st.debugKbdIndex, 2, reason: '按 3 直接跳到第 3 格');
  });

  testWidgets('★★ 焦点环看得见：面板格子上出现 2px 蓝边', (WidgetTester tester) async {
    final (EditorPageState st2, DocBuffer buf2) = await _pump(tester);
    expect(buf2.length, greaterThan(0));
    await _press(tester, LogicalKeyboardKey.f6);
    expect(st2.debugKbdArea, 'panel');
    // 至少有一格带"焦点环"配色（#EBF5FF 底 / #1E88E5 边）
    var ring = 0;
    for (final Element e in find.byType(Container).evaluate()) {
      final Container c = e.widget as Container;
      final BoxDecoration? d = c.decoration as BoxDecoration?;
      final Border? b = d?.border as Border?;
      if (b != null && b.top.color == const Color(0xFF1E88E5) && b.top.width == 2) {
        ring++;
      }
    }
    expect(ring, greaterThan(0), reason: '键盘焦点必须有可见的环（否则不知道在哪）');
  });

  testWidgets('★★ F7 ⇒ 焦点进快捷栏；→ 选格；Enter 进赋值模式；Delete 清空',
      (WidgetTester tester) async {
    final (EditorPageState st, DocBuffer _) = await _pump(
      tester,
      settings: const AppSettings(
        favorites: <String?>['frac', 'sqrt', null, null, null, null, null, null],
      ),
    );
    expect(st.debugFavoriteAt(0), 'frac');

    await _press(tester, LogicalKeyboardKey.f7);
    expect(st.debugKbdArea, 'quick', reason: 'F7 是快捷栏的键盘入口');

    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(st.debugKbdIndex, 1);

    // Delete：清空第 2 格（sqrt）
    await _press(tester, LogicalKeyboardKey.delete);
    expect(st.debugFavoriteAt(1), isNull, reason: 'Delete 清空该格（替代长按）');

    // Enter：进入赋值模式 ⇒ 出现提示条
    await _press(tester, LogicalKeyboardKey.enter);
    expect(find.byKey(const Key('quick-assign-hint')), findsOneWidget,
        reason: 'Enter = 进入赋值模式（等价点一下空格）');

    await _press(tester, LogicalKeyboardKey.escape);
    expect(st.debugKbdArea, 'none');
  });
}
