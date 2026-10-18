// ★★ S4-b② 面板「筛选器式」守卫（《界面与布局.md》§4）
//
// 守的是用户 2026-10-17 的原话：
//   「不是给一个大面、放各种类把这个面占满，而是**这个面就当作选择的表格**；
//     上方留出按钮来筛选显示，初始为"全部"……有二级子类的，选那个类时再给一个二级筛选按钮，也是初始"全部"。」
//
// 所以断言里**不许出现页签/tab/返回**这类东西的存在前提，只许有：
//   ① 一个网格（`GridView` 只有一个）；
//   ② 两个下拉筛选（`filter-group` / `filter-subgroup`）；
//   ③ 分类 ∩ 子类**互相收窄**；没有子类的分类 ⇒ 子类按钮**置灰**；
//   ④ 搜索**跨分类**（不受当前筛选限制），清空搜索回到原筛选；
//   ⑤ 搜不到**不静默空手而归**（给相近建议 + 清空入口）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/symbol_library.dart';
import 'package:mathlang/ui/symbol_panel.dart';

import '../support/symbol_fixture.dart';

const double _panelWidth = 8 * 44 + 7 * 6 + 24;

Future<SymbolPanelState> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(600, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final List<SymbolItem> inserted = <SymbolItem>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Row(
        children: <Widget>[
          const Spacer(),
          SymbolPanel(
            library: testSymbolLibrary(),
            onInsert: inserted.add,
          ),
        ],
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return tester.state<SymbolPanelState>(find.byType(SymbolPanel));
}

/// 当前面里有几个格子（= 搜索/筛选之后剩下的项数）
int _cells(WidgetTester tester) => tester
    .widgetList<InkWell>(find.descendant(
      of: find.byType(GridView),
      matching: find.byType(InkWell),
    ))
    .where((InkWell w) => (w.key as ValueKey<String>?)?.value.startsWith('symbol-') ?? false)
    .length;

void main() {
  group('① 面 = 表格（只有一个网格，没有页签/列表页/返回）', () {
    testWidgets('打开时：两个筛选都是"全部"，面里是全部 7 项',
        (WidgetTester tester) async {
      final SymbolPanelState st = await _pump(tester);
      expect(st.group, isNull);
      expect(st.subgroup, isNull);
      expect(find.byType(GridView), findsOneWidget, reason: '面 = 一个表格');
      expect(find.text('共 7 项'), findsOneWidget);
      expect(_cells(tester), 7);
      // 没有子类的分类没选时：子类按钮置灰 ⇒ 不存在可点的 `filter-subgroup`
      expect(find.byKey(const Key('filter-subgroup')), findsNothing);
    });

    testWidgets('面板宽 = 格数推算（不写死）', (WidgetTester tester) async {
      await _pump(tester);
      expect(tester.getSize(find.byType(SymbolPanel)).width, _panelWidth);
    });
  });

  group('② 分类筛选（一级只有 结构 / 符号）', () {
    testWidgets('选「结构」⇒ 只剩 2 项，且子类按钮仍置灰', (WidgetTester tester) async {
      final SymbolPanelState st = await _pump(tester);
      st.setGroup('结构');
      await tester.pumpAndSettle();
      expect(st.visibleItems().length, 2, reason: '结构 = 分式 / 根号');
      expect(find.byKey(const Key('filter-subgroup')), findsNothing,
          reason: '「结构」没有子类 ⇒ 子类按钮置灰（不出现可点的下拉）');
    });

    testWidgets('选「符号」⇒ 5 项，且出现子类下拉', (WidgetTester tester) async {
      final SymbolPanelState st = await _pump(tester);
      st.setGroup('符号');
      await tester.pumpAndSettle();
      expect(st.visibleItems().length, 5);
      expect(find.byKey(const Key('filter-subgroup')), findsOneWidget);
      expect(st.subgroupOptions, <String>['希腊', '运算', '关系'],
          reason: '子类顺序 = JSON 里第一次出现的顺序');
    });

    testWidgets('★ 换分类 ⇒ 子类自动回"全部"（不出现"结构 ▸ 希腊"这种组合）',
        (WidgetTester tester) async {
      final SymbolPanelState st = await _pump(tester);
      st.setGroup('符号');
      st.setSubgroup('希腊');
      await tester.pumpAndSettle();
      expect(st.visibleItems().length, 2);
      st.setGroup('结构');
      await tester.pumpAndSettle();
      expect(st.subgroup, isNull);
      expect(st.visibleItems().length, 2);
    });
  });

  group('③ 分类 ∩ 子类 互相收窄', () {
    testWidgets('符号 ▸ 希腊 ⇒ 阿尔法 / 德尔塔', (WidgetTester tester) async {
      final SymbolPanelState st = await _pump(tester);
      st.setGroup('符号');
      st.setSubgroup('希腊');
      await tester.pumpAndSettle();
      expect(st.visibleItems().map((SymbolItem i) => i.id).toSet(),
          <String>{'alpha', 'delta'});
      expect(find.byKey(const Key('symbol-alpha')), findsOneWidget);
      expect(find.byKey(const Key('symbol-sum')), findsNothing);
    });

    testWidgets('★ 一项多类（alsoIn）：求和能从「运算」和「逻辑集合」两处找到',
        (WidgetTester tester) async {
      final SymbolLibrary lib = testSymbolLibrary();
      expect(lib.inCategory(group: '符号', subgroup: '运算').map((SymbolItem i) => i.id),
          contains('sum'));
      expect(
          lib
              .inCategory(group: '符号', subgroup: '逻辑集合')
              .map((SymbolItem i) => i.id),
          contains('sum'));
    });
  });

  group('④ 搜索优先于筛选', () {
    testWidgets('停在「希腊」下搜"求和" ⇒ 仍能搜到（跨分类），清空后回希腊',
        (WidgetTester tester) async {
      final SymbolPanelState st = await _pump(tester);
      st.setGroup('符号');
      st.setSubgroup('希腊');
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('symbol-search')), '求和');
      await tester.pumpAndSettle();
      expect(st.searching, isTrue);
      expect(find.byKey(const Key('symbol-sum')), findsOneWidget,
          reason: '★ 搜索跨分类，不受当前筛选限制');

      await tester.enterText(find.byKey(const Key('symbol-search')), '');
      await tester.pumpAndSettle();
      expect(st.visibleItems().length, 2, reason: '清空查询 ⇒ 回到原来的筛选');
    });

    testWidgets('关键词命中（"判别式" ⇒ 德尔塔；"批量" ⇒ 求和）',
        (WidgetTester tester) async {
      final SymbolLibrary lib = testSymbolLibrary();
      expect(lib.search('判别式').first.item.id, 'delta');
      expect(lib.search('批量').first.item.id, 'sum');
    });
  });

  group('⑤ 空态：绝不静默空手而归', () {
    testWidgets('搜不到 ⇒ 有标题 + 清空入口', (WidgetTester tester) async {
      await _pump(tester);
      await tester.enterText(find.byKey(const Key('symbol-search')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('empty-title')), findsOneWidget);
      expect(find.byKey(const Key('empty-clear')), findsOneWidget);
    });

    testWidgets('★ 打了短语 ⇒ 给相近建议（缩短查询再搜）', (WidgetTester tester) async {
      await _pump(tester);
      // "阿尔法的平方" 没有直接命中，但缩短到 "阿尔法" 有
      await tester.enterText(find.byKey(const Key('symbol-search')), '阿尔法的平方');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('empty-suggestions')), findsOneWidget,
          reason: '★ 有相近项时必须给建议（否则用户只能猜）');
      expect(find.byKey(const Key('suggest-alpha')), findsOneWidget);
    });
  });

  group('⑥ 点格子 ⇒ 回调（插入语义在外壳）', () {
    testWidgets('点「分式」⇒ onInsert 收到 frac', (WidgetTester tester) async {
      final List<SymbolItem> got = <SymbolItem>[];
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: <Widget>[
            const Spacer(),
            SymbolPanel(library: testSymbolLibrary(), onInsert: got.add),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('symbol-frac')));
      await tester.pumpAndSettle();
      expect(got.single.id, 'frac');
    });
  });
  group('⑦ 长按 = 真预览（b1 只有小 tooltip）', () {
    testWidgets('长按「分段」⇒ 浮层里有大图 + LaTeX + 插入按钮',
        (WidgetTester tester) async {
      await _pump(tester);
      await tester.longPress(find.byKey(const Key('symbol-frac')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('symbol-preview-frac')), findsOneWidget);
      expect(find.text(r'\frac{}{}'), findsOneWidget,
          reason: '浮层里要能看见真实源码（可选中复制）');
      expect(find.byKey(const Key('symbol-preview-insert-frac')), findsOneWidget);

      await tester.tap(find.byKey(const Key('symbol-preview-insert-frac')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('symbol-preview-frac')), findsNothing,
          reason: '插入后浮层要关掉');
    });

    testWidgets('★ `preview` 字段：分段/对齐推导画的是**代表式**（不是一对空花括号）',
        (WidgetTester tester) async {
      final SymbolLibrary lib = testSymbolLibrary();
      expect(lib.byId('frac')!.previewTex, r'\frac{}{}',
          reason: '没有 preview 的项回落到 tex 本身');
    });
  });
}