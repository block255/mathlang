// 数语引擎 · **检查更新的通道**（D1，2026-10-28；1.2.1 起改"外挂小助手"）
//
// 分三层，和文件后端同一套套路（`io/file_gateway_platform.dart`）：
//   · 这个文件 = 接口 + **平台入口**（默认 Web 空实现，有 `dart:io` 时换原生）；
//   · `update_gateway_native.dart` = Windows 真实现（`HttpClient` + 外挂安装脚本）；
//   · `update_gateway_web.dart` = 全空（Web 端只用来开发，不做更新）。
//
// ★★ 2026-10-28 实测（0x80073D02）：**Windows 不允许"边跑边装"** ——
//   `Add-AppxPackage` 会说"它修改的资源当前正在使用中，需要关闭 MathLang.Editor"。
//   ⇒ 安装必须交给**外挂小助手**：主程序先退出，由它装完再起新版。
//   于是"更新完成"这件事只能在**下一次启动**时告诉用户（结果写在 %TEMP% 的结果文件里）。

import '../core/update_check.dart';
import 'update_gateway_web.dart'
    if (dart.library.io) 'update_gateway_native.dart' as impl;

/// GitHub 仓库与发布页（**与平台无关**，界面直接用它）
const String kUpdateRepoSlug = 'block255/mathlang';
const String kUpdateReleasePage =
    'https://github.com/block255/mathlang/releases/latest';

/// 上一次更新留在 `mathlang-update-pending.json` 里的东西（供"下次启动"的弹窗用）
class PendingUpdate {
  const PendingUpdate({this.notes, this.msixPath});
  final String? notes;

  /// 下好的安装包在本地哪 —— 安装失败时要把它摆给用户（可以手动装）
  final String? msixPath;
}

/// **下载取消令牌**（2026-10-28 晚）
///
/// 为什么要有它：以前弹窗上的【取消】只是"让进度条别再更新"，后台照样把 13.8 MB
/// 下完、照样写出文件 —— **界面说取消，实际没停**。
/// 现在取消会真 `client.close(force: true)` 掐断连接；已经下到的部分**故意保留**成
/// `.part`，下次点更新**接着下**（断点续传）。
class DownloadCancelToken {
  bool _cancelled = false;
  Object? _client; // 实体是 dart:io 的 HttpClient（这里不引 dart:io，Web 也要能编译）

  bool get isCancelled => _cancelled;

  /// 实现方把连接挂进来，取消时才掐得断
  void attach(Object client) => _client = client;
  void detach() => _client = null;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final Object? c = _client;
    if (c == null) return;
    try {
      // ignore: avoid_dynamic_calls
      (c as dynamic).close(force: true);
    } catch (_) {
      // 已经关掉了 ⇒ 无所谓，isCancelled 已置位
    }
  }
}

/// 检查更新要用的几件事（界面只调这些）。
abstract class UpdateGateway {
  /// 这台机器上是不是 **MSIX 安装**（决定"一键更新"走不走得通）。
  bool get isPackaged;

  /// **该不该做"启动后自动检查"**。
  ///
  /// Web ⇒ 不查（只是开发台）；**测试环境也不查** —— 启动检查会留一个 3 秒定时器，
  /// 而 widget 测试的 `pumpAndSettle` 见到挂着的定时器就直接判失败
  /// （2026-10-28 实测：147 个测试因此红）。手动「检查更新」不受这条影响。
  bool get supportsAutoCheck;

  /// **最近一次失败的真实原因**（给界面显示）。
  ///
  /// ★ 以前把失败一律压成"网络不可用"——用户网络明明好好的
  ///   （实测是 hosts 把 api.github.com 劫持到 127.0.0.1，而那个加速工具当时没在应答）。
  ///   原则 5「静默失败必须可见」：原因要能看见，用户才不用猜自己的网。
  String? get lastError;

  /// 查最新 release。**失败一律返回 null（不抛）**，原因放进 [lastError]。
  Future<UpdateInfo?> checkLatest();

  /// 把 msix 下到临时目录；返回本地路径（失败 ⇒ null，原因在 [lastError]）。
  ///
  /// [onProgress] 是**真进度**（已下字节 / 总字节；总字节未知时 total = -1）。
  /// ★ 1.2.1 起改成流式读 chunk（原来是 `res.pipe(sink)`，没有进度）——
  ///   用户 2026-10-28 要求"界面内独立弹窗 + 进度条"，那就得能报进度。
  Future<String?> downloadMsix(
    UpdateInfo info, {
    void Function(int got, int total)? onProgress,
    DownloadCancelToken? cancel,
  });

  /// 已下载的更新包占多少字节（`.part` 半截 + 完整包，一起算）
  Future<int> downloadedUpdateBytes();

  /// 清掉已下载的更新包（`.part` 与完整包一起），返回删掉多少字节
  Future<int> clearDownloadedUpdates();

  /// 有几个半截/完整文件（0 字节的空 `.part` 也算一个 —— 那是"取消得太早"的痕迹）
  Future<int> downloadedUpdateFiles();

  /// **我们在哪个目录里找更新包**（给设置页显示 —— 让"看不到残留"这件事可诊断）
  String get downloadsHint;

  /// 生成并**启动外挂小助手**：它等本进程退出 → `Add-AppxPackage` → 起新版。
  /// 返回 true ⇒ 调用方应当**立刻退出**（`exit(0)`），把舞台让给它。
  ///
  /// [notes] / [pageUrl] 会在退出前存进 `mathlang-update-pending.json`，
  /// 供"已更新到 x.y.z"弹窗显示更新说明（用户 2026-10-28 要的）。
  Future<bool> launchInstaller(
    String msixPath, {
    required String version,
    String notes = '',
    String pageUrl = '',
  });

  /// 上一次更新留下的结果（`ok:<版本>` / `fail:<原因>`；读完就删）。没有 ⇒ null。
  ///
  /// ★ 读到 `ok:` 时实现方要**顺手清掉**那三样临时文件（msix / .ps1 / pending.json）——
  ///   那是"启动时顺手清"的第 ① 条（用户 2026-10-28 定的两条规则之一）。
  Future<String?> takeLastUpdateResult();

  /// 上一次更新保存下来的东西：**更新说明**（弹窗显示）+ **msix 本地路径**
  /// （安装失败时要摆给用户，让他能手动装）。没有 ⇒ null。
  Future<PendingUpdate?> takePendingInfo();

  /// "启动时顺手清"的第 ② 条：删掉 [olderThanDays] 天前的 `mathlang-update-*` 残留。
  /// 成本 = 列一次目录 + 几个删除；**不联网、不碰用户文档**。
  Future<void> sweepOldUpdateFiles({int olderThanDays = 3});

  /// **当前网络通道**的一句话说明（给下载弹窗显示）。
  ///
  /// ★ 只报**能看见**的东西：`api.github.com` 解析到 loopback ⇒ 说明 hosts 被本地加速
  ///   工具劫持；否则**不许**猜"裸连还是 VPN"（VPN 在应用眼里和直连一样）——
  ///   用户 2026-10-28 拍板：非劫持就写「正在尝试连接 GitHub」，不要写"或"。
  Future<String> describeChannel();

  /// 在资源管理器里**定位到某个文件**（选中它）——
  /// 绿色版"下载好了"之后用它把安装包摆到用户眼前（2026-10-28 晚）。
  Future<void> revealFile(String path);

  /// 用系统浏览器打开发布页。
  Future<void> openReleasePage(String url);
}

/// 当前平台的更新通道
UpdateGateway platformUpdateGateway() => impl.createUpdateGateway();
