// ★★★ U1 守卫：设置页「高级」栏 ＋ 界面里不许出现内部批次号（2026-10-19）
//
// 用户 2026-10-19 的三条要求：
//   ① `/` → 分式 已经归到「快捷键」，**智能输入里不许再重复给开关**；
//   ② 设置页「高级」要有个说法（原来是空壳）：诊断清单 / 诊断信息 / 只读源码 / 本地暂存；
//   ③ **界面里不许出现 S4c / S4e / S5 这种阶段号**（用户："我们的界面内不应出现…草稿了"）。
//
// 另外两条口径（用户同日拍板）：
//   · 源码只做**只读全文浮层**（可编辑版留 S6 之后，记账）；
//   · 「清除本地暂存」**二次确认**（它连带清掉设置 ⇒ 必须把后果写清楚）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/app_info.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/lang/shortcut_registry.dart';
import 'package:mathlang/ui/editor_page.dart';
import 'package:mathlang/ui/settings_page.dart';

import '../support/symbol_fixture.dart';

/// 正文里带一段行内公式，顺便验证"源码浮层给的是逐字原文"
const String kDoc = '甲乙丙丁\n\n第二段 ' r'$\frac{a}{b}=1$' ' 收尾';

Future<({EditorPageState state, DocBuffer buffer})> _pump(
  WidgetTester tester, {
  int group = 7,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(kDoc)..setCaret(2);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(library: testSymbolLibrary(), buffer: buf),
  ));
  await tester.pumpAndSettle();
  final EditorPageState st =
      tester.state<EditorPageState>(find.byType(EditorPage));
  st.openSettings(group: group);
  await tester.pumpAndSettle();
  return (state: st, buffer: buf);
}

/// 设置卡片里所有可见文本（含可选中文本）
String _allText(WidgetTester tester) {
  final StringBuffer sb = StringBuffer();
  for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
    final String? s = t.data ?? t.textSpan?.toPlainText();
    if (s != null) sb.writeln(s);
  }
  for (final SelectableText t
      in tester.widgetList<SelectableText>(find.byType(SelectableText))) {
    if (t.data != null) sb.writeln(t.data);
  }
  return sb.toString();
}

