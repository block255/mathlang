// 数语引擎 · **检查更新的四个弹窗**（D1，2026-10-28；1.2.1 起改"外挂小助手"）
//
// 为什么不用底部提示条（snackbar）：实测 2026-10-28 —— 用户点「一键更新」后我弹了一条
// snack，紧接着为了降级打开了浏览器，**浏览器抢了前台，那条提示等于没看见**。
// 更新这种事必须用**界面内独立的弹窗**（用户原话：「应该有一个界面内独立的弹窗吧对吧」）。
//
// 四个弹窗：
//   ① 发现新版本（暂不更新 / 前往发布页 / 一键更新 + 「以后不再自动检查」）
//   ② 下载进度（**一个窗口两态**：下载中 → 下载完问"要不要现在装"）
//   ③ 已更新（下次启动时）
//   ④ 上次没装成（下次启动时）

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/update_check.dart';
import '../core/version_ref.dart';

/// 用户在「发现新版本」里选了什么
enum UpdateChoice {
  /// **只关这次弹窗** —— 什么都不记，下次启动照样弹（2026-10-28 晚用户拍板）
  later,

  /// **忽略这一个版本** —— 记进 `updateIgnoredVersion`，出更新的版本再弹
  ignoreVersion,

  /// 去 GitHub 发布页自己下
  openPage,

  /// 走「下载 → 外挂小助手装 → 自动起新版」
  install,
}

/// 弹窗结果：[choice] + 是否勾了「以后不再自动检查更新」
class UpdateDecision {
  const UpdateDecision(this.choice, {this.disableAuto = false});
  final UpdateChoice choice;
  final bool disableAuto;

  @override
  String toString() => 'UpdateDecision($choice, disableAuto=$disableAuto)';
}

/// ① 发现新版本
Future<UpdateDecision?> showUpdateAvailableDialog(
  BuildContext context, {
  required UpdateInfo info,
  required VersionRef current,
  required bool canInstall,
  /// 有安装包可下（绿色版：能下不能装 ⇒ 按钮写"下载更新包"）
  bool canDownload = false,
  bool autoCheckEnabled = true,
}) {
  bool disableAuto = false;
  final VersionRef? latest = info.version;
  return showDialog<UpdateDecision>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, StateSetter setSt) => AlertDialog(
        key: const Key('update-available-dialog'),
        title: Text('发现新版本 ${latest ?? info.tag}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('当前 $current · 最新 ${latest ?? info.tag}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
              const SizedBox(height: 10),
              const Text('更新说明', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              _NotesBox(notes: info.notes),
              if (!canInstall) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  canDownload
                      ? '绿色版没有包身份，不能自动安装 —— 点【下载更新包】会下好并把路径给你。'
                      : '这一版没有可安装的包 —— 用「前往发布页」下载后手动安装。',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFB7791F)),
                ),
              ],
              const SizedBox(height: 8),
              // ★ 两个"不更"按钮的区别要写在按钮**旁边**，否则用户以为它们一样
              const Text(
                '暂不更新 = 只关掉这一次（下次启动还会提醒）\n'
                '忽略此版本 = 这一个版本不再提醒（出了更新的版本还会提醒）',
                style: TextStyle(fontSize: 11, height: 1.5, color: Color(0xFF718096)),
              ),
              InkWell(
                key: const Key('update-disable-auto'),
                onTap: () => setSt(() => disableAuto = !disableAuto),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Checkbox(
                      value: disableAuto,
                      onChanged: (bool? v) => setSt(() => disableAuto = v ?? false),
                    ),
                    const Flexible(
                      child: Text('以后不再自动检查更新（设置里可以改回来）',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
              if (!autoCheckEnabled)
                const Padding(
                  padding: EdgeInsets.only(left: 34, top: 2),
                  child: Text('（自动检查现在是关着的 —— 这次是手动查的）',
                      style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
                ),
            ],
          ),
        ),
        // ★ 2026-10-28 晚（用户拍板）：两个"不更"的理由必须**看得见地区别开** ——
        //   · 暂不更新 = 只关这次，下次启动照样弹；
        //   · 忽略此版本 = 跳过这一个版本，出更新的再说。
        //   四个按钮一行太挤 ⇒ 左边两个用文字按钮、右边两个是主操作。
        actionsPadding: const EdgeInsets.fromLTRB(8, 0, 12, 12),
        actions: <Widget>[
          TextButton(
            key: const Key('update-later'),
            onPressed: () => Navigator.of(ctx)
                .pop(UpdateDecision(UpdateChoice.later, disableAuto: disableAuto)),
            child: const Text('暂不更新'),
          ),
          TextButton(
            key: const Key('update-ignore-version'),
            onPressed: () => Navigator.of(ctx).pop(
                UpdateDecision(UpdateChoice.ignoreVersion, disableAuto: disableAuto)),
            child: const Text('忽略此版本'),
          ),
          TextButton(
            key: const Key('update-open-page'),
            onPressed: () => Navigator.of(ctx)
                .pop(UpdateDecision(UpdateChoice.openPage, disableAuto: disableAuto)),
            child: const Text('前往发布页'),
          ),
          FilledButton(
            key: const Key('update-install'),
            onPressed: (canInstall || canDownload)
                ? () => Navigator.of(ctx)
                    .pop(UpdateDecision(UpdateChoice.install, disableAuto: disableAuto))
                : null,
            child: Text(canInstall ? '一键更新' : '下载更新包'),
          ),
        ],
      ),
    ),
  );
}

