// 数语引擎 · 单元 widget 池（S2-3 实测出来的关键技术）
//
// 目的：**源文本没变就复用同一个 widget 实例** ——
// `Element.updateChild` 发现 `child.widget == newWidget`（同一实例）会**整棵子树直接返回**，
// 既不 build 也不 layout。实测：空帧 91 ms → 2.8 ms（32×），打字帧 89 ms → 12.4 ms。
//
// ★★ 两条纪律（都是踩出来的）：
//   1. **同一个实例不能同时出现在树的两个位置** —— flutter_math_fork 的 `Math` 会把
//      `Line(key: GlobalKey)` 这个 widget **记忆化**，同一实例放两处 → "Multiple widgets used
//      the same GlobalKey"。所以同帧内第二次用到同一个 contentKey 时**新建一个、不入池**。
//   2. **"测量树"与"渲染树"必须各用各的池** —— 否则两棵树会互相把对方的实例挤掉，
//      结果两棵树每帧都在重建。

import 'package:flutter/widgets.dart';

/// 按**内容**寻址的 widget 池，带"同帧只用一个实例"的保护。
class UnitPool {
  final Map<String, Widget> _pool = <String, Widget>{};

  /// 本帧已经用掉的 contentKey
  final Set<String> _used = <String>{};

  /// 每帧 build 开头调用
  void beginFrame() => _used.clear();

  /// 取（或建）一个 widget 实例。
  ///
  /// [key] 应当是"内容键"（内容变了 key 就变），这样**在中间插入内容不会让后面的单元失效**。
  Widget widgetFor(String key, Widget Function() build) {
    if (_used.contains(key)) {
      // 同帧第二次出现 → 必须新建，不能复用同一实例（见文件头纪律 1）
      return build();
    }
    _used.add(key);
    final Widget? cached = _pool[key];
    if (cached != null) return cached;
    final Widget w = build();
    _pool[key] = w;
    return w;
  }

  /// 每帧 build 结尾调用：把这一帧没用到的实例丢掉（池子大小 = 上一帧的内容量）
  void endFrame() {
    if (_pool.isEmpty) return;
    _pool.removeWhere((String k, _) => !_used.contains(k));
  }

  int get size => _pool.length;
}