void main() {
  group('㉒ 高级栏：诊断 / 源码 / 暂存（U1）', () {
    testWidgets('★★ 高级组里有四块入口（诊断清单 / 诊断信息 / 查看源码 / 清除暂存）',
        (WidgetTester tester) async {
      await _pump(tester, group: 7);
      expect(find.byKey(const Key('advanced-diagnostics')), findsOneWidget);
      expect(find.byKey(const Key('advanced-diagnostics-text')), findsOneWidget);
      expect(find.byKey(const Key('advanced-copy-diagnostics')), findsOneWidget);
      expect(find.byKey(const Key('advanced-source')), findsOneWidget);
      expect(find.byKey(const Key('session-path')), findsOneWidget,
          reason: '暂存位置仍在（原来就有）');
      expect(find.byKey(const Key('session-clear')), findsOneWidget);
    });

    testWidgets('★★ 诊断信息含版本 / 平台 / 页面几何（能粘给开发者定位问题）',
        (WidgetTester tester) async {
      await _pump(tester, group: 7);
      final SelectableText t = tester.widget<SelectableText>(
          find.byKey(const Key('advanced-diagnostics-text')));
      final String s = t.data ?? '';
      expect(s, contains(kAppVersion), reason: '诊断信息要有完整版本（含构建号 +1）');
      expect(s, contains('正文宽'), reason: '要有正文宽（657.6 那条不变量）');
      expect(s, contains('页'), reason: '要有页数');
      expect(s, contains('暂存'), reason: '要有暂存位置');
      expect(s, contains(kMathEngine), reason: '要有渲染引擎版本');
    });

    testWidgets('★★ 「复制诊断信息」真的写进剪贴板', (WidgetTester tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await _pump(tester, group: 7);
      await tester.tap(find.byKey(const Key('advanced-copy-diagnostics')));
      await tester.pumpAndSettle();
      expect(copied, isNotNull, reason: '按了复制就要写剪贴板');
      expect(copied, contains(kAppVersion));
    });

    testWidgets('★★ 「查看源码」打开**只读**浮层，内容就是文档原文',
        (WidgetTester tester) async {
      await _pump(tester, group: 7);
      await tester.tap(find.byKey(const Key('advanced-source')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('source-dialog')), findsOneWidget);
      final SelectableText t =
          tester.widget<SelectableText>(find.byKey(const Key('source-text')));
      expect(t.data, kDoc, reason: '浮层里必须逐字是那份源码');
      expect(
          find.descendant(
              of: find.byKey(const Key('source-dialog')),
              matching: find.byType(TextField)),
          findsNothing,
          reason: '只读 ⇒ 浮层里不许有输入框');
      await tester.tap(find.byKey(const Key('source-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('source-dialog')), findsNothing);
    });

    testWidgets('★★ 「清除本地暂存」要二次确认；取消不生效、确认才清',
        (WidgetTester tester) async {
      final ({EditorPageState state, DocBuffer buffer}) r =
          await _pump(tester, group: 7);
      final String before = r.buffer.buf;
      // ① 点清除 ⇒ 出确认框
      await tester.tap(find.byKey(const Key('session-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('session-clear-confirm')), findsOneWidget);
      final String dialogText = _allText(tester);
      expect(dialogText, contains('恢复出厂'),
          reason: '确认框必须说清"设置也会被清掉"（不然用户以为只清内容）');
      expect(dialogText, contains('.md'),
          reason: '还要说清"已保存的 .md 文件不受影响"');
      // ② 取消 ⇒ 什么都不变
      await tester.tap(find.byKey(const Key('session-clear-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('session-clear-confirm')), findsNothing);
      expect(r.buffer.buf, before, reason: '取消 ⇒ 一个字都不该动');
      // ③ 确认 ⇒ 走到清除（确认框关闭即可）
      await tester.tap(find.byKey(const Key('session-clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('session-clear-ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('session-clear-confirm')), findsNothing);
    });
  });

  group('㉓ 界面里不许出现内部批次号（用户 2026-10-19）', () {
    testWidgets('★★ 九组**全部**都点得开，且没有 S3/S4/S5/阶段/待接入 字样',
        (WidgetTester tester) async {
      final ({EditorPageState state, DocBuffer buffer}) r =
          await _pump(tester, group: 0);
      for (var g = 0; g < kSettingGroups.length; g++) {
        r.state.openSettings(group: g);
        await tester.pumpAndSettle();
        final String text = _allText(tester);
        for (final String bad in <String>['S3', 'S4', 'S5', '阶段', '待接入', 'b2-']) {
          final Iterable<String> hits =
              text.split('\n').where((String l) => l.contains(bad));
          expect(hits, isEmpty,
              reason: '第 $g 组（${kSettingGroups[g].title}）里出现了内部字样 '
                  '"$bad"：${hits.join(" / ")}');
        }
      }
    });

    testWidgets('★ 「关于」写的是真版本与真平台（不是"web / android"那种想当然）',
        (WidgetTester tester) async {
      await _pump(tester, group: 8);
      final SelectableText t =
          tester.widget<SelectableText>(find.byKey(const Key('about-version')));
      final String s = t.data ?? '';
      // ★★ U2：**关于只显示版本名**（1.0.0），构建号 +1 留给诊断信息
      expect(s, contains(kAppVersionName));
      expect(s, isNot(contains('+')), reason: '关于页不显示构建号（用户问过 +1 是什么）');
      expect(s, contains(kMathEngine));
      expect(s, isNot(contains('web / android')));
    });
  });

  group('㉔ 斜杠去重：只留「快捷键」一条', () {
    testWidgets('★★ 智能输入里**没有**斜杠的开关了（auto-slash 已删）',
        (WidgetTester tester) async {
      await _pump(tester, group: 6);
      expect(find.byKey(const Key('auto-slash')), findsNothing,
          reason: '用户要求：斜杠已经归到快捷键，智能输入里不许重复给开关');
      expect(find.byKey(const Key('auto-word')), findsOneWidget,
          reason: '词触发仍在智能输入里');
      expect(find.byKey(const Key('auto-shorthand')), findsOneWidget,
          reason: '符号缩写仍在智能输入里');
    });

    testWidgets('★★ 开关在快捷键表里（typeFracKey，名字写明是"自动展开"）',
        (WidgetTester tester) async {
      final ShortcutSettings s = ShortcutSettings.defaults();
      final ShortcutAction? a = s.actionOf('typeFracKey');
      expect(a, isNotNull, reason: '斜杠变分式必须在快捷键表里（那是它唯一的开关）');
      expect(a!.combo, '/');
      expect(a.name, contains('自动展开'),
          reason: '名字要说明"停用即关闭、改键不生效"，否则用户会去改键');
      expect(s.actionOf('typeSup')!.name, contains('自动展开'),
          reason: '上标（打字 ^）同一口径');
    });
  });
}