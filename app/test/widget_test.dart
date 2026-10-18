// 入口冒烟测试（2026-10-17 更新）。
//
// ★ 语义变了：**软件端（非 Web）直接进编辑器**，Web 才进实验台（用户 2026-10-17 拍板：
//   "正式端先 Windows；Web 只用于开发"）。所以这里分别验两条入口：
//   ① `MathlangApp` 在测试环境（非 Web）⇒ **编辑器**（不再是我们以前测的实验台）；
//   ② 实验台本身仍然可用（把 `ExperimentHome` 直接 pump 起来验第一个入口项）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/main.dart';
import 'package:mathlang/ui/editor_page.dart';

void main() {
  testWidgets('非 Web：MathlangApp 直接进编辑器', (WidgetTester tester) async {
    await tester.pumpWidget(const MathlangApp());
    await tester.pump();
    expect(find.byType(EditorPage), findsOneWidget);
    // 顶栏该在（说明真的进了编辑器外壳，而不是白屏）
    expect(find.byKey(const Key('file-menu')), findsOneWidget);
  });

  testWidgets('实验台入口仍然可用（Web 走这条）', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ExperimentHome()));
    expect(find.text('★ 问 0 · 流内数学映射可行性'), findsOneWidget);
  });
}