/// ② 下载进度弹窗的状态（**由调用方驱动**，弹窗只负责显示）
enum DownloadPhase { downloading, ready, failed }

class DownloadUiState {
  const DownloadUiState({
    this.phase = DownloadPhase.downloading,
    this.got = 0,
    this.total = -1,
    this.speed = 0,
    this.error,
    this.path,
  });

  final DownloadPhase phase;

  /// 已下字节
  final int got;

  /// 总字节（未知 ⇒ -1）
  final int total;

  /// 当前速度（字节/秒，滑动平均；0 = 还算不出来）
  final double speed;

  /// 失败原因（[phase] == failed 时有值）
  final String? error;

  /// 下好的本地路径（[phase] == ready 时有值）
  final String? path;

  double get ratio => total > 0 ? (got / total).clamp(0.0, 1.0) : 0.0;

  DownloadUiState copyWith({
    DownloadPhase? phase,
    int? got,
    int? total,
    double? speed,
    String? error,
    String? path,
  }) =>
      DownloadUiState(
        phase: phase ?? this.phase,
        got: got ?? this.got,
        total: total ?? this.total,
        speed: speed ?? this.speed,
        error: error ?? this.error,
        path: path ?? this.path,
      );
}

/// ② 下载进度 / 安装确认 —— **一个窗口两态**
///
/// 返回：[UpdateChoice.install] = 现在安装（调用方随后要退出进程）、
/// [UpdateChoice.later] = 稍后再说、[UpdateChoice.openPage] = 去发布页（下载失败时）。
Future<UpdateChoice?> showUpdateDownloadDialog(
  BuildContext context, {
  required UpdateInfo info,
  required ValueListenable<DownloadUiState> state,
  required VoidCallback onCancelDownload,
  String channelText = '',
}) {
  return showDialog<UpdateChoice>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext ctx) => ValueListenableBuilder<DownloadUiState>(
      valueListenable: state,
      builder: (BuildContext ctx, DownloadUiState s, _) {
        final bool downloading = s.phase == DownloadPhase.downloading;
        final bool failed = s.phase == DownloadPhase.failed;
        final String ver = (info.version ?? info.tag).toString();
        return AlertDialog(
          key: const Key('update-progress-dialog'),
          title: Text(failed
              ? '更新没有完成'
              : downloading
                  ? '正在下载 1.2.0'.replaceAll('1.2.0', ver)
                  : '准备安装 $ver'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (downloading) ...<Widget>[
                  const Text('正在下载安装包…'),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    key: const Key('update-progress-bar'),
                    value: s.total > 0 ? s.ratio : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.total > 0
                        ? '${_mb(s.got)} / ${_mb(s.total)} MB · '
                            '${(s.ratio * 100).toStringAsFixed(0)}%${_speedText(s)}'
                        : '${_mb(s.got)} MB（总大小未知）${_speedText(s)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF4A5568)),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    channelText.isEmpty
                        ? '正在尝试连接 GitHub；中途断了会自动重试一次。'
                        : '$channelText；中途断了会自动重试一次。',
                    key: const Key('update-channel-text'),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF718096)),
                  ),
                ] else if (failed) ...<Widget>[
                  Text('原因：${s.error ?? '未知'}',
                      key: const Key('update-failed-reason'),
                      style: const TextStyle(fontSize: 13, color: Color(0xFFB7791F))),
                  const SizedBox(height: 8),
                  const Text('文档和设置都没有动，你还是原来的版本。',
                      style: TextStyle(fontSize: 12, color: Color(0xFF4A5568))),
                ] else ...<Widget>[
                  Text('安装包已下载好（${_mb(s.got)} MB）。',
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 10),
                  const Text(
                    '⚠ Windows 要求安装时必须**关闭本程序**（它不允许边跑边装）。'
                    '点【现在安装】之后：',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                  const SizedBox(height: 6),
                  const Text('① 这个窗口会关闭\n② 约 10~20 秒后自动打开新版本',
                      style: TextStyle(fontSize: 12, height: 1.6)),
                  const SizedBox(height: 8),
                  const Text(
                    '文档与设置不受影响；万一失败，应用会重新打开并告诉你原因。',
                    style: TextStyle(fontSize: 11, color: Color(0xFF718096)),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            if (downloading)
              TextButton(
                key: const Key('update-cancel-download'),
                onPressed: () {
                  onCancelDownload();
                  Navigator.of(ctx).pop(UpdateChoice.later);
                },
                child: const Text('取消'),
              ),
            if (failed) ...<Widget>[
              TextButton(
                key: const Key('update-close-dialog'),
                onPressed: () => Navigator.of(ctx).pop(UpdateChoice.later),
                child: const Text('知道了'),
              ),
              FilledButton(
                key: const Key('update-open-page'),
                onPressed: () => Navigator.of(ctx).pop(UpdateChoice.openPage),
                child: const Text('前往发布页'),
              ),
            ],
            if (!downloading && !failed) ...<Widget>[
              TextButton(
                key: const Key('update-install-later'),
                onPressed: () => Navigator.of(ctx).pop(UpdateChoice.later),
                child: const Text('稍后再说'),
              ),
              FilledButton(
                key: const Key('update-install-now'),
                onPressed: () => Navigator.of(ctx).pop(UpdateChoice.install),
                child: const Text('现在安装'),
              ),
            ],
          ],
        );
      },
    ),
  );
}

