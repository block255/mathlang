// 数语引擎 · **检查更新的两个弹窗**（D1，2026-10-28）
//
// 用户 2026-10-28 定的形状：
//   ① 发现新版本：**暂不更新 / 前往发布页 / 一键更新** ＋ 「以后不再自动检查更新」勾选；
//   ② 更新完成：**立即重启 / 暂不重启**。
//
// 口径（同一次对话里定的）：
//   · 勾选 = **完全不再自动联网查**（设置页有同一个开关；手动「检查更新」照旧可用）；
//   · 不勾 + 「暂不更新」= **只跳过这一个版本**（由调用方把版本号记进设置）；
//   · 没有 msix 附件（或不是 MSIX 安装）⇒ **不显示「一键更新」**，只留前两个。

import 'package:flutter/material.dart';

import '../core/update_check.dart';
import '../core/version_ref.dart';

/// 用户在「发现新版本」里选了什么
enum UpdateChoice {
  /// 这次不更（记住这个版本，下次升版再说）
  later,

  /// 去 GitHub 发布页自己下
  openPage,

  /// 下载 + 装 + 重启
  install,
}

/// 弹窗结果：[choice] + 是否勾了「以后不再自动检查更新」
class UpdateDecision {
  const UpdateDecision(this.choice, {this.disableAuto = false});
  final UpdateChoice choice;
  final bool disableAuto;
}

/// ① 发现新版本
Future<UpdateDecision?> showUpdateAvailableDialog(
  BuildContext context, {
  required UpdateInfo info,
  required VersionRef current,
  required bool canInstall,
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
              Container(
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
                    info.notes.trim().isEmpty ? '（这次发布没有写更新说明）' : info.notes.trim(),
                    style: const TextStyle(fontSize: 12, height: 1.6),
                  ),
                ),
              ),
              if (!canInstall) ...<Widget>[
                const SizedBox(height: 8),
                const Text(
                  '这一版没有可一键安装的包 —— 用「前往发布页」下载后手动安装。',
                  style: TextStyle(fontSize: 11, color: Color(0xFFB7791F)),
                ),
              ],
              const SizedBox(height: 8),
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
        actions: <Widget>[
          TextButton(
            key: const Key('update-later'),
            onPressed: () => Navigator.of(ctx)
                .pop(UpdateDecision(UpdateChoice.later, disableAuto: disableAuto)),
            child: const Text('暂不更新'),
          ),
          TextButton(
            key: const Key('update-open-page'),
            onPressed: () => Navigator.of(ctx)
                .pop(UpdateDecision(UpdateChoice.openPage, disableAuto: disableAuto)),
            child: const Text('前往发布页'),
          ),
          FilledButton(
            key: const Key('update-install'),
            onPressed: canInstall
                ? () => Navigator.of(ctx)
                    .pop(UpdateDecision(UpdateChoice.install, disableAuto: disableAuto))
                : null,
            child: const Text('一键更新'),
          ),
        ],
      ),
    ),
  );
}

/// ② 更新完成 —— 返回 `true` = 立即重启
Future<bool> showUpdateDoneDialog(
  BuildContext context, {
  required UpdateInfo info,
}) async {
  final bool? restart = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext ctx) => AlertDialog(
      key: const Key('update-done-dialog'),
      title: Text('已更新到 ${info.version ?? info.tag}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('更新完成，本次改动已经生效。'),
            const SizedBox(height: 8),
            SelectableText(
              info.notes.trim().isEmpty ? '' : info.notes.trim(),
              style: const TextStyle(fontSize: 12, height: 1.6, color: Color(0xFF4A5568)),
            ),
            const SizedBox(height: 8),
            const Text('要现在重启到新版本吗？（不重启就继续用旧的，退出后再打开就是新版）',
                style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('update-restart-later'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('暂不重启'),
        ),
        FilledButton(
          key: const Key('update-restart-now'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('立即重启'),
        ),
      ],
    ),
  );
  return restart ?? false;
}
