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

    testWidgets('四个按钮都在，说明里带当前/最新版本与 Release 原文',
        (WidgetTester tester) async {
      await pumpDialog(tester);
      // ★ 2026-10-28 晚：两个"不更"的理由必须**分开且都可见**
      expect(find.text('暂不更新'), findsOneWidget);
      expect(find.text('忽略此版本'), findsOneWidget);
      expect(find.text('前往发布页'), findsOneWidget);
      expect(find.text('一键更新'), findsOneWidget);
      expect(find.textContaining('发现新版本 1.2.0'), findsOneWidget);
      expect(find.textContaining('A1 导出不再包含纯空行页'), findsOneWidget);
      expect(find.byKey(const Key('update-disable-auto')), findsOneWidget);
    });

    testWidgets('「暂不更新」⇒ later（只关这次，什么都不记）',
        (WidgetTester tester) async {
      await pumpDialog(tester);
      await tester.tap(find.byKey(const Key('update-later')));
      await tester.pumpAndSettle();
      // 结果由 pumpDialog 里的 got 捕获 —— 这里靠"弹窗关掉了"间接确认
      expect(find.byKey(const Key('update-available-dialog')), findsNothing);
    });

    testWidgets('「忽略此版本」⇒ ignoreVersion（与 later 是两回事）',
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
      await tester.tap(find.byKey(const Key('update-ignore-version')));
      await tester.pumpAndSettle();
      expect(got, isNotNull);
      expect(got!.choice, UpdateChoice.ignoreVersion);
      expect(got!.disableAuto, isFalse, reason: '忽略一个版本 ≠ 关掉自动检查');
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

  group('弹窗 ② 下载进度 / 安装确认（一个窗口两态）', () {
    Future<void> pumpProgress(
      WidgetTester tester,
      ValueNotifier<DownloadUiState> st,
    ) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showUpdateDownloadDialog(ctx,
                  info: _info, state: st, onCancelDownload: () {}),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
    }

    testWidgets('下载中：进度条 + 已下/总量 + 「取消」', (WidgetTester tester) async {
      final ValueNotifier<DownloadUiState> st = ValueNotifier<DownloadUiState>(
          const DownloadUiState(got: 5 * 1024 * 1024, total: 14 * 1024 * 1024));
      addTearDown(st.dispose);
      await pumpProgress(tester, st);
      expect(find.byKey(const Key('update-progress-bar')), findsOneWidget);
      expect(find.textContaining('5.0 / 14.0 MB'), findsOneWidget);
      expect(find.byKey(const Key('update-cancel-download')), findsOneWidget);
    });

    testWidgets('下载完 ⇒ 同一窗口变成"准备安装"，两个按钮', (WidgetTester tester) async {
      final ValueNotifier<DownloadUiState> st =
          ValueNotifier<DownloadUiState>(const DownloadUiState());
      addTearDown(st.dispose);
      await pumpProgress(tester, st);
      st.value = st.value.copyWith(
          phase: DownloadPhase.ready, got: 14 * 1024 * 1024, path: r'C:\t\x.msix');
      await tester.pumpAndSettle();
      expect(find.textContaining('准备安装'), findsOneWidget);
      expect(find.textContaining('关闭本程序'), findsOneWidget);
      expect(find.byKey(const Key('update-install-now')), findsOneWidget);
      expect(find.byKey(const Key('update-install-later')), findsOneWidget);
    });

    testWidgets('下载失败 ⇒ 显示**真实原因** + 去发布页', (WidgetTester tester) async {
      final ValueNotifier<DownloadUiState> st =
          ValueNotifier<DownloadUiState>(const DownloadUiState());
      addTearDown(st.dispose);
      await pumpProgress(tester, st);
      st.value = st.value.copyWith(
          phase: DownloadPhase.failed, error: '连接被拒绝 —— 本机 127.0.0.1 上没有代理在应答');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-failed-reason')), findsOneWidget);
      expect(find.textContaining('连接被拒绝'), findsOneWidget);
      expect(find.byKey(const Key('update-open-page')), findsOneWidget);
    });
  });

  group('弹窗 ③ 已更新 / ④ 上次没装成', () {
    testWidgets('已更新：显示版本与更新说明', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Center(
            child: ElevatedButton(
              onPressed: () =>
                  showUpdateInstalledDialog(ctx, version: '1.2.0', notes: '· 修了 A'),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-installed-dialog')), findsOneWidget);
      expect(find.textContaining('已更新到 1.2.0'), findsOneWidget);
      expect(find.textContaining('修了 A'), findsOneWidget);
    });

    testWidgets('上次没装成：显示原因 + **安装包路径** + 复制按钮', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showUpdateFailedDialog(
                ctx,
                reason: '0x80073D02 资源正在使用中',
                currentVersion: '1.1.2',
                msixPath: r'C:\Users\me\AppData\Local\Temp\mathlang-update-1.2.0.msix',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-failed-dialog')), findsOneWidget);
      expect(find.byKey(const Key('update-failed-msix-path')), findsOneWidget);
      expect(find.textContaining('mathlang-update-1.2.0.msix'), findsOneWidget);
      await tester.tap(find.byKey(const Key('update-failed-copy-path')));
      await tester.pumpAndSettle();
      // ★ 这里不断言那条 snack：剪贴板在测试里没有平台实现，而且 snack 需要一个
      //   Scaffold 才能上屏（本用例的 home 没套 Scaffold）。只断言"点了不炸"。
      expect(tester.takeException(), isNull);
    });
  });
}