/// ③ 已更新（下次启动时弹）
Future<void> showUpdateInstalledDialog(
  BuildContext context, {
  required String version,
  String? notes,
}) =>
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        key: const Key('update-installed-dialog'),
        title: Text('已更新到 $version'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('更新完成，本次改动已经生效。'),
              if (notes != null && notes.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                _NotesBox(notes: notes),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          FilledButton(
            key: const Key('update-installed-ok'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );

/// ④ 上次没装成（下次启动时弹）
///
/// [reason] 是安装器报的原因；[msixPath] 是**下好的安装包在哪** ——
/// 用户 2026-10-28 明确要求：安装失败时要把这个路径摆出来（可复制、可手动装）。
///
/// 返回 true = 用户要去发布页。
Future<bool> showUpdateFailedDialog(
  BuildContext context, {
  required String reason,
  required String currentVersion,
  String? msixPath,
}) async {
  final bool? go = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      key: const Key('update-failed-dialog'),
      title: const Text('上次更新没成功'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SelectableText(reason,
                style: const TextStyle(fontSize: 12, color: Color(0xFFB7791F))),
            const SizedBox(height: 8),
            Text('你现在还是 $currentVersion —— 文档和设置都没有动。',
                style: const TextStyle(fontSize: 12, color: Color(0xFF4A5568))),
            if (msixPath != null && msixPath.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              const Text('安装包已经下载好了，就放在这里（可以复制后手动安装）：',
                  style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: SelectableText(msixPath,
                    key: const Key('update-failed-msix-path'),
                    style: const TextStyle(fontSize: 11, height: 1.5)),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const Key('update-failed-copy-path'),
                  onPressed: () async {
                    // 剪贴板在测试里没有平台实现 ⇒ 失败也无所谓，提示照给
                    try {
                      await Clipboard.setData(ClipboardData(text: msixPath));
                    } catch (_) {}
                    if (!ctx.mounted) return;
                    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
                      const SnackBar(content: Text('路径已复制')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('复制路径'),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('update-failed-ok'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('知道了'),
        ),
        FilledButton(
          key: const Key('update-failed-open-page'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('前往发布页'),
        ),
      ],
    ),
  );
  return go ?? false;
}

/// 更新说明的小框（三个弹窗共用）
class _NotesBox extends StatelessWidget {
  const _NotesBox({required this.notes});
  final String notes;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 220),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFC),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: SingleChildScrollView(
          child: SelectableText(
            notes.trim().isEmpty ? '（这次发布没有写更新说明）' : notes.trim(),
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
        ),
      );
}

String _mb(int bytes) =>
    bytes <= 0 ? '0' : (bytes / 1024 / 1024).toStringAsFixed(1);

/// 速度 / 剩余时间（算不出来就空着，不显示 "0 KB/s" 那种噪音）
String _speedText(DownloadUiState s) {
  if (s.speed <= 0) return '';
  final String sp = s.speed >= 1024 * 1024
      ? '${(s.speed / 1024 / 1024).toStringAsFixed(1)} MB/s'
      : '${(s.speed / 1024).toStringAsFixed(0)} KB/s';
  if (s.total <= s.got) return ' · $sp';
  final double left = (s.total - s.got) / s.speed;
  final String eta = left >= 60
      ? '剩余约 ${(left / 60).ceil()} 分'
      : '剩余约 ${left.ceil()} 秒';
  return ' · $sp · $eta';
}
