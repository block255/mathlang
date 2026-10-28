// 数语引擎 · 检查更新的**原生实现**（Windows）
//
// 只用 `dart:io`：`HttpClient` 查 GitHub API、`Process` 起外挂安装脚本。
// 不引入 http / url_launcher（调查稿 §六：清单只有 runFullTrust，联网不受限）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/update_check.dart';
import 'update_gateway.dart';

UpdateGateway createUpdateGateway() => NativeUpdateGateway();

class NativeUpdateGateway implements UpdateGateway {
  NativeUpdateGateway();

  /// 超时：用户 2026-10-28 拍板"启动后静默检查，不能卡住" ⇒ 到点就当没查到。
  /// ★ 1.2.1 从 6 s 放到 **10 s**：走本地加速工具（hosts 劫持到 127.0.0.1）比直连慢，
  ///   6 秒偏紧。它仍然是**异步**的，界面一个字都不会卡。
  static const Duration _timeout = Duration(seconds: 10);

  /// 失败原因（给界面显示）。**必须具体**，否则用户只能怀疑自己的网。
  String? _lastError;

  @override
  String? get lastError => _lastError;

  /// `flutter test` 会把 `FLUTTER_TEST=true` 写进环境（实测确认过）。
  /// 测试里**不许**起"启动后自动检查"：那个 3 秒延时定时器会让 `pumpAndSettle` 判失败。
  @override
  bool get supportsAutoCheck =>
      Platform.environment['FLUTTER_TEST'] != 'true';

  @override
  bool get isPackaged {
    // MSIX 安装的真身跑在 `C:\Program Files\WindowsApps\...` 下；
    // 绿色版跑在用户解压的目录里。这条判据比"猜"靠谱，且不需要权限。
    final String exe = Platform.resolvedExecutable.toLowerCase();
    return exe.contains('windowsapps');
  }

  @override
  Future<UpdateInfo?> checkLatest() async {
    _lastError = null;
    // 失败重试一次：本机的"访问 GitHub"其实是本地加速工具在代答（hosts 劫持到 127.0.0.1），
    // 它重启的那一两秒里会直接拒绝连接 —— 隔 1 秒再来一次基本就过去了。
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _checkOnce();
      } on _UpdateFailure catch (e) {
        _lastError = e.reason;
        if (!e.retryable || attempt == 1) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    return null;
  }

