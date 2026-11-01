// 2026-11-01（用户两条反馈）：**手打输入的过滤与落点校正**。
//
// ## 一、反斜杠不许手打
// 原则 2「用户永远不需要看数学编码」⇒ `\` 是 LaTeX 命令的开头，手打一个孤立的 `\`
// 会让整块公式立刻变成 `[公式不完整]`（用户实测："数学区段里打 `\`，会变成公式不完整"）。
// 进编码的入口是符号面板 / 快捷键 / 模板，不是键盘敲反斜杠。
//
// ## 二、打字落点不许落在行首标记里
// 实测：标题 `# 20261028作业`，光标在最前面（`#` 之前）打 `w`
// ⇒ 缓冲区 `w# 20261028作业` ⇒ `#` 不在行首 ⇒ 不再是标题 ⇒ **markdown 标记漏到屏幕上**。
// 违反原则 3「结构由块类型表达，用户不写 Markdown 标记」。
//
// ★ 只挪**插入点**不删标记：删标记是 `Delete` 的语义（整块降级，见
//   `math_nav._visibleObjectDelete` ②），两者是两件事。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/typed_input.dart';

void main() {
  group('① 反斜杠不许手打', () {
    test('★ 单个 `\\` ⇒ 丢掉（不进缓冲区）', () {
      expect(filterTypedText('\\'), isNull,
          reason: r'★ 改前：一个反斜杠会插进 tex ⇒ 整块公式变 [公式不完整]');
    });

    test('普通字符 / 多字符载荷照旧', () {
      for (final String t in <String>['a', '甲', ' ', r'\frac', r'x\y', '\n']) {
        expect(filterTypedText(t), t, reason: r'「' '$t' r'」不该被挡');
      }
    });
  });

  group('② 打字落点不许落在行首标记里', () {
    test('★★ 标题 `# 标题`：在最前面打字 ⇒ 挪到标记之后', () {
      const String doc = '# 标题\n正文\n';
      expect(shiftInsertOutOfMarker(doc, 0), 2,
          reason: '★ 改前：`w` 插在 0 ⇒ `w# 标题` ⇒ 屏上显示 `w# 标题`（标记漏出来）');
      expect(shiftInsertOutOfMarker(doc, 1), 2, reason: '`#` 与空格之间也要挪');
      expect(shiftInsertOutOfMarker(doc, 2), isNull,
          reason: '已经在标题文字开头 ⇒ 不用挪（这就是"在标题开头插字"）');
      expect(shiftInsertOutOfMarker(doc, 3), isNull);
    });

    test('★ 三级标题 / 引用 / 列表 都按同一个判据', () {
      expect(shiftInsertOutOfMarker('### T1\n', 0), 4);
      expect(shiftInsertOutOfMarker('> 引用\n', 0), 2);
      expect(shiftInsertOutOfMarker('- 项\n', 0), 2);
      expect(shiftInsertOutOfMarker('1. 项\n', 0), 3);
    });

    test('★ 普通段落 / 公式行的开头不动', () {
      expect(shiftInsertOutOfMarker('正文\n', 0), isNull);
      expect(shiftInsertOutOfMarker('\$\$\nx\n\$\$\n', 0), isNull);
      expect(shiftInsertOutOfMarker('# 标题\n正文\n', 6), isNull, reason: '正文行没有标记');
    });
  });
}
