// 整篇归一：**只用于"交给外面"的边界**（保存 / 导出 / 复制全文），不改缓冲区。
//
// 为什么单独做这一层（2026-11-01 用户拍板的口径）：
//   · 归一**不能**逐击键跑 —— 空结构会被当场收走（`^` 刚展开成 `^{}` 就被回收），
//     撇归一还会改字节长度与顺序（光标/IME 都要重映射）；
//   · 但归一**必须**在"落盘给外面看"的地方跑一次，否则 `.md` 是两种形态混着
//     （老文档留着裸撇 `f'`、新写的写 `^{\prime}`），AI 与其它工具读到的东西不唯一。
//   ⇒ 边界上做**副本归一**：不动 live 缓冲区 ⇒ 不移动光标、不进撤销栈、不打断输入。

import '../render/normalize.dart';
import 'math_spans.dart';

/// 把 [doc] 里**每一个数学段**的 tex 归一（返回新字符串；[doc] 本身不动）。
///
/// 幂等：对结果再跑一次不会再变（`prime_normalize_test` / `normalize_test` 的口径）。
String normalizeDocument(String doc) {
  final List<MathSpan> spans = scanMathSpans(doc);
  if (spans.isEmpty) return doc;
  final StringBuffer out = StringBuffer();
  var at = 0;
  for (final MathSpan s in spans) {
    final int innerStart = s.start + (s.display ? 2 : 1);
    final int innerEnd = innerStart + s.tex.length;
    if (innerStart < at || innerEnd > doc.length || innerStart > innerEnd) {
      continue; // 防御：span 自相矛盾就跳过（宁可原样，不许吞内容）
    }
    final String fixed = normalizeTex(s.tex, 0).tex;
    out.write(doc.substring(at, innerStart));
    out.write(fixed);
    at = innerEnd;
  }
  out.write(doc.substring(at));
  return out.toString();
}
