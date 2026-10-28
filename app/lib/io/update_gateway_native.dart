// 数语引擎 · 检查更新的**原生实现**（Windows）
//
// 只用 `dart:io`：`HttpClient` 查 GitHub API、`Process` 起外挂安装脚本。
// 不引入 http / url_launcher（调查稿 §六：清单只有 runFullTrust，联网不受限）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../app_info.dart';
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

  /// 检查更新用的地址。
  ///
  /// ★★ **探针钩子**（2026-10-28 用户提议）：绿色版可以用环境变量
  ///   `MATHLANG_UPDATE_API` 把地址指到一个**本地假 release**，
  ///   于是"启动 → 3 秒后静默查 → 发现新版 → 弹窗"这条真实路径可以**不发版**就验一遍。
  ///   **只在非打包版（绿色版/开发版）生效** —— 打包版永远走真地址，避免变成安全口子。
  String _apiUrl() {
    if (!isPackaged) {
      final String probe = Platform.environment['MATHLANG_UPDATE_API'] ?? '';
      if (probe.isNotEmpty) return probe;
    }
    return 'https://api.github.com/repos/$kUpdateRepoSlug/releases/latest';
  }

  Future<UpdateInfo?> _checkOnce() async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = _timeout
      ..userAgent = 'mathlang-updater/1 (+https://github.com/$kUpdateRepoSlug)';
    try {
      final HttpClientRequest req =
          await client.getUrl(Uri.parse(_apiUrl())).timeout(_timeout);
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
    DownloadCancelToken? cancel,
  }) async {
    _lastError = null;
    final String? url = info.msixUrl;
    _log('downloadMsix 进入 url=$url tag=${info.tag} '
        'packaged=$isPackaged temp=${Directory.systemTemp.path}');
    if (url == null) {
      _lastError = '这个 Release 没有 msix 附件';
      return null;
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      if (cancel?.isCancelled ?? false) {
        _lastError = '已取消';
        return null;
      }
      try {
        return await _downloadOnce(info, url, onProgress, cancel);
      } on _UpdateFailure catch (e) {
        _lastError = e.reason;
        if (!e.retryable || attempt == 1) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    return null;
  }

  /// 下载到 `<ver>.msix.part`，**断了能续**（2026-10-28 晚）。
  ///
  /// 三点行为：
  /// ① **分段续传**：有 `.part` 就发 `Range: bytes=<已下>-`；
  ///    服务器回 206 ⇒ 接着写；回 200 ⇒ 说明它不支持断点，**截断重下**（不会拼出坏文件）；
  /// ② **完成才改名**：长度校验通过才把 `.part` 改成 `.msix` ——
  ///    半截文件永远不会被当成"下好了"（这是续传最容易踩的坑）；
  /// ③ **取消是真取消**：[cancel] 会 `client.close(force: true)`，立刻停、不再吃带宽；
  ///    已经下到的部分**故意保留**（那是白下的带宽，下次接着用）。
  Future<String?> _downloadOnce(
    UpdateInfo info,
    String url,
    void Function(int got, int total)? onProgress,
    DownloadCancelToken? cancel,
  ) async {
    final HttpClient client = HttpClient()..connectionTimeout = _timeout;
    cancel?.attach(client);
    final String tag = (info.version ?? 'new').toString();
    final String sep = Platform.pathSeparator;
    final Directory temp = _downloadDir();
    final File part = File('${temp.path}${sep}mathlang-update-$tag.msix.part');
    final File done = File('${temp.path}${sep}mathlang-update-$tag.msix');
    IOSink? sink;
    try {
      // 已有多少？（只有它比目标小时才有意义）
      int have = 0;
      try {
        if (part.existsSync()) have = part.lengthSync();
      } catch (_) {}

      final HttpClientRequest req =
          await client.getUrl(Uri.parse(url)).timeout(_timeout);
      if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
      final HttpClientResponse res = await req.close().timeout(_timeout);
      final bool resumed = res.statusCode == HttpStatus.partialContent;
      if (res.statusCode != 200 && !resumed) {
        throw _UpdateFailure('下载失败：HTTP ${res.statusCode}', retryable: false);
      }
      // 总长度：206 从 `Content-Range: bytes a-b/total` 拿；200 就是 Content-Length
      int total = res.contentLength;
      if (resumed) {
        final String? cr = res.headers.value('content-range');
        final int slash = cr == null ? -1 : cr.lastIndexOf('/');
        if (slash >= 0 && cr != null) {
          total = int.tryParse(cr.substring(slash + 1)) ?? -1;
        }
      } else {
        have = 0; // 服务器没理 Range ⇒ 从头来（下面用 write 截断）
      }

      sink = resumed ? part.openWrite(mode: FileMode.append) : part.openWrite();
      _log('open part=${part.path} resumed=$resumed have=$have total=$total '
          'realfile=${part.existsSync()}');
      var got = have;
      onProgress?.call(got, total);
      await for (final List<int> chunk in res.timeout(const Duration(minutes: 5))) {
        if (cancel?.isCancelled ?? false) {
          throw _UpdateFailure('已取消', retryable: false);
        }
        sink.add(chunk);
        got += chunk.length;
        // 临时诊断：每 2 MB 记一次磁盘上的真实大小（看 IOSink 到底写没写下去）
        if (got ~/ (2 * 1024 * 1024) != (got - chunk.length) ~/ (2 * 1024 * 1024)) {
          _log('progress got=$got diskLen=${part.existsSync() ? part.lengthSync() : -1}');
        }
        onProgress?.call(got, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      // 长度自检：有的代理会"正常结束"却只给半截 ⇒ 宁可留 .part 也不改名
      if (total > 0 && got != total) {
        throw _UpdateFailure('下载不完整（$got / $total 字节）', retryable: true);
      }
      if (got == 0) throw _UpdateFailure('下载到 0 字节', retryable: true);
      if (done.existsSync()) {
        try {
          done.deleteSync();
        } catch (_) {}
      }
      await part.rename(done.path);
      return done.path;
    } on _UpdateFailure {
      rethrow;
    } on SocketException catch (e) {
      if (cancel?.isCancelled ?? false) {
        throw _UpdateFailure('已取消', retryable: false);
      }
      throw _UpdateFailure(_socketHint(e), retryable: true);
    } on TimeoutException {
      throw _UpdateFailure('下载超时', retryable: true);
    } catch (e) {
      if (cancel?.isCancelled ?? false) {
        throw _UpdateFailure('已取消', retryable: false);
      }
      throw _UpdateFailure('下载失败：${e.runtimeType}: $e', retryable: true);
    } finally {
      try {
        await sink?.close();
        _log('finally close ok  partExists=${part.existsSync()} '
            'partLen=${part.existsSync() ? part.lengthSync() : -1}');
      } catch (e) {
        _log('finally close 抛了: $e  partExists=${part.existsSync()}');
      }
      cancel?.detach();
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

  /// 下载过程的**诊断日志**（2026-10-28 晚临时加，定位完就删）
  ///
  /// 依次尝试三个位置，第一个能写的就写（内容里带**版本号 + exe 路径**，
  /// 这样"到底是不是这个构建在跑"一目了然）：
  ///   ① exe 同级目录（最好找）  ② `%USERPROFILE%\mathlang\`  ③ `%TEMP%`
  static void _log(String line) {
    final List<String> dirs = <String>[];
    try {
      dirs.add(File(Platform.resolvedExecutable).parent.path);
    } catch (_) {}
    final String home = Platform.environment['USERPROFILE'] ?? '';
    if (home.isNotEmpty) dirs.add('$home\\mathlang');
    try {
      dirs.add(Directory.systemTemp.path);
    } catch (_) {}
    final String body = '[${DateTime.now().toIso8601String()}] '
        'v$kAppVersion exe=${Platform.resolvedExecutable}  $line\n';
    for (final String d in dirs) {
      try {
        final Directory dir = Directory(d);
        if (!dir.existsSync()) dir.createSync(recursive: true);
        final File f = File('${dir.path}\\update-download.log');
        // 不让它长成垃圾：超过 64 KB 就从头写
        try {
          if (f.existsSync() && f.lengthSync() > 64 * 1024) f.deleteSync();
        } catch (_) {}
        f.writeAsStringSync(body, mode: FileMode.append, flush: true);
        return; // 写成功就够
      } catch (_) {
        // 换下一个位置
      }
    }
  }

  /// 更新包**下载到哪个目录**（2026-10-28 晚改）
  ///
  /// ★★★ 实测（日志抓到的，不是推理）：绿色版往 `%TEMP%` 写 `.part` 会被系统拒绝
  ///
  ///   ```
  ///   open part=C:\Users\…\Temp\mathlang-update-9.9.9.msix.part  realfile=false
  ///   progress got=2097152 diskLen=-1        ← 2 MB 了磁盘上还是没有
  ///   finally close 抛了: PathAccessException: 拒绝访问。(errno = 5)
  ///   ```
  ///
  ///   `File.openWrite()` 是**惰性**打开：开文件失败不会当场抛，数据先堆在内存里，
  ///   直到 `close()` 才报错 —— 于是进度条一路涨、磁盘一个字节都没有。
  ///   同一个路径同一个名字，PowerShell 写得进去 ⇒ 不是 ACL，是**这个进程**被限制。
  ///
  /// ⇒ 不再赌"哪个目录应该能写"，而是**运行时试写探测**（写一个 1 字节探针文件，
  ///   成功就删掉），按顺序挑第一个真能写的：
  ///   ① `%USERPROFILE%\mathlang\`（正常位置：跟设置/图标在一起，卸载选 N 就留着）
  ///   ② **exe 同级目录**（绿色版必可写；打包版只读会被跳过）
  ///   ③ `%TEMP%`
  ///   结果缓存在 [_dlDir]。
  static Directory? _dlDir;

  Directory _downloadDir() {
    final Directory? cached = _dlDir;
    if (cached != null) return cached;
    final List<Directory> cands = <Directory>[];
    final String home = Platform.environment['USERPROFILE'] ?? '';
    if (home.isNotEmpty) cands.add(Directory('$home\\mathlang'));
    try {
      cands.add(Directory(File(Platform.resolvedExecutable).parent.path));
    } catch (_) {}
    try {
      cands.add(Directory.systemTemp);
    } catch (_) {}
    for (final Directory d in cands) {
      try {
        if (!d.existsSync()) d.createSync(recursive: true);
        final File probe = File('${d.path}\\.mathlang-write-test');
        probe.writeAsStringSync('x', flush: true);
        probe.deleteSync();
        _dlDir = d;
        _log('下载目录选定 = ${d.path}');
        return d;
      } catch (e) {
        _log('下载目录不可写，跳过 ${d.path}（$e）');
      }
    }
    _dlDir = Directory.systemTemp;
    return Directory.systemTemp;
  }

  @override
  String get downloadsHint => _downloadDir().path;

  /// 所有"更新包文件"（**新目录 + 旧的 temp 都算**：老版本可能把半截文件留在 temp 里）
  List<File> _updatePayloadFiles() {
    final List<File> out = <File>[];
    final List<String> dirs = <String>[_downloadDir().path];
    try {
      final String t = Directory.systemTemp.path;
      if (!dirs.contains(t)) dirs.add(t);
    } catch (_) {}
    for (final String d in dirs) {
      try {
        for (final FileSystemEntity e
            in Directory(d).listSync(followLinks: false)) {
          if (e is! File) continue;
          final String name = e.uri.pathSegments.last.toLowerCase();
          if (!name.startsWith('mathlang-update-')) continue;
          if (!name.endsWith('.msix') && !name.endsWith('.msix.part')) continue;
          out.add(e);
        }
      } catch (_) {}
    }
    return out;
  }

  @override
  Future<int> downloadedUpdateFiles() async => _updatePayloadFiles().length;

  @override
  Future<int> downloadedUpdateBytes() async {
    var sum = 0;
    for (final File f in _updatePayloadFiles()) {
      try {
        sum += f.lengthSync();
      } catch (_) {}
    }
    return sum;
  }

  @override
  Future<int> clearDownloadedUpdates() async {
    final int before = await downloadedUpdateBytes();
    for (final File f in _updatePayloadFiles()) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
    final int after = await downloadedUpdateBytes();
    return before - after;
  }

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

      // ★★★ 2026-10-28 **第二次实测纠正（关键）**：
      //   上一版用 `Process.start('powershell', …, detached)` 起小助手 —— 脚本写出了，
      //   但**一次都没被执行**（result.txt / log.txt 都不存在）；而**手动从控制台跑同一个
      //   脚本就成功**（result.txt 立刻变成 ok:1.2.4）⇒ 不是脚本的问题，是"谁当它的爸爸"。
      //   根因：**MSIX 打包应用的进程跑在 Job 对象里，应用退出会连带杀掉所有子进程**
      //   ⇒ 我们起的 PowerShell 跟着我们一起死。
      //   ⇒ 现在改成**让 explorer 去启动**：先写一个 .cmd 中转，再用
      //     `explorer.exe <cmd>` —— explorer 把请求转交给已运行的 shell，
      //     新进程的父是 explorer、不在我们的 Job 里 ⇒ 我们退出它照样活着。
      //   代价：会闪一下 cmd 控制台（约 2~4 秒）；这是"能装上"的必要代价。
      final File cmd = File('$temp${sep}mathlang-update-$version.cmd');
      await cmd.writeAsString(
        '@echo off\r\n'
        'powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden '
        '-File "%~dp0mathlang-update-$version.ps1"\r\n',
        flush: true,
      );
      await Process.start(
        'explorer.exe',
        <String>[cmd.path],
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

  @override
  Future<void> revealFile(String path) async {
    try {
      await Process.start(
        'explorer.exe',
        <String>['/select,', path],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      // 打不开就算了：弹窗里还有可复制的路径
    }
  }

  /// 删掉过期的 `mathlang-update-*`（**新目录 + 旧的 temp 都清**）。
  ///
  /// · [onlyMsixAndScript] ⇒ 只删 msix / `.msix.part` / ps1（"装好了"那一支，立刻删）；
  /// · 否则只删 [olderThanDays] 天前的（兜底那条）。
  void _deleteOldUpdateFiles({bool onlyMsixAndScript = false, int olderThanDays = 3}) {
    try {
      final DateTime cutoff =
          DateTime.now().subtract(Duration(days: olderThanDays));
      final List<File> candidates = <File>[..._updatePayloadFiles()];
      // `.ps1` 小助手脚本只在 temp 里，单列一份
      try {
        for (final FileSystemEntity e
            in Directory.systemTemp.listSync(followLinks: false)) {
          if (e is! File) continue;
          final String n = e.uri.pathSegments.last.toLowerCase();
          if (!n.startsWith('mathlang-update-') || !n.endsWith('.ps1')) continue;
          candidates.add(e);
        }
      } catch (_) {}
      for (final File e in candidates) {
        final String name = e.uri.pathSegments.last.toLowerCase();
        final bool isPayload =
            name.endsWith('.msix') || name.endsWith('.msix.part');
        if (onlyMsixAndScript && !isPayload && !name.endsWith('.ps1')) continue;
        if (!onlyMsixAndScript) {
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
  Future<String> describeChannel() async {
    try {
      final List<InternetAddress> addrs = await InternetAddress.lookup(
        'api.github.com',
      ).timeout(const Duration(seconds: 3));
      if (addrs.any((InternetAddress a) => a.isLoopback)) {
        return '网络通道：本机加速工具（api.github.com → 127.0.0.1）';
      }
    } catch (_) {
      // 解析不了也算"正在尝试"
    }
    return '网络通道：正在尝试连接 GitHub';
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
