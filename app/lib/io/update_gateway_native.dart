// 数语引擎 · 检查更新的**原生实现**（Windows）
//
// 只用 `dart:io`：`HttpClient` 查 GitHub API、`Process` 跑 `Add-AppxPackage`。
// 不引入 http / url_launcher（调查稿 §六：清单只有 runFullTrust，联网不受限）。

import 'dart:convert';
import 'dart:io';

import '../core/update_check.dart';
import 'update_gateway.dart';

UpdateGateway createUpdateGateway() => const NativeUpdateGateway();

class NativeUpdateGateway implements UpdateGateway {
  const NativeUpdateGateway();

  /// 超时：用户 2026-10-28 拍板"启动后静默检查，不能卡住" ⇒ 6 秒到点就当没查到。
  static const Duration _timeout = Duration(seconds: 6);

  @override
  bool get isPackaged {
    // MSIX 安装的真身跑在 `C:\Program Files\WindowsApps\...` 下；
    // 绿色版跑在用户解压的目录里。这条判据比"猜"靠谱，且不需要权限。
    final String exe = Platform.resolvedExecutable.toLowerCase();
    return exe.contains('windowsapps');
  }

  /// `flutter test` 会把 `FLUTTER_TEST=true` 写进环境（实测确认过）。
  /// 测试里**不许**起"启动后自动检查"：那个 3 秒延时定时器会让 `pumpAndSettle` 判失败。
  @override
  bool get supportsAutoCheck =>
      Platform.environment['FLUTTER_TEST'] != 'true';

  @override
  Future<UpdateInfo?> checkLatest() async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = _timeout
      ..userAgent = 'mathlang-updater/1 (+https://github.com/$kUpdateRepoSlug)';
    try {
      final HttpClientRequest req = await client
          .getUrl(Uri.parse(
              'https://api.github.com/repos/$kUpdateRepoSlug/releases/latest'))
          .timeout(_timeout);
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final HttpClientResponse res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) return null;
      final String body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      return UpdateInfo.tryParse(jsonDecode(body));
    } catch (_) {
      // 网络不稳是常态（本机实测出现过 ERR_CONNECTION_TIMED_OUT）⇒ 静默失败
      return null;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<String?> downloadMsix(UpdateInfo info) async {
    final String? url = info.msixUrl;
    if (url == null) return null;
    final HttpClient client = HttpClient()..connectionTimeout = _timeout;
    try {
      final HttpClientRequest req = await client.getUrl(Uri.parse(url));
      final HttpClientResponse res = await req.close();
      if (res.statusCode != 200) return null;
      final String tag = (info.version ?? 'new').toString();
      final File out = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'mathlang-update-$tag.msix');
      final IOSink sink = out.openWrite();
      try {
        await res.pipe(sink);
      } finally {
        await sink.close();
      }
      return out.lengthSync() > 0 ? out.path : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<bool> installMsix(String path) async {
    // ★ 故意**不带** `-ForceApplicationShutdown`：那是"把正在跑的应用杀掉"的开关，
    //   而我们要的是"装好之后让用户自己选立即重启"。装不上（应用占用）⇒ 返回 false，
    //   界面给「前往发布页」的兜底 —— 这是可接受且诚实的降级。
    try {
      final ProcessResult r = await Process.run(
        'powershell',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'Add-AppxPackage -Path \'$path\'',
        ],
      ).timeout(const Duration(seconds: 180));
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> relaunch() async {
    try {
      final ProcessResult r = await Process.run(
        'powershell',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'(Get-AppxPackage MathLang.Editor).PackageFamilyName',
        ],
      ).timeout(const Duration(seconds: 10));
      final String pfn = (r.stdout ?? '').toString().trim();
      if (pfn.isNotEmpty) {
        await Process.start(
          'explorer.exe',
          <String>['shell:AppsFolder\\$pfn!App'],
          mode: ProcessStartMode.detached,
        );
      }
    } catch (_) {
      // 起不来也不能卡住退出流程
    }
    exit(0);
  }

  @override
  Future<void> openReleasePage(String url) async {
    try {
      await Process.start(
        'explorer.exe',
        <String>[url.isEmpty ? kUpdateReleasePage : url],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      // 打不开浏览器就什么都不做（界面里还有那个网址可以手抄）
    }
  }
}
