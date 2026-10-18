// 数语引擎 · **按平台挑文件后端**（S4-d-①）
//
// 条件导入的唯一技巧就在这里：**默认用 web 实现，有 `dart:io` 时换成原生实现**。
// 这样 `lib/` 里任何地方都不需要写 `Platform.isWindows` 之类的分支，
// 也不会把 `dart:io` 带进 web 构建。

import 'file_gateway.dart';
import 'file_gateway_web.dart'
    if (dart.library.io) 'file_gateway_native.dart' as impl;

/// 当前平台的文件后端（Windows / Android ⇒ 原生；Web ⇒ 浏览器下载）
FileGateway platformFileGateway() => impl.createFileGateway();
