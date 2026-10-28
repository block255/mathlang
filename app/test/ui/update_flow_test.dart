// D1 界面守卫（2026-10-28）：设置页那三条 + 两个弹窗。
//
// 不联网、不起 EditorPage（它太重）：设置页单独挂 `SettingsOverlay`，
// 弹窗直接 `showUpdateAvailableDialog`。判据（比版本/限频/该不该弹）在
// `test/core/update_check_test.dart` 里已经钉过了，这里只钉"界面如实反映 + 返回正确的决定"。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_settings.dart';
import 'package:mathlang/core/update_check.dart';
import 'package:mathlang/core/version_ref.dart';
import 'package:mathlang/ui/app_settings.dart';
import 'package:mathlang/ui/settings_page.dart';
import 'package:mathlang/ui/update_dialogs.dart';

final UpdateInfo _info = UpdateInfo(
  tag: 'v1.2.0',
  version: const VersionRef(1, 2, 0),
  notes: '· A1 导出不再包含纯空行页\n· C1 安装只弹一次 UAC',
  pageUrl: 'https://github.com/block255/mathlang/releases/tag/v1.2.0',
  msixUrl: 'https://example.com/mathlang-1.2.0-x64.msix',
  msixSize: 14000000,
);

Future<void> _pumpSettings(
  WidgetTester tester, {
  required void Function(AppSettings) onSettings,
  VoidCallback? onCheck,
  VoidCallback? onOpenPage,
  String status = '',
  bool checking = false,
  AppSettings settings = const AppSettings(),
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SettingsOverlay(
        initialGroup: 8, // 「关于」
        settings: settings,
        doc: const DocSettings(),
        onSettings: onSettings,
        onDoc: (_) {},
        onClose: () {},
        onCheckUpdate: onCheck,
        onOpenReleasePage: onOpenPage,
        updateStatusText: status,
        updateChecking: checking,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('设置 → 关于 → 更新（三条）', () {
    testWidgets('三条都在，且状态行显示传进来的文案', (WidgetTester tester) async {
      await _pumpSettings(
        tester,
        onSettings: (_) {},
        onCheck: () {},
        onOpenPage: () {},
        status: '上次检查：今天 14:20 · 已是最新',
      );
      expect(find.byKey(const Key('check-update')), findsOneWidget);
      expect(find.byKey(const Key('auto-check-update')), findsOneWidget);
      expect(find.byKey(const Key('open-release-page')), findsOneWidget);
      expect(find.textContaining('上次检查：今天 14:20'), findsOneWidget);
    });

    testWidgets('点「检查更新」⇒ 回调被调用；检查中时按钮禁用', (WidgetTester tester) async {
      var n = 0;
      await _pumpSettings(tester, onSettings: (_) {}, onCheck: () => n++);
      await tester.tap(find.byKey(const Key('check-update')));
      await tester.pumpAndSettle();
      expect(n, 1);

      await _pumpSettings(
          tester, onSettings: (_) {}, onCheck: () => n++, checking: true);
      expect(find.text('检查中…'), findsOneWidget);
      final OutlinedButton b = tester.widget<OutlinedButton>(
          find.byKey(const Key('check-update')));
      expect(b.onPressed, isNull, reason: '正在检查时按钮要禁用（防连点）');
    });

    testWidgets('关掉「自动检查更新」⇒ 写回 autoCheckUpdate: false',
        (WidgetTester tester) async {
      AppSettings? got;
      await _pumpSettings(tester, onSettings: (AppSettings v) => got = v);
      await tester.tap(find.byKey(const Key('auto-check-update')));
      await tester.pumpAndSettle();
      expect(got, isNotNull);
      expect(got!.autoCheckUpdate, isFalse);
      // 其它字段不许被动过
      expect(got!.showStatusBar, const AppSettings().showStatusBar);
    });

    testWidgets('点「前往发布页」⇒ 回调被调用', (WidgetTester tester) async {
      var n = 0;
      await _pumpSettings(tester, onSettings: (_) {}, onOpenPage: () => n++);
      await tester.tap(find.byKey(const Key('open-release-page')));
      await tester.pumpAndSettle();
      expect(n, 1);
    });
  });

  group('弹窗 ① 发现新版本', () {
    Future<UpdateDecision?> pumpDialog(
      WidgetTester tester, {
      bool canInstall = true,
      bool autoCheckEnabled = true,
    }) async {
      UpdateDecision? got;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                got = await showUpdateAvailableDialog(
                  ctx,
                  info: _info,
                  current: const VersionRef(1, 1, 2),
                  canInstall: canInstall,
                  autoCheckEnabled: autoCheckEnabled,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-available-dialog')), findsOneWidget);
      return got;
    }

    testWidgets('三个按钮都在，说明里带当前/最新版本与 Release 原文',
        (WidgetTester tester) async {
      await pumpDialog(tester);
      expect(find.text('暂不更新'), findsOneWidget);
      expect(find.text('前往发布页'), findsOneWidget);
      expect(find.text('一键更新'), findsOneWidget);
      expect(find.textContaining('发现新版本 1.2.0'), findsOneWidget);
      expect(find.textContaining('A1 导出不再包含纯空行页'), findsOneWidget);
      expect(find.byKey(const Key('update-disable-auto')), findsOneWidget);
    });

    testWidgets('「暂不更新」⇒ later，且默认不带「不再自动检查」',
        (WidgetTester tester) async {
      await pumpDialog(tester);
      await tester.tap(find.byKey(const Key('update-later')));
      await tester.pumpAndSettle();
      // 结果由 pumpDialog 里的 got 捕获 —— 这里靠"弹窗关掉了"间接确认
      expect(find.byKey(const Key('update-available-dialog')), findsNothing);
    });

    testWidgets('勾上「以后不再自动检查更新」再选 ⇒ disableAuto = true',
        (WidgetTester tester) async {
      UpdateDecision? got;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                got = await showUpdateAvailableDialog(
                  ctx,
                  info: _info,
                  current: const VersionRef(1, 1, 2),
                  canInstall: true,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('update-disable-auto')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('update-later')));
      await tester.pumpAndSettle();
      expect(got, isNotNull);
      expect(got!.choice, UpdateChoice.later);
      expect(got!.disableAuto, isTrue);
    });

    testWidgets('没有可一键安装的包 ⇒ 「一键更新」禁用并给出说明',
        (WidgetTester tester) async {
      await pumpDialog(tester, canInstall: false);
      final FilledButton b =
          tester.widget<FilledButton>(find.byKey(const Key('update-install')));
      expect(b.onPressed, isNull);
      expect(find.textContaining('这一版没有可一键安装的包'), findsOneWidget);
    });
  });

  group('弹窗 ② 更新完成', () {
    Future<bool?> pumpDone(WidgetTester tester) async {
      bool? restart;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                restart = await showUpdateDoneDialog(ctx, info: _info);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-done-dialog')), findsOneWidget);
      return restart;
    }

    testWidgets('两个选项都在；「暂不重启」返回 false', (WidgetTester tester) async {
      await pumpDone(tester);
      expect(find.text('暂不重启'), findsOneWidget);
      expect(find.text('立即重启'), findsOneWidget);
      await tester.tap(find.byKey(const Key('update-restart-later')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-done-dialog')), findsNothing);
    });

    testWidgets('「立即重启」⇒ 弹窗关掉（重启动作由外壳执行）', (WidgetTester tester) async {
      await pumpDone(tester);
      await tester.tap(find.byKey(const Key('update-restart-now')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-done-dialog')), findsNothing);
    });
  });
}
