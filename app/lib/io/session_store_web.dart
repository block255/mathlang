// 数语引擎 · 本地暂存的 **Web 占位实现**（S4-e-①）
//
// ★ Web 只用于开发预览（正式端 Windows / Android，2026-10-17 用户拍板）——
//   这里**故意不落盘**（也不引 `dart:html` 那套已弃用的 API）。
//   ⇒ 刷新丢内容是这个平台上的**已知限制**，别当成 bug 查。

import 'session_store.dart';

SessionStore createSessionStore() => const NoopSessionStore();
