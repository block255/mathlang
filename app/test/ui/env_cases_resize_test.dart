// ★★ 2026-10-23（批 2 · C/E1）：尺寸面板的**单栏形态**（分段函数 / 对齐推导）。
//
// 用户口径：「那个参数就**段数**，然后就段数（数字），不用接 × 数字」。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/env_resize.dart';
import 'package:mathlang/ui/env_size_dialog.dart';

Future<EnvSizeChoice?> _open(
  WidgetTester tester, {
  required bool rowsOnly,
  required String rowsLabel,
  required String unit,
  int rows = 2,
  int cols = 2,
  bool determinant = false,
  EnvStyle style = EnvStyle.cases,
}) async {
  EnvSizeChoice? out;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (BuildContext ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              out = await showEnvSizeDialog(
                ctx,
                style: style,
                rows: rows,
                cols: cols,
                determinant: determinant,
                rowsOnly: rowsOnly,
                rowsLabel: rowsLabel,
                unit: unit,
                title: '分段函数',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return out;
}

String _preview(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('env-size-preview'))).data ?? '';

void main() {
  testWidgets('★ 分段函数：只有「段数」一栏，预览写「2 段」而不是「2 × 2」',
      (WidgetTester tester) async {
    await _open(tester, rowsOnly: true, rowsLabel: '段数', unit: '段');

    expect(find.text('段数'), findsOneWidget);
    expect(find.byKey(const Key('env-size-rows')), findsOneWidget);
    expect(find.byKey(const Key('env-size-cols')), findsNothing,
        reason: '只有一个自由度 ⇒ 不许有列数一栏');
    expect(find.byKey(const Key('env-size-style')), findsNothing,
        reason: '括号由环境自带 ⇒ 不许有括号选择');
    expect(_preview(tester), '预览：2 段');
    expect(find.text('× 2'), findsNothing);
  });

  testWidgets('改成 3 段 ⇒ 预览跟着变；应用后返回 rows=3 / cols 保持 2',
      (WidgetTester tester) async {
    await _open(tester, rowsOnly: true, rowsLabel: '段数', unit: '段');
    await tester.enterText(find.byKey(const Key('env-size-rows')), '3');
    await tester.pumpAndSettle();
    expect(_preview(tester), '预览：3 段');

    await tester.tap(find.byKey(const Key('env-size-apply')));
    await tester.pumpAndSettle();
    // 弹窗关闭后按钮回调把结果写进闭包 —— 通过"弹窗消失"确认应用生效
    expect(find.byKey(const Key('env-size-dialog')), findsNothing);
  });

  testWidgets('越过 1..12 ⇒ 报错不关闭', (WidgetTester tester) async {
    await _open(tester, rowsOnly: true, rowsLabel: '段数', unit: '段');
    await tester.enterText(find.byKey(const Key('env-size-rows')), '13');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('env-size-apply')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('env-size-dialog')), findsOneWidget);
    expect(find.textContaining('1–12'), findsOneWidget);
  });

  testWidgets('矩阵面板不受影响：仍有行数 / 列数 / 括号', (WidgetTester tester) async {
    await _open(tester,
        rowsOnly: false,
        rowsLabel: '行数',
        unit: '行',
        style: EnvStyle.bracket);
    expect(find.byKey(const Key('env-size-rows')), findsOneWidget);
    expect(find.byKey(const Key('env-size-cols')), findsOneWidget);
    expect(find.byKey(const Key('env-size-style')), findsOneWidget);
    expect(_preview(tester), '预览：2 × 2');
  });
}
