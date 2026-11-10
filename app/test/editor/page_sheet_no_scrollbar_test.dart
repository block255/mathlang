// 2026-11-10 · 反馈 ①：**页面里那条"不能滚却在显示"的滚动条**
//
// 现场（用户两张截图）：纸面里、**正文栏右边缘**上常驻一条 12px 宽的全高灰条。
//   逐像素量：纸面 x=49..1239（1190px = 793.7 逻辑）、正文栏右边缘 1137、
//   灰条 1122..1133（宽 12）—— 与探针量到的 `Rect(68.0, 95.6, 725.7, 1066.9)` 逐项吻合。
//
// 根因：`page_sheet.dart` 正文区那层 `SingleChildScrollView`（`NeverScrollableScrollPhysics`，
//   **只为裁剪/撑高，根本不能滚**）被桌面端的 `MaterialScrollBehavior.buildScrollbar`
//   无条件下发了一个 `Scrollbar`（Windows 上 `Scrollbar` → `_MaterialScrollbar`），
//   于是它会在页面内部的"正文栏右边缘"画滑块。
//   ★ 框架里 `_handleScrollMetricsNotification` 那条淡入路径**没有**"没得滚就别显示"的保护
//     （对比 `_handleScrollNotification` 里的 `maxScrollExtent <= minScrollExtent ⇒ reverse`），
//     所以内容尺寸一变（打字、重排）它就淡入并**一直停在淡入状态** ⇒ 常驻。
//
// 本守卫钉两条：
//   ① `PageSheet` 子树里**不许有滚动条控件**（改前 1 个 ⇒ 红）；
//   ② 外面那层真能滚的 `SingleChildScrollView` 的滚动条**必须还在**
//      （防"一刀切把 ScrollBehavior 全关了"）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/editor/page_sheet.dart';

const Key _outerKey = Key('outer-scroll');

/// 滚动条控件（`MaterialScrollBehavior` 下发的是 `Scrollbar` → `_MaterialScrollbar`；
/// 两者都是 `RawScrollbar` 的子类）
final Finder _scrollbar = find.byWidgetPredicate(
  (Widget w) => w is RawScrollbar,
  description: '滚动条（RawScrollbar / _MaterialScrollbar）',
);

Future<void> _mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1100, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer('第 1 段正文。\n\n第 2 段正文。\n');
  await tester.pumpWidget(MaterialApp(
    // ★ 必须显式指定 Windows：`MaterialScrollBehavior.buildScrollbar` 只在桌面端下发滚动条
    theme: ThemeData(platform: TargetPlatform.windows),
    home: Scaffold(
      body: SingleChildScrollView(
        key: _outerKey,
        child: SizedBox(width: 793.7, child: EditView(buffer: buf)),
      ),
    ),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('① PageSheet 子树里不许有滚动条控件', (WidgetTester tester) async {
    await _mount(tester);
    expect(find.byType(PageSheet), findsWidgets, reason: '前置条件：得有页面');
    final Finder inner = find.descendant(
      of: find.byType(PageSheet),
      matching: _scrollbar,
      matchRoot: false,
    );
    expect(inner, findsNothing,
        reason: '正文区那层 `SingleChildScrollView` 根本不能滚（NeverScrollableScrollPhysics），'
            '它上面那条滑块就是用户截图里那条灰条');
  });

  testWidgets('② 外面那层能滚的容器：滚动条必须还在', (WidgetTester tester) async {
    await _mount(tester);
    final Finder outer = find.descendant(
      of: find.byKey(_outerKey),
      matching: _scrollbar,
      matchRoot: true,
    );
    expect(outer, findsWidgets,
        reason: '别把 ScrollBehavior 一刀切关掉 —— 该有的滚动条还得有');
  });
}
