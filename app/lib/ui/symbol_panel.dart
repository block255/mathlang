// 数语引擎 · **符号面板（筛选器式）**（S4-b② 重写）
//
// 规格：《界面与布局.md》**§4**（用户 2026-10-17 定稿）：
//   「不是给一个大面、放各种类把这个面占满，而是**这个面就当作选择的表格**；
//     上方**留出按钮来筛选显示**，初始为"全部"；有二级子类的，选那个类时再给一个二级筛选按钮，也是初始"全部"。」
//
// 所以本文件**只有一个网格** —— 没有分类列表页、没有 tab 行、没有返回按钮（那三个方案已明确否掉）。
//
//   🔍 [ 搜索：中文名 / 别名 / 拼音 / LaTeX ]
//   [ 分类 ▾ 全部 ] [ 子类 ▾ 全部 ]            共 N 项
//   ┌──┐┌──┐┌──┐┌──┐┌──┐┌──┐┌──┐┌──┐      ← 面 = 表格（当前筛选的项）
//
// 三条交互规则（§4.2）：
//   ① **搜索优先于筛选**：有查询 ⇒ 跨分类结果；清空 ⇒ 回到原来的筛选；
//   ② 选了没有子类的分类（结构）⇒ `子类` 自动回"全部"并**置灰**；
//   ③ 点某个符号 ⇒ `onInsert`（插入语义在 `lang/symbol_insert.dart`）；
//      快捷栏**赋值模式**下改走 `onAssign`（面板保持打开、筛选不变）。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../lang/symbol_library.dart';
import '../render/slot_marks.dart';
import 'app_settings.dart';

/// "全部"在下拉里的取值（`PopupMenuItem` 不接受 null）
const String kFilterAll = '';

class SymbolPanel extends StatefulWidget {
  const SymbolPanel({
    super.key,
    required this.library,
    required this.onInsert,
    this.columns = LayoutMetrics.defaultGridColumns,
    this.cellSize = LayoutMetrics.cellSize,
    this.searchFocus,
    this.assignSlot,
    this.onAssign,
    this.showEmptySuggestions = true,
    this.showLabels = true,
  });

  final SymbolLibrary library;
  final void Function(SymbolItem item) onInsert;
  final int columns;
  final double cellSize;

  /// 打开面板时把焦点给搜索框（外壳传入）
  final FocusNode? searchFocus;

  /// 快捷栏**赋值模式**下是第几格（`null` = 正常插入模式）
  final int? assignSlot;
  final void Function(SymbolItem item)? onAssign;

  /// 搜不到时给相近建议（绝不静默空手而归）
  final bool showEmptySuggestions;

  /// 格子里显不显示中文名（关掉 ⇒ 格子更大、不再被截字）
  final bool showLabels;

  @override
  State<SymbolPanel> createState() => SymbolPanelState();
}

class SymbolPanelState extends State<SymbolPanel> {
  final TextEditingController _query = TextEditingController();

  /// 一级筛选（`null` = 全部）
  String? _group;

  /// 二级筛选（`null` = 全部；只有「符号」有子类）
  String? _subgroup;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  // ---------------- 对外（测试 / 外壳） ----------------

  String? get group => _group;
  String? get subgroup => _subgroup;

  /// 当前该分类下可选的子类（没有 ⇒ 空表 ⇒ 子类按钮置灰）
  List<String> get subgroupOptions =>
      _group == null ? const <String>[] : widget.library.subgroupsOf(_group!);

  /// 当前面里有哪些项（=`inCategory` 或搜索结果）
  List<SymbolItem> visibleItems() {
    final String q = _query.text.trim();
    if (q.isNotEmpty) {
      return <SymbolItem>[
        for (final SymbolHit h in widget.library.search(q)) h.item,
      ];
    }
    return widget.library.inCategory(group: _group, subgroup: _subgroup);
  }

  bool get searching => _query.text.trim().isNotEmpty;

  void setGroup(String? g) {
    setState(() {
      _group = g;
      // 分类一变，子类回"全部"（否则会出现"结构 ▸ 希腊"这种不存在的组合）
      _subgroup = null;
    });
  }

  void setSubgroup(String? s) => setState(() => _subgroup = s);

  // ---------------- 构建 ----------------

