// 数语引擎 · **检查更新的通道**（D1，2026-10-28）
//
// 分三层，和文件后端同一套套路（`io/file_gateway_platform.dart`）：
//   · 这个文件 = 接口 + **平台入口**（默认 Web 空实现，有 `dart:io` 时换原生）；
//   · `update_gateway_native.dart` = Windows 真实现（`HttpClient` + `Add-AppxPackage`）；
//   · `update_gateway_web.dart` = 全空（Web 端只用来开发，不做更新）。
//
// ★ 为什么不用 http / url_launcher 之类的新依赖：`dart:io` 的 `HttpClient` 够用，
//   而清单里只有 `runFullTrust` ⇒ 联网不受限（调查稿 §六 已经查过）。

import '../core/update_check.dart';
import 'update_gateway_web.dart'
    if (dart.library.io) 'update_gateway_native.dart' as impl;

/// GitHub 仓库与发布页（**与平台无关**，界面直接用它）
const String kUpdateRepoSlug = 'block255/mathlang';
const String kUpdateReleasePage =
    'https://github.com/block255/mathlang/releases/latest';

/// 检查更新要用的四件事（界面只调这四个）。
abstract class UpdateGateway {
  /// 这台机器上是不是 **MSIX 安装**（决定"一键更新"走不走得通）。
  bool get isPackaged;

  /// **该不该做"启动后自动检查"**。
  ///
  /// Web ⇒ 不查（只是开发台）；**测试环境也不查** —— 启动检查会留一个 3 秒定时器，
  /// 而 widget 测试的 `pumpAndSettle` 见到挂着的定时器就直接判失败
  /// （2026-10-28 实测：147 个测试因此红）。手动「检查更新」不受这条影响。
  bool get supportsAutoCheck;

  /// 查最新 release。**失败/超时/解析不了一律返回 null，绝不抛**
  /// （界面据此显示"上次检查失败：网络不可用"，而不是弹报错框）。
  Future<UpdateInfo?> checkLatest();

  /// 把 msix 下到临时目录；返回本地路径（失败 ⇒ null）。
  Future<String?> downloadMsix(UpdateInfo info);

  /// 装已下载的 msix（`Add-AppxPackage`，不带 `-ForceApplicationShutdown` ——
  /// 目的是**别把正在运行的这个进程杀掉**，装完由用户选"立即重启"）。
  /// 返回是否装上；装不上 ⇒ 界面给"前往发布页"的兜底。
  Future<bool> installMsix(String path);

  /// 起一个新的自己（新版本），然后退出当前进程。
  Future<void> relaunch();

  /// 用系统浏览器打开发布页。
  Future<void> openReleasePage(String url);
}

/// 当前平台的更新通道
UpdateGateway platformUpdateGateway() => impl.createUpdateGateway();
