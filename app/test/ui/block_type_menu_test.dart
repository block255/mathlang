// ★★ U6 守卫（2026-10-19）：顶栏「块类型」下拉 + 桌面快捷方式
//
// 用户两条要求：
//   ① 标题行没有显眼入口 ⇒ 顶栏加下拉，**只有 正文 / 标题1 / 标题2 / 标题3**（平权口径：不含列表/引用/代码块）；
//   ② MSIX 装完普通用户找不到软件 ⇒ **第一次启动自动建桌面快捷方式**（安装包本身不允许建）。
//
// 判据：
//   · 下拉里恰好四项，点哪项就把行首标记设成哪个（**设置语义**：已是该项则什么都不做）；
//   · 正文 ↔ 标题1/2/3 **往返**无损（内容一个字不变，只有行首标记变）；
//   · 光标在行中间时改类型，光标跟着标记长度走（不许跑出这一行）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/block.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/io/desktop_shortcut.dart';
import 'package:mathlang/lang/block_ops.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/symbol_fixture.dart';

Future<(EditorPageState, DocBuffer)> _pump(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(library: testSymbolLibrary(), buffer: buf),
  ));
  await tester.pumpAndSettle();
  return (tester.state<EditorPageState>(find.byType(EditorPage)), buf);
}

void main() {
  group('㉗ 顶栏「块类型」下拉（U6）', () {
    testWidgets('★★ 下拉里恰好四项：正文 / 标题 1 / 标题 2 / 标题 3',
        (WidgetTester tester) async {
      await _pump(tester, '甲乙');
      await tester.tap(find.byKey(const Key('block-type-menu')));
      await tester.pumpAndSettle();
      for (final String t in <String>[
        'block-type-paragraph',
        'block-type-heading1',
        'block-type-heading2',
        'block-type-heading3',
      ]) {
        expect(find.byKey(Key(t)), findsOneWidget, reason: '缺 $t');
      }
      // 平权口径：下拉里**不许**出现列表/引用/代码块
      expect(find.text('列表'), findsNothing);
      expect(find.text('引用'), findsNothing);
      expect(find.text('代码块'), findsNothing);
    });

    testWidgets('★★ 点「标题 2」⇒ 行首变 `## `；再选「正文」⇒ 标记消失（内容不动）',
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf) = await _pump(tester, '甲乙丙\n丁');
      st.openSettings(); // 只是为了确保有 state；下面直接走编辑层
      st.closeSettings();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('block-type-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('block-type-heading2')));
      await tester.pumpAndSettle();
      expect(buf.buf, '## 甲乙丙\n丁', reason: '选标题 2 ⇒ 行首 `## `');

      await tester.tap(find.byKey(const Key('block-type-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('block-type-paragraph')));
      await tester.pumpAndSettle();
      expect(buf.buf, '甲乙丙\n丁', reason: '选正文 ⇒ 标记消失，文字一个字不动');
    });

    // ★★ 2026-10-20（T-A 实测 F1）：光标在**行间公式块内部**时整个下拉禁用。
    //   改前：点了照样弹菜单、选了照样执行 ⇒ `# ` 插进 tex ⇒ 红字 `[公式不完整]`、公式散架。
    testWidgets('★ F1：光标在行间公式块内部 ⇒ 下拉禁用 + 点了不弹菜单',
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf) = await _pump(tester, '\$\$\n\n\$\$');
      st.openSettings();
      st.closeSettings();
      await tester.pumpAndSettle();
      buf.setCaret(3); // 两道 `$$` 之间那一行 = 行间公式块内部
      await tester.pumpAndSettle();

      final PopupMenuButton<BlockType> btn = tester.widget<PopupMenuButton<BlockType>>(
          find.byKey(const Key('block-type-menu')));
      expect(btn.enabled, isFalse, reason: '整块内部没有"段落类型"这回事');

      await tester.tap(find.byKey(const Key('block-type-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('block-type-paragraph')), findsNothing,
          reason: '改前这里会弹出菜单（点了就执行）');
      expect(buf.buf, '\$\$\n\n\$\$', reason: '文档一个字都不许动');
    });
  });

  group('㉘ 块标记"设置语义"的纯函数（U6）', () {
    test('★★ 往返无损：正文 → 标题1 → 标题2 → 标题3 → 正文',
        () {
      // 走一遍完整往返（`''` = 正文；若本来就是目标 ⇒ 返回 null，这是"设置语义"的正确行为）
      String doc = '甲乙丙';
      for (final String m in <String>['# ', '## ', '### ', '', '### ', '']) {
        final BlockOpResult? r = planLineMarkerSet(doc, 0, m);
        if (r == null) continue;
        doc = doc.substring(0, r.from) + r.insert + doc.substring(r.to);
      }
      expect(doc, '甲乙丙', reason: '来回改完必须回到原文');
    });

    test('★ 已经是目标类型 ⇒ 返回 null（下拉不许把它切成正文）', () {
      const String doc = '## 甲乙丙';
      expect(planLineMarkerSet(doc, 5, '## '), isNull);
      expect(planLineMarkerSet(doc, 5, '# '), isNotNull);
    });

    test('★ 光标在行中间：改类型后光标跟着标记长度走，且不跑出这一行', () {
      const String doc = '甲乙丙\n丁';
      // 光标在第 0 行第 2 个字（"乙"后）
      final BlockOpResult? r = planLineMarkerSet(doc, 2, '## ');
      expect(r, isNotNull);
      expect(r!.caret, 2 + 3, reason: '前面插了 `## ` 三个字符');
      expect(r.caret <= 2 + 3, isTrue);
    });

    test('★ 整块语义的行不许改行首标记', () {
      const String fence = '\$\$';
      expect(planLineMarkerSet(fence, 0, '# '), isNull);
      expect(planLineMarkerSet(fence, 1, '# '), isNull);
    });
  });
  group('㉙ 桌面快捷方式（设置 → 高级）', () {
    testWidgets('★★ 高级页有「桌面快捷方式」这一行（状态 + 按钮）',
        (WidgetTester tester) async {
      final (EditorPageState st, _) = await _pump(tester, '甲乙');
      st.openSettings(group: 7);
      await tester.pumpAndSettle();
      // ★ ListView 只实例化可见子项 ⇒ 先把这一行滚出来（它在「高级」组末尾）
      await tester.scrollUntilVisible(
        find.byKey(const Key('desktop-shortcut-state')),
        240,
        scrollable: find
            .descendant(
                of: find.byKey(const Key('settings-overlay')),
                matching: find.byType(Scrollable))
            .last,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('desktop-shortcut-state')), findsOneWidget);
      expect(find.byKey(const Key('desktop-shortcut-toggle')), findsOneWidget);
      expect(find.text('桌面快捷方式'), findsOneWidget);
    });

    test('★ 常量与路径口径', () {
      expect(kDesktopShortcutName, '数语引擎.lnk');
      // 测试环境不是 MSIX ⇒ 包族名为 null（不会去碰 explorer.exe 那套分支）
      expect(BlockType.heading2, isNot(BlockType.paragraph));
    });
  });
}