  @override
  Widget build(BuildContext context) {
    final List<SymbolItem> shown = visibleItems();
    return SizedBox(
      width: LayoutMetrics.panelWidth(widget.columns, cell: widget.cellSize),
      child: Material(
        color: const Color(0xFFF7FAFC),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  LayoutMetrics.panelPadding, 10, LayoutMetrics.panelPadding, 4),
              child: TextField(
                key: const Key('symbol-search'),
                controller: _query,
                focusNode: widget.searchFocus,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: '搜索：中文名 / 别名 / 拼音 / LaTeX',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            _filters(shown.length),
            const Divider(height: 1),
            Expanded(
              child: shown.isEmpty ? _empty() : _grid(shown),
            ),
          ],
        ),
      ),
    );
  }

  // ★ 赋值模式的提示条只在**快捷栏**那一侧画。
  //   2026-10-17 实测：面板与快捷栏各画一条 ⇒ 屏幕上下两条重复的黄色提示（噪音），删掉面板这条。

  /// 两个**下拉筛选**（不是把分类铺满面板）＋ 计数
  Widget _filters(int count) {
    final List<String> subs = subgroupOptions;
    final bool subEnabled = subs.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(LayoutMetrics.panelPadding, 2,
          LayoutMetrics.panelPadding, 8),
      child: Row(
        children: <Widget>[
          PopupMenuButton<String>(
            key: const Key('filter-group'),
            tooltip: '按一级分类筛选',
            initialValue: _group ?? kFilterAll,
            onSelected: (String v) => setGroup(v.isEmpty ? null : v),
            itemBuilder: (BuildContext c) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                  value: kFilterAll, child: Text('全部')),
              for (final String g in widget.library.groups)
                PopupMenuItem<String>(value: g, child: Text(g)),
            ],
            child: _filterChip('分类', _group ?? '全部'),
          ),
          const SizedBox(width: 6),
          if (subEnabled)
            PopupMenuButton<String>(
              key: const Key('filter-subgroup'),
              tooltip: '按二级子类筛选',
              initialValue: _subgroup ?? kFilterAll,
              onSelected: (String v) => setSubgroup(v.isEmpty ? null : v),
              itemBuilder: (BuildContext c) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                    value: kFilterAll, child: Text('全部')),
                for (final String s in subs)
                  PopupMenuItem<String>(value: s, child: Text(s)),
              ],
              child: _filterChip('子类', _subgroup ?? '全部'),
            )
          else
            // 没有子类（或没选分类）⇒ **置灰**（§4.2）
            Tooltip(
              message: _group == null ? '先选分类' : '「$_group」没有子类',
              child: _filterChip('子类', '全部', enabled: false),
            ),
          const Spacer(),
          Text(
            searching ? '搜索 $count 项' : '共 $count 项',
            key: const Key('panel-count'),
            style: const TextStyle(fontSize: 10, color: Color(0xFF718096)),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value, {bool enabled = true}) {
    final Color fg =
        enabled ? const Color(0xFF2D3748) : const Color(0xFFCBD5E0);
    return Container(
      key: Key('filter-chip-$label'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: enabled ? const Color(0xFFE2E8F0) : const Color(0xFFEDF2F7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label,
              style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
          const SizedBox(width: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 12, color: fg, fontWeight: FontWeight.w500)),
          Icon(Icons.arrow_drop_down,
              size: 16, color: enabled ? fg : const Color(0xFFE2E8F0)),
        ],
      ),
    );
  }

  Widget _grid(List<SymbolItem> shown) {
    return GridView.builder(
      padding: const EdgeInsets.all(LayoutMetrics.panelPadding),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.columns,
        mainAxisSpacing: LayoutMetrics.cellGap,
        crossAxisSpacing: LayoutMetrics.cellGap,
        mainAxisExtent: widget.cellSize + 8,
      ),
      itemCount: shown.length,
      itemBuilder: (BuildContext c, int i) => cell(shown[i]),
    );
  }

  /// 搜不到 / 筛不到时的**空态**（§11 缺口 10：绝不静默空手而归）
  Widget _empty() {
    final List<SymbolItem> near = widget.showEmptySuggestions && searching
        ? _suggestions(_query.text.trim())
        : const <SymbolItem>[];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              searching ? '没有匹配「${_query.text.trim()}」的符号' : '这一类下暂时没有条目',
              key: const Key('empty-title'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF4A5568)),
            ),
            if (near.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              const Text('你是不是想找',
                  style: TextStyle(fontSize: 10, color: Color(0xFF718096))),
              const SizedBox(height: 6),
              Wrap(
                key: const Key('empty-suggestions'),
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  for (final SymbolItem i in near)
                    InkWell(
                      key: Key('suggest-${i.id}'),
                      onTap: () => _tap(i),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(i.label,
                            style: const TextStyle(fontSize: 11)),
                      ),
                    ),
                ],
              ),
            ],
            if (searching || _group != null || _subgroup != null) ...<Widget>[
              const SizedBox(height: 10),
              TextButton(
                key: const Key('empty-clear'),
                onPressed: () => setState(() {
                  _query.clear();
                  _group = null;
                  _subgroup = null;
                }),
                child: const Text('清空搜索与筛选', style: TextStyle(fontSize: 11)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 相近建议：**逐字缩短查询**再搜（"矩阵的逆" → "矩阵的" → "矩阵"），去重取前 6 条。
  /// 理由：用户打的是**短语**，符号表里是**词**；缩短是最省事又最可解释的模糊。
  List<SymbolItem> _suggestions(String q) {
    final List<SymbolItem> out = <SymbolItem>[];
    final Set<String> seen = <String>{};
    for (var n = q.length; n > 0 && out.length < 6; n--) {
      final String probe = q.substring(0, n);
      for (final SymbolHit h in widget.library.search(probe, limit: 6)) {
        if (seen.add(h.item.id)) out.add(h.item);
        if (out.length >= 6) break;
      }
      // 已经找到就不必再缩
      if (out.isNotEmpty) break;
    }
    if (out.isEmpty) {
      // 最后兜底：拼音子序列 / 单字包含
      for (final SymbolItem i in widget.library.items) {
        if (i.label.contains(q) || i.tex.contains(q)) {
          if (seen.add(i.id)) out.add(i);
          if (out.length >= 6) break;
        }
      }
    }
    return out;
  }

  void _tap(SymbolItem item) {
    if (widget.assignSlot != null) {
      widget.onAssign?.call(item);
    } else {
      widget.onInsert(item);
    }
  }

  /// 一格（也供快捷栏复用风格）
  Widget cell(SymbolItem item) {
    return Tooltip(
      message: '${item.label}  ${item.tex}',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        key: Key('symbol-${item.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => _tap(item),
        // ★ 长按 = **真预览**（大图 + 名称 + LaTeX）；b1 只有一个小 tooltip
        onLongPress: () => showSymbolPreviewDialog(context, item,
            onInsert: () => _tap(item)),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Expanded(child: Center(child: symbolPreview(item))),
              if (widget.showLabels)
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: Color(0xFF718096)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 符号的真实渲染预览（**同一格也用在快捷栏**）
///
/// ★ 走**同一条注入链**（`renderMathTex`）：空槽会被注上占位垫 ⇒
///   `^{}` / `_{}` / `\frac{}{}` 这些模板在格子里**看得见空槽**（否则是一片空白）。
Widget symbolPreview(SymbolItem item, {double size = 14}) {
  // ★ 优先用 `preview`（代表式）：`cases`/`aligned` 的空格子直接画出来是一对花括号，
  //   看不出是什么东西 ⇒ 数据里给一份填充式当门面（插入的仍是空槽 tex）。
  final String tex = renderMathTex(item.previewTex, caretRel: -1);
  return FittedBox(
    fit: BoxFit.scaleDown,
    child: Math.tex(
      tex,
      mathStyle: MathStyle.text,
      textStyle: TextStyle(fontSize: size, color: const Color(0xFF1A202C)),
      onErrorFallback: (Object e) =>
          Text(item.label, style: const TextStyle(fontSize: 10)),
    ),
  );
}

/// 长按格子的**真预览浮层**（大图 + 名称 + LaTeX 源码 + 插入）
///
/// 为什么值得做：面板里格子只有 44px，`\bigcup` 和 `\cup` 那种差别在 14px 下看不出来。
Future<void> showSymbolPreviewDialog(
  BuildContext context,
  SymbolItem item, {
  VoidCallback? onInsert,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext c) => Dialog(
      key: Key('symbol-preview-${item.id}'),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(item.label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Center(
                child: symbolPreview(item, size: 40),
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              item.tex,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF718096)),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(c).pop(),
                  child: const Text('关闭', style: TextStyle(fontSize: 12)),
                ),
                if (onInsert != null)
                  FilledButton(
                    key: Key('symbol-preview-insert-${item.id}'),
                    onPressed: () {
                      Navigator.of(c).pop();
                      onInsert();
                    },
                    child: const Text('插入', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
