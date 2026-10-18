// 守卫：矩阵/行列式尺寸面板（PC-5）
//
// 用户口径：面板固定居中 · 行列数可**键入** · 矩阵括号 `[ ]`/`( )` · 行列式强制方阵 ·
//   `Enter` 应用 / `Esc` 取消。
// 这里只测**面板自己的行为**（返回值），不测右键接线。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/env_resize.dart';
import 'package:mathlang/ui/env_size_dialog.dart';

Future<void> _open(
  WidgetTester tester, {
  EnvStyle style = EnvStyle.bracket,
  int rows = 2,
  int cols = 2,
  bool determinant = false,
  void Function(EnvSizeChoice?)? onResult,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (BuildContext c) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final EnvSizeChoice? r = await showEnvSizeDialog(
                c,
                style: style,
                rows: rows,
                cols: cols,
                determinant: determinant,
                title: determinant ? '行列式' : '矩阵',
              );
              onResult?.call(r);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('键入数字 + 应用 ⇒ 返回键入的尺寸', (WidgetTester tester) async {
    EnvSizeChoice? got;
    await _open(tester, onResult: (EnvSizeChoice? r) => got = r);
    await tester.enterText(find.byKey(const Key('env-size-rows')), '4');
    await tester.enterText(find.byKey(const Key('env-size-cols')), '5');
    await tester.pump();
    expect(
        (tester.widget(find.byKey(const Key('env-size-preview'))) as Text).data,
        contains('4 × 5'));
    await tester.tap(find.byKey(const Key('env-size-apply')));
    await tester.pumpAndSettle();
    expect(got, isNotNull);
    expect(got!.rows, 4);
    expect(got!.cols, 5);
  });

  testWidgets('行列式：列数框被禁用，列数跟随行数', (WidgetTester tester) async {
    EnvSizeChoice? got;
    await _open(tester, determinant: true, onResult: (EnvSizeChoice? r) => got = r);
    final TextField cols =
        tester.widget(find.byKey(const Key('env-size-cols'))) as TextField;
    expect(cols.enabled, isFalse, reason: '行列式强制方阵 ⇒ 列数不可改');
    await tester.enterText(find.byKey(const Key('env-size-rows')), '3');
    await tester.pump();
    await tester.tap(find.byKey(const Key('env-size-apply')));
    await tester.pumpAndSettle();
    expect(got!.rows, 3);
    expect(got!.cols, 3);
  });

  testWidgets('取消 ⇒ 返回 null', (WidgetTester tester) async {
    EnvSizeChoice? got;
    bool called = false;
    await _open(tester, onResult: (EnvSizeChoice? r) {
      got = r;
      called = true;
    });
    await tester.tap(find.byKey(const Key('env-size-cancel')));
    await tester.pumpAndSettle();
    expect(called, isTrue);
    expect(got, isNull);
  });

  testWidgets('超出范围 ⇒ 报错且不返回', (WidgetTester tester) async {
    bool called = false;
    await _open(tester, onResult: (EnvSizeChoice? r) {
      called = true;
    });
    await tester.enterText(find.byKey(const Key('env-size-rows')), '99');
    await tester.pump();
    await tester.tap(find.byKey(const Key('env-size-apply')));
    await tester.pumpAndSettle();
    expect(called, isFalse, reason: '越界不该关面板');
    expect(find.textContaining('请输入'), findsOneWidget);
  });
}
