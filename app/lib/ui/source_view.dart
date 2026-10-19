// 数语引擎 · **只读源码浮层**（U1，2026-10-19 用户拍板）
//
// 定位（用户原话："只读的全文浮层，可以"）：
//   · 文档存的就是**标准 Markdown + LaTeX**，这个浮层把它原样摊开 —— 排查用；
//   · **只读**：不提供编辑（真要改请改正文；可编辑的源码视图是 S6 之后的事，已记账）；
//   · 可**选中 / 复制**：贴给我就能定位"存进去的到底是什么"。
//
// ★ 为什么是 `showDialog` 而不是又一个页面/路由：它是一次性诊断动作，
//   不该让编辑器状态与焦点换一套生命期（设置页本身也是"叠一层"的同一理由）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

Future<void> showSourceView(
  BuildContext context, {
  required String text,
  String title = '源码（只读）',
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext c) => _SourceDialog(title: title, text: text),
  );
}

class _SourceDialog extends StatelessWidget {
  const _SourceDialog({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final int lines = '\n'.allMatches(text).length + 1;
    return AlertDialog(
      key: const Key('source-dialog'),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      title: Row(
        children: <Widget>[
          Text(title, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Text('$lines 行 · ${text.length} 字符',
              style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
          const Spacer(),
          IconButton(
            key: const Key('source-copy'),
            tooltip: '复制全部',
            iconSize: 18,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
                content: Text('源码已复制', style: TextStyle(fontSize: 12)),
                duration: Duration(milliseconds: 1200),
                behavior: SnackBarBehavior.floating,
                width: 180,
              ));
            },
            icon: const Icon(Icons.copy_all_outlined),
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        height: 460,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF7FAFC),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                text.isEmpty ? '（空文档）' : text,
                key: const Key('source-text'),
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.65,
                  fontFamily: 'monospace',
                  color: Color(0xFF2D3748),
                ),
              ),
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('source-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
