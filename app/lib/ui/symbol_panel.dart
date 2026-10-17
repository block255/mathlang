// 数语引擎 · **符号面板**（S4-b）：搜索 ＋ 分类页签 ＋ 符号网格
//
// 规格：《符号面板与符号表.md》§四 ＋《界面与布局.md》§4。
//   · 面板宽由**格数**推出来（`LayoutMetrics.panelWidth`），不写死；
//   · 点格子 ⇒ `onInsert(item)`（**插入语义在 `lang/symbol_insert.dart`**，这里只负责"点了哪个"）；
//   · 面板**保持打开**（连续插入），关由外壳负责（`Esc` / 点正文）；
//   · 每个格子用真实数学渲染（长按/悬停会显示同名 tooltip；真·预览留给 b2）。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../lang/symbol_library.dart';
import 'app_settings.dart';

class SymbolPanel extends StatefulWidget {
  const SymbolPanel({
    super.key,
    required this.library,
    required this.onInsert,
    this.columns = LayoutMetrics.defaultGridColumns,
    this.searchFocus,
  });

  final SymbolLibrary library;
  final void Function(SymbolItem item) onInsert;
  final int columns;

  /// 打开面板时把焦点给搜索框（外壳传入）
  final FocusNode? searchFocus;

  @override
  State<SymbolPanel> createState() => _SymbolPanelState();
}

class _SymbolPanelState extends State<SymbolPanel> {
  final TextEditingController _query = TextEditingController();
  String? _group;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<SymbolItem> shown = _visibleItems();
    final double width = LayoutMetrics.panelWidth(widget.columns);
    return SizedBox(
      width: width,
      child: Material(
        color: const Color(0xFFF7FAFC),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  LayoutMetrics.panelPadding, 10, LayoutMetrics.panelPadding, 6),
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
            _groupTabs(),
            const Divider(height: 1),
            Expanded(
              child: shown.isEmpty
                  ? const Center(
                      child: Text('没有匹配的符号', style: TextStyle(fontSize: 12)))
                  : GridView.builder(
                      padding: const EdgeInsets.all(LayoutMetrics.panelPadding),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: widget.columns,
                        mainAxisSpacing: LayoutMetrics.cellGap,
                        crossAxisSpacing: LayoutMetrics.cellGap,
                        mainAxisExtent: LayoutMetrics.cellSize + 8,
                      ),
                      itemCount: shown.length,
                      itemBuilder: (BuildContext c, int i) =>
                          _cell(shown[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
          horizontal: LayoutMetrics.panelPadding, vertical: 4),
      child: Row(
        children: <Widget>[
          for (final String g in widget.library.groups)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: Key('group-$g'),
                label: Text(g, style: const TextStyle(fontSize: 12)),
                selected: _group == g,
                onSelected: (_) => setState(() => _group = (_group == g ? null : g)),
              ),
            ),
        ],
      ),
    );
  }

  List<SymbolItem> _visibleItems() {
    final String q = _query.text.trim();
    if (q.isNotEmpty) {
      return <SymbolItem>[for (final SymbolHit h in widget.library.search(q)) h.item];
    }
    if (_group != null) return widget.library.inGroup(_group!);
    // 没选分类 = 结构模板在前（最常用），其余按库内顺序
    final List<SymbolItem> templates = <SymbolItem>[
      for (final SymbolItem i in widget.library.items)
        if (i.isTemplate) i,
    ];
    final List<SymbolItem> symbols = <SymbolItem>[
      for (final SymbolItem i in widget.library.items)
        if (!i.isTemplate) i,
    ];
    return <SymbolItem>[...templates, ...symbols];
  }

  Widget _cell(SymbolItem item) {
    return Tooltip(
      message: '${item.label}  ${item.tex}',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        key: Key('symbol-${item.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => widget.onInsert(item),
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
              Expanded(child: Center(child: _preview(item))),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 8, color: Color(0xFF718096)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(SymbolItem item) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Math.tex(
        item.tex,
        mathStyle: MathStyle.text,
        textStyle: const TextStyle(fontSize: 14, color: Color(0xFF1A202C)),
        onErrorFallback: (Object e) => Text(item.tex, style: const TextStyle(fontSize: 10)),
      ),
    );
  }
}