  Future<UpdateInfo?> _checkOnce() async {
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
      if (res.statusCode != 200) {
        throw _UpdateFailure('HTTP ${res.statusCode}（Release 接口）', retryable: false);
      }
      final String body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      final UpdateInfo? info = UpdateInfo.tryParse(jsonDecode(body));
      if (info == null) {
        throw _UpdateFailure('返回内容解析失败（tag 不像版本号）', retryable: false);
      }
      return info;
    } on _UpdateFailure {
      rethrow;
    } on HandshakeException catch (e) {
      throw _UpdateFailure(_sslHint(e.message), retryable: false);
    } on SocketException catch (e) {
      throw _UpdateFailure(_socketHint(e), retryable: true);
    } on TimeoutException {
      throw _UpdateFailure('超时（${_timeout.inSeconds} 秒内没有响应）', retryable: true);
    } on FormatException {
      throw _UpdateFailure('返回内容不是合法 JSON', retryable: false);
    } catch (e) {
      throw _UpdateFailure('${e.runtimeType}: $e', retryable: false);
    } finally {
      client.close(force: true);
    }
  }

  /// 把 `SocketException` 翻成人话 —— 本机最常见的两种：
  ///   ① 本地加速工具（hosts 把 github 指到 127.0.0.1）没在跑 ⇒ 连接被拒；
  ///   ② DNS 真的解析不了。
  String _socketHint(SocketException e) {
    final String msg = e.message.toLowerCase();
    if (msg.contains('refused') || e.osError?.message.contains('拒绝') == true) {
      return '连接被拒绝 —— 本机 127.0.0.1 上没有代理在应答'
          '（hosts 把 GitHub 域名指向了本地加速工具，先确认它在运行）';
    }
    if (msg.contains('failed host lookup') || msg.contains('nodename')) {
      return '域名解析失败（DNS）';
    }
    if (msg.contains('reset')) return '连接被重置';
    return '网络错误：${e.message}';
  }

  /// TLS 失败在本机有个很典型的成因：自签证书（本地加速工具自己签的）没进信任库。
  String _sslHint(String m) {
    final String s = m.toLowerCase();
    if (s.contains('certificate') || s.contains('cert')) {
      return '证书校验失败 —— 本地加速工具的自签证书不在信任库';
    }
    return 'TLS 握手失败：$m';
  }

  @override
  Future<String?> downloadMsix(
    UpdateInfo info, {
    void Function(int got, int total)? onProgress,
  }) async {
    _lastError = null;
    final String? url = info.msixUrl;
    if (url == null) {
      _lastError = '这个 Release 没有 msix 附件';
      return null;
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _downloadOnce(info, url, onProgress);
      } on _UpdateFailure catch (e) {
        _lastError = e.reason;
        if (!e.retryable || attempt == 1) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    return null;
  }

  Future<String?> _downloadOnce(
    UpdateInfo info,
    String url,
    void Function(int got, int total)? onProgress,
  ) async {
    final HttpClient client = HttpClient()..connectionTimeout = _timeout;
    File? out;
    IOSink? sink;
    try {
      final HttpClientRequest req = await client.getUrl(Uri.parse(url)).timeout(_timeout);
      final HttpClientResponse res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        throw _UpdateFailure('下载失败：HTTP ${res.statusCode}', retryable: false);
      }
      final int expect = res.contentLength;
      final String tag = (info.version ?? 'new').toString();
      out = File('${Directory.systemTemp.path}${Platform.pathSeparator}'
          'mathlang-update-$tag.msix');
      sink = out.openWrite();
      // ★ 流式读：这样界面才有**真进度**（用户 2026-10-28 要进度条）。
      //   原来的 `res.pipe(sink)` 一行到位，但报不了进度。
      var got = 0;
      await for (final List<int> chunk in res.timeout(const Duration(minutes: 5))) {
        sink.add(chunk);
        got += chunk.length;
        onProgress?.call(got, expect);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      // 下载被掐断时 Dart 通常抛异常；但有的代理会"正常结束"却只给半截 ⇒ 长度自检
      if (expect > 0 && got != expect) {
        throw _UpdateFailure('下载不完整（$got / $expect 字节）', retryable: true);
      }
      if (got == 0) throw _UpdateFailure('下载到 0 字节', retryable: true);
      return out.path;
    } on _UpdateFailure {
      rethrow;
    } on SocketException catch (e) {
      throw _UpdateFailure(_socketHint(e), retryable: true);
    } on TimeoutException {
      throw _UpdateFailure('下载超时', retryable: true);
    } catch (e) {
      throw _UpdateFailure('下载失败：${e.runtimeType}: $e', retryable: true);
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close(force: true);
    }
  }

  /// 外挂小助手的脚本内容（生成到 `%TEMP%`，用 `powershell -File` 跑）。
  ///
  /// 为什么必须外挂：**Windows 不允许边跑边装**（实测 0x80073D02「资源正在使用中」）。
  /// 流程：等本进程退出 → `Add-AppxPackage -ForceApplicationShutdown` → 起新版。
  static String _installerScript(String msix, String version) => '''
\$ErrorActionPreference = 'Stop'
\$result = Join-Path \$env:TEMP 'mathlang-update-result.txt'
\$msix = '${msix.replaceAll("'", "''")}'
\$log = Join-Path \$env:TEMP 'mathlang-update-log.txt'
# ★★ 2026-10-28 实测教训：**不要用 -File 传参数**！
#   上一版是 `powershell -File x.ps1 -WaitPid \$pid` —— 那 `\$pid` 是**字面量**，
#   `[int]\$WaitPid` 绑不上 ⇒ 参数绑定当场报错 ⇒ 脚本**一行都没跑**：
#   没有安装、没有结果文件、没有自动打开，用户看到的就是"点了没反应"。
#   ⇒ 现在脚本**不带任何参数**：主程序点【现在安装】后立刻 exit(0)，这里睡够 2.5 秒即可。
Start-Sleep -Milliseconds 2500
function Write-Result([string]\$text) {
  [IO.File]::WriteAllText(\$result, \$text, (New-Object System.Text.UTF8Encoding(\$false)))
}
try {
  Add-AppxPackage -Path \$msix -ForceApplicationShutdown -ErrorAction Stop
  Write-Result 'ok:$version'
  \$pfn = (Get-AppxPackage MathLang.Editor).PackageFamilyName
  if (\$pfn) { Start-Process 'explorer.exe' "shell:AppsFolder\\\$pfn!App" }
} catch {
  \$msg = \$_.Exception.Message
  if (\$msg.Length -gt 300) { \$msg = \$msg.Substring(0, 300) }
  Write-Result ('fail:' + \$msg.Replace("`r", ' ').Replace("`n", ' '))
  (\$_ | Out-String) | Out-File -FilePath \$log -Encoding UTF8
}
''';

  @override
  Future<bool> launchInstaller(
    String msixPath, {
    required String version,
    String notes = '',
    String pageUrl = '',
  }) async {
    _lastError = null;
    try {
      final String temp = Directory.systemTemp.path;
      final String sep = Platform.pathSeparator;
      final File script = File('$temp${sep}mathlang-update-$version.ps1');
      await script.writeAsString(_installerScript(msixPath, version), flush: true);
      // 下次启动要用它把"更新说明"带出来；**msix 路径也存**，因为安装失败时要摆给用户
      final File pending = File('$temp${sep}mathlang-update-pending.json');
      await pending.writeAsString(
        jsonEncode(<String, String>{
          'version': version,
          'notes': notes,
          'pageUrl': pageUrl,
          'msixPath': msixPath,
        }),
        flush: true,
      );
      // 上次的结果先清掉，免得下一次启动读到旧结论
      final File result = File('$temp${sep}mathlang-update-result.txt');
      if (result.existsSync()) result.deleteSync();
      await Process.start(
        'powershell',
        <String>[
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          '-File',
          script.path,
        ],
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (e) {
      _lastError = '起不来安装脚本：$e';
      return false;
    }
  }

  /// 结果文件 + 两个"用完就删"的伴生文件
  File _resultFile() => File('${Directory.systemTemp.path}'
      '${Platform.pathSeparator}mathlang-update-result.txt');

  File _pendingFile() => File('${Directory.systemTemp.path}'
      '${Platform.pathSeparator}mathlang-update-pending.json');

  @override
  Future<String?> takeLastUpdateResult() async {
    try {
      final File f = _resultFile();
      if (!f.existsSync()) return null;
      final String s = f.readAsStringSync().trim();
      try {
        f.deleteSync();
      } catch (_) {}
      if (s.isEmpty) return null;
      // ★ "启动时顺手清"第 ① 条：装好了 ⇒ msix 与 .ps1 就没价值了，当场删。
      //   失败的话**留着**（用户可能想重试，别让他重下 13.7 MB）—— 交给 3 天兜底那条。
      if (s.startsWith('ok:')) {
        _deleteOldUpdateFiles(onlyMsixAndScript: true);
        try {
          _pendingFile().deleteSync();
        } catch (_) {}
      }
      return s;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<PendingUpdate?> takePendingInfo() async {
    try {
      final File f = _pendingFile();
      if (!f.existsSync()) return null;
      final Object? j = jsonDecode(f.readAsStringSync());
      if (j is! Map) return null;
      final String notes = (j['notes'] ?? '').toString().trim();
      final String msix = (j['msixPath'] ?? '').toString().trim();
      return PendingUpdate(
        notes: notes.isEmpty ? null : notes,
        msixPath: msix.isEmpty ? null : msix,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> sweepOldUpdateFiles({int olderThanDays = 3}) async {
    _deleteOldUpdateFiles(olderThanDays: olderThanDays);
  }

  /// 删 `%TEMP%` 里的 `mathlang-update-*`。
  ///
  /// · [onlyMsixAndScript] ⇒ 只删 msix / ps1（"装好了"那一支，立刻删）；
  /// · 否则只删 [olderThanDays] 天前的（兜底那条）。
  void _deleteOldUpdateFiles({bool onlyMsixAndScript = false, int olderThanDays = 3}) {
    try {
      final Directory dir = Directory.systemTemp;
      final DateTime cutoff =
          DateTime.now().subtract(Duration(days: olderThanDays));
      for (final FileSystemEntity e in dir.listSync(followLinks: false)) {
        if (e is! File) continue;
        final String name = e.uri.pathSegments.last.toLowerCase();
        if (!name.startsWith('mathlang-update-')) continue;
        final bool isPayload = name.endsWith('.msix') || name.endsWith('.ps1');
        if (onlyMsixAndScript && !isPayload) continue;
        if (!onlyMsixAndScript) {
          // 兜底那条：只动"够老"的（失败留下的 msix 也在内）
          DateTime mtime;
          try {
            mtime = e.statSync().modified;
          } catch (_) {
            continue;
          }
          if (mtime.isAfter(cutoff)) continue;
        }
        try {
          e.deleteSync();
        } catch (_) {}
      }
    } catch (_) {
      // 清理失败不该影响启动
    }
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

/// 内部用：带"要不要重试"标记的失败
class _UpdateFailure implements Exception {
  _UpdateFailure(this.reason, {required this.retryable});
  final String reason;
  final bool retryable;
}
