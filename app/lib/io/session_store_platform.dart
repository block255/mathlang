// 数语引擎 · **按平台挑本地暂存后端**（S4-e-①）
//
// 与 `file_gateway_platform.dart` 同一套路：**默认 web 实现，有 `dart:io` 时换成原生实现**
// ⇒ `lib/` 里不出现 `Platform.isWindows` 之类的分支，也不会把 `dart:io` 带进 web 构建。

import 'session_store.dart';
import 'session_store_web.dart'
    if (dart.library.io) 'session_store_native.dart' as impl;

/// 当前平台的暂存后端（Windows / Android ⇒ 文件；Web ⇒ 不落盘）
SessionStore platformSessionStore() => impl.createSessionStore();
