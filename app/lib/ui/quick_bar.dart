// 数语引擎 · **快捷栏**（= 收藏；独立组件，在面板**上方**）（S4-b②）
//
// 规格：《界面与布局.md》**§5** —— 用户 2026-10-17 原话：
//   「**收藏也就是快捷栏**……它跟其他类并不是并列的，而是**放在选择面板的上方独立显示**；
//     不管选择面板选哪个类，这个快捷栏都在上面显示着。」
//
// 五条规矩：
//   ① **8 格**（= 面板一排的格数，同一常量可调）；**不随筛选变化**，永远是这 8 格；
//   ② **赋值**：先点某个栏位"选中" ⇒ 再点面板里任意符号 ⇒ 放进该格；`Esc` 取消；**长按清空**；
//      ★★ 2026-10-18 晚（用户提出）：**右键 = 编辑这一格（换掉）**。
//      左键在"有内容的格"上是**插入**（每天最常用的动作，不能动），
//      于是"想换掉第 3 格"原来只有"先长按清空、再左键进赋值"这一条绕路
//      ⇒ 右键直接进赋值模式（空位也一样：统一成"右键 = 我要编辑这一格"）。
//   ③ **使用**：点格子插入，或 `Alt+1..8`（不管面板开没开）；
//   ④ 与面板**各有自己的收起/拉出按钮**（开关在顶栏，见 `editor_page.dart`）；
//   ⑤ 数据 = `AppSettings.favorites`（`null` = 空格，**空位就是快捷栏的空格**）。

import 'package:flutter/material.dart';

import '../lang/symbol_library.dart';
import 'app_settings.dart';
import 'symbol_panel.dart' show symbolPreview;

class QuickBar extends StatelessWidget {
  const QuickBar({
    super.key,
    required this.library,
    required this.settings,
    required this.onTapSlot,
    required this.onClearSlot,
    required this.onAssignSlot,
    this.assignSlot,
    this.highlightSlot,
    this.placement = QuickBarPlacement.abovePanel,
  });

  final SymbolLibrary library;
  final AppSettings settings;

  /// 点第 i 格：空格 ⇒ 进入赋值模式；有内容 ⇒ 插入
  final void Function(int index) onTapSlot;

  /// 长按清空
  final void Function(int index) onClearSlot;

  /// ★ 右键 ⇒ **换掉**这一格（进赋值模式；空位/有内容都一样）
  final void Function(int index) onAssignSlot;

  /// 赋值模式的目标格（`null` = 不在赋值模式）
  final int? assignSlot;

  /// ★★ U2（2026-10-21）：**键盘焦点环**（当前用键盘选中的格号；`null` = 没有焦点）
  final int? highlightSlot;
  final QuickBarPlacement placement;

  /// 一格边长（与面板同一常量）
  double get cell => settings.cellSize;

  @override
  Widget build(BuildContext context) {
    final List<Widget> cells = <Widget>[
      for (var i = 0; i < settings.quickBarSlots; i++) _cell(context, i),
    ];
    final Widget row = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: LayoutMetrics.panelPadding),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < cells.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i == cells.length - 1 ? 0 : LayoutMetrics.cellGap),
              child: cells[i],
            ),
        ],
      ),
    );
    return SizedBox(
      key: const Key('quick-bar'),
      width: LayoutMetrics.panelWidth(settings.quickBarSlots,
          cell: settings.cellSize),
      child: Material(
        color: const Color(0xFFFFFFFF),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: LayoutMetrics.quickBarHeight,
              child: Center(child: row),
            ),
            if (assignSlot != null)
              Container(
                key: const Key('quick-assign-hint'),
                color: const Color(0xFFFFF3CD),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  '点面板里一个符号 ⇒ 放进第 ${assignSlot! + 1} 格 · Esc 取消',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF8A6100)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, int i) {
    final String? id = settings.favoriteAt(i);
    final SymbolItem? item = id == null ? null : library.byId(id);
    final bool hot = assignSlot == i;
    final bool kb = highlightSlot == i; // ★ U2：键盘焦点环
    return Tooltip(
      message: item == null
          ? '第 ${i + 1} 格（空）· 点一下再选符号'
          : '${item.label} · Alt+${i + 1} 插入 · 右键换掉 · 长按清空',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        key: Key('quick-slot-$i'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => onTapSlot(i),
        // ★ 右键 = 编辑这一格（换掉）；工具提示里也写了
        onSecondaryTap: () => onAssignSlot(i),
        onLongPress: item == null ? null : () => onClearSlot(i),
        child: Container(
          width: cell,
          height: cell,
          decoration: BoxDecoration(
            color: hot
                ? const Color(0xFFFFF8E1)
                : (item == null ? const Color(0xFFFAFCFE) : Colors.white),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hot
                  ? const Color(0xFFF6AD55)
                  : (kb ? const Color(0xFF1E88E5) : const Color(0xFFE2E8F0)),
              width: hot || kb ? 2 : 1,
            ),
          ),
          child: Stack(
            children: <Widget>[
              Positioned(
                left: 3,
                top: 1,
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                      fontSize: 8, color: Color(0xFFB0BEC5)),
                ),
              ),
              // ★★ 2026-10-18 晚（用户）：**空位不要加号** —— 「简洁一点」。
              //   空位只留左上角那个小序号（告诉用户"这是第几格"），
              //   不再画 `+`：`+` 会让人以为"必须点它才能加"，而实际动作是
              //   「点格子进赋值模式」（提示已经写在 tooltip 里，不占视觉）。
              if (item != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 8, 2, 2),
                  child: Center(child: symbolPreview(item, size: 13)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
