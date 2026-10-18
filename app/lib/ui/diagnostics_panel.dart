// 数语引擎 · **诊断清单**（S4-b②，《S4》§A4 /《界面与布局》§11-7）
//
// 底线原则 5「**可疑要可见**」：智能包裹是**编辑器替用户猜的编码**，所以
//   · 状态栏报"自动包裹 N 处"；
//   · 点它 ⇒ 这份清单：**哪几处、原文是什么、在哪儿**，点一条就**跳过去并高亮**。
//
// ★ 数据源：`EditViewStats.autoWrappedSpans`（`lang/math_spans.dart` 扫出来的区间）。
//   只描述**最近一次插入**（这是刻意的：它是"刚才那一步我替你补了什么"的账，不是历史审计）。

import 'package:flutter/material.dart';

import '../lang/math_spans.dart';

Future<void> showDiagnostics(
  BuildContext context, {
  required List<MathSpan> spans,
  required void Function(MathSpan span) onJump,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext c) => _DiagnosticsDialog(spans: spans, onJump: onJump),
  );
}

class _DiagnosticsDialog extends StatelessWidget {
  const _DiagnosticsDialog({required this.spans, required this.onJump});

  final List<MathSpan> spans;
  final void Function(MathSpan span) onJump;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('diagnostics-dialog'),
      backgroundColor: const Color(0xFFFFFDF8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _header(context),
            const Divider(height: 1),
            Flexible(
              child: spans.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        '这一次没有需要你检查的东西。\n（粘贴纯文本、或插入一个符号时，'
                        '编辑器替你补的 `\$…\$` 会出现在这里）',
                        key: Key('diagnostics-empty'),
                        style: TextStyle(fontSize: 12, color: Color(0xFF4A5568), height: 1.6),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: spans.length,
                      itemBuilder: (BuildContext c, int i) => _row(context, i, spans[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: <Widget>[
          const Icon(Icons.report_gmailerrorred, size: 16, color: Color(0xFFDD6B20)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('诊断清单 · 编辑器替你补的编码',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  spans.isEmpty
                      ? '没有可疑项'
                      : '共 ${spans.length} 处 · 点一条跳过去并高亮（不算一次编辑）',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF718096)),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('diagnostics-close'),
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int i, MathSpan s) {
    return InkWell(
      key: Key('diagnostic-item-$i'),
      onTap: () {
        Navigator.of(context).pop();
        onJump(s);
      },
      child: Container(
        // 淡红底 = "这是编辑器猜的，值得看一眼"
        color: const Color(0xFFFFF5F5),
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: <Widget>[
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  color: Color(0xFFFFE0E0), shape: BoxShape.circle),
              child: Text('${i + 1}',
                  style: const TextStyle(fontSize: 10, color: Color(0xFFC53030))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    s.display ? '行间公式 · ${s.summary()}' : '行内公式 · ${s.summary()}',
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11, color: Color(0xFF2D3748)),
                  ),
                  Text(
                    '偏移 ${s.start}..${s.end}（${s.length} 字符）',
                    style: const TextStyle(fontSize: 9, color: Color(0xFFA0AEC0)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: Color(0xFFA0AEC0)),
          ],
        ),
      ),
    );
  }
}
