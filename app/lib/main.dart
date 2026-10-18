// ============================================================
//  数语引擎（mathlang）· S1-A 实验台入口
//  三块内容：★问 0 流内数学映射（A 组主战场）/ S1 渲染验证取证 / B 组 appflowy_editor
//  判定矩阵：notes/design/技术选型与风险.md 第 9.3 节
// ============================================================
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'spike/ime_input/ime_input_page.dart';
import 'spike/inline_math/inline_math_page.dart';
// 注意：B 组页面（spike/kernel_appflowy/）**故意不 import** ——
// appflowy_editor 6.2.0 与 Flutter 3.47.1 编译不兼容（TextInputClient.onFocusReceived），
// 一旦 import 就会让整个 app 编译失败。结论见 notes/design/技术选型与风险.md 9.7。
import 'spike/render_check/render_check_page.dart';
import 'spike/s2_page/s2_page_page.dart';
import 'spike/s2_projection/s2_projection_page.dart';
import 'spike/s3_edit/s3_edit_page.dart';
import 'ui/editor_page.dart';

void main() => runApp(const MathlangApp());

class MathlangApp extends StatelessWidget {
  const MathlangApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: kIsWeb ? '数语引擎 · S1-A 实验台' : '数语引擎',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF2B6CB0)),
        // ★ S4-d：**软件端（Windows / Android）直接进编辑器**（正式产品不该先看实验台）；
        //   Web 只用于开发 ⇒ 保留实验台入口（各阶段的验页面都还在）。
        home: kIsWeb ? const ExperimentHome() : const EditorPage(),
      );
}

class ExperimentHome extends StatelessWidget {
  const ExperimentHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数语引擎 · S1-A 实验台')),
      body: ListView(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '编辑内核对照实验（2026-10-13 开工）\n'
              '判定矩阵 7 问与及格线见 notes/design/技术选型与风险.md 第 9.3 节\n'
              '★ = 一票否决项',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
          const Divider(height: 1),
          _tile(
            context,
            '★★ 应用界面 · 编辑器（S4-b 面板 + 布局）',
            '顶栏 + A4 页面（偏左）+ 右侧符号面板（宽由格数推算）+ 状态栏；面板插入走「并入/建壳/替换」',
            const EditorPage(),
          ),
          _tile(
            context,
            '★ 问 0 · 流内数学映射可行性',
            '一维缓冲区 + 渲染投影：①基线对齐 ②光标画进数学 ③点击反查偏移 ④100 行性能',
            const InlineMathPage(),
          ),
          _tile(
            context,
            'S2-2 · 行内投影（折行 + 基线对齐实测）',
            r'Text.rich + WidgetSpan：段落自动折行、$...$ 不被拆开、基线对齐误差（baseline vs middle）',
            const S2ProjectionPage(),
          ),
          _tile(
            context,
            '★ S2-4 · A4 分页（真文档演示）',
            '一页放不下的自动流到下一页 · 手动分页符 · 高于一页的块告警 · 页眉 · 单元级缓存',
            const S2PagePage(),
          ),
          _tile(
            context,
            '★ S3-1b · 中文 IME 输入通道',
            'A 路 onKeyEvent+character vs B 路 平台文本输入（镜像输入框）→ 决定 S3-2「编辑面」的输入设备',
            const ImeInputPage(),
          ),
          _tile(
            context,
            '★ S3-2 · 编辑面（能打字了）',
            'A4 分页视图里直接打字（含中文 IME）· 光标可见 · 缓冲区实时更新 · Enter = 新块',
            const S3EditPage(),
          ),
          _tile(
            context,
            'S1 渲染验证页（既有取证）',
            '21 条正常样例 + 2 条错误样例 + SelectableMath（风险 1 的取证）',
            const RenderCheckPage(),
          ),
          _tile(
            context,
            'B 组 · appflowy_editor ✗ 编译不兼容',
            'appflowy_editor 6.2.0（最新版）与 Flutter 3.47.1 不兼容：TextInputClient.onFocusReceived 未实现\n'
                '→ B 组退化为"读源码评代价"（见 notes/design/技术选型与风险.md 9.7）',
            null,
          ),
        ],
      ),
    );
  }

  static Widget _tile(BuildContext context, String title, String sub, Widget? page) {
    return ListTile(
      leading: Icon(page == null ? Icons.pending_outlined : Icons.science_outlined),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right),
      enabled: page != null,
      onTap: page == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
    );
  }
}
