// 守卫测试：平台文本通道接上去时，`TextInput.setClient` 必须带 **非 null 的 viewId**。
//
// 为什么：Flutter 的 `_PlatformTextInputControl.attach` 把整个 `TextInputConfiguration.toJson()`
// 发给引擎；引擎（Windows）对 `viewId == null` 的做法是**直接拒绝**：
//   PlatformException(Bad Arguments, Could not set client, view ID is null.)
// 而我们自己 new 的配置没有 viewId（`EditableText` 是显式传 `View.of(context).viewId` 的）。
// 后果：文本输入通道永远接不上 ⇒ Windows 上中文输入法哑掉，且每次点击都刷一串
//   `Set editing state has been invoked, but no client is set`。
//
// 改前（不传 viewId）本测试红；改后绿。

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/editor/text_input_surface.dart';

void main() {
  testWidgets('接上平台文本通道时 viewId 不能是 null', (WidgetTester tester) async {
    final List<MethodCall> calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (MethodCall call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.textInput, null);
    });

    final FocusNode focus = FocusNode();
    addTearDown(focus.dispose);
    final TextInputSurfaceController surface =
        TextInputSurfaceController(focusNode: focus);
    addTearDown(surface.dispose);

    surface.ensureAttached();
    await tester.pump();

    final MethodCall setClient = calls.firstWhere(
      (MethodCall c) => c.method == 'TextInput.setClient',
      orElse: () => throw StateError('没有发出 TextInput.setClient：${calls.map((c) => c.method)}'),
    );

    final List<dynamic> args = setClient.arguments as List<dynamic>;
    final Map<dynamic, dynamic> config = args[1] as Map<dynamic, dynamic>;
    expect(
      config['viewId'],
      isNotNull,
      reason: '引擎会因为 viewId 为 null 拒绝接入（Could not set client, view ID is null.）',
    );
    expect(config['viewId'], isA<int>());
  });
}
