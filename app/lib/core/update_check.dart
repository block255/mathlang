// 数语引擎 · **检查更新的判据**（D1，2026-10-28）
//
// 三件事，全是纯函数（可不联网单测）：
//   ① `UpdateInfo` + `parseLatestRelease`：GitHub `releases/latest` 的 JSON → 我们要的东西；
//   ② `shouldAutoCheck`：启动时**该不该**自动查（限频，别每次开机都弹）；
//   ③ `shouldPromptUpdate`：查到了**该不该弹窗**（用户 2026-10-28 定的规则）。
//
// 用户定的规则（原话摘要）：
//   · 启动后**静默**检查，"没发现就无异常，有发现才弹窗"；
//   · 弹窗三个选项：暂不更新 / 前往发布页 / 一键更新；带「以后不再自动检查更新」勾选；
//   · 勾上勾选 ⇒ **完全不再自动联网查**（手动「检查更新」照旧可用）；
//   · 不勾 + 点「暂不更新」⇒ **只跳过这一个版本**（下次升版还会提示）。
//
// ★ 网络失败**不弹窗**，但要**留痕**（设置页「上次检查失败：网络不可用」）——
//   设计原则 5「静默失败必须可见」。这一条由 UI 层照 `UpdateCheck.failed` 写。

import 'version_ref.dart';

/// GitHub Release 里我们关心的那几样。
class UpdateInfo {
  const UpdateInfo({
    required this.tag,
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.msixUrl,
    this.msixSize,
  });

  /// 原始 tag（`v1.2.0`）
  final String tag;

  /// 解析出来的版本（解析不了 ⇒ null，那份 release 就当没有）
  final VersionRef? version;

  /// 更新说明（Release 的 `body`，原样显示）
  final String notes;

  /// 发布页（`html_url`）—— 「前往发布页」用它
  final String pageUrl;

  /// 安装包直链（`assets[]` 里第一份 `*.msix` 的 `browser_download_url`）
  ///
  /// ★ 为什么按**后缀**找而不是拼 URL：GitHub 会丢弃非 ASCII 附件名
  ///   （全局笔记「Flutter 开发实战经验」#60），名字只能约定成 `mathlang-<ver>-x64.msix`；
  ///   按后缀找就不怕以后改前缀。
  final String? msixUrl;

  final int? msixSize;

  /// 能不能一键更新（没有 msix 附件 ⇒ 只能「前往发布页」）
  bool get canInstall => msixUrl != null;

  /// 从 `GET /repos/{owner}/{repo}/releases/latest` 的 JSON 解析。
  ///
  /// 解析不了（不是 Map / 没有 tag / tag 不像版本）⇒ `null`。
  static UpdateInfo? tryParse(Object? json) {
    if (json is! Map) return null;
    final String tag = (json['tag_name'] ?? '').toString().trim();
    if (tag.isEmpty) return null;
    final VersionRef? ver = VersionRef.tryParse(tag);
    if (ver == null) return null;
    final String page = (json['html_url'] ?? '').toString().trim();
    String? msix;
    int? msixSize;
    final Object? assets = json['assets'];
    if (assets is List) {
      for (final Object? a in assets) {
        if (a is! Map) continue;
        final String name = (a['name'] ?? '').toString().toLowerCase();
        if (!name.endsWith('.msix')) continue;
        final String url = (a['browser_download_url'] ?? '').toString().trim();
        if (url.isEmpty) continue;
        msix = url;
        final Object? size = a['size'];
        if (size is int) msixSize = size;
        break;
      }
    }
    return UpdateInfo(
      tag: tag,
      version: ver,
      notes: (json['body'] ?? '').toString(),
      pageUrl: page,
      msixUrl: msix,
      msixSize: msixSize,
    );
  }
}

/// 一次检查的结果（UI 与"上次检查"那一行都按它显示）
enum UpdateCheck {
  /// 发现更新的版本 ⇒ **弹窗**
  newer,

  /// 已是最新 ⇒ 静默
  upToDate,

  /// 网络/解析失败 ⇒ 静默，但设置页留痕
  failed,
}

/// 启动时**该不该自动查**。
///
/// ★★★ 2026-10-28 晚（用户实测推翻"限频"）：原来按"距上次 ≥24 小时"限频，
///   结果是 —— 装完新版启动查过一次（当时已是最新），我几分钟后发了更新的版本，
///   用户再启动时**24 小时内不再查** ⇒ **自动弹窗一次都没出现过**。
///   用户的原话：「这个软件数学编辑的定位就注定一天之内不会频繁多次打开」⇒
///   **去掉限频，每次启动查一次**。
///   代价只是一个 HTTPS GET（~1 KB）、静默、不阻塞；已是最新时一声不吭。
///   真不想查就关掉「以后不再自动检查更新」（那是明确意愿，不是限频）。
///
/// `updateLastCheckAt` 从此**只用来显示**"上次检查 X"，不再参与判断。
bool shouldAutoCheck({required bool enabled}) => enabled;

/// 查到了最新版，**该不该弹窗**。
///
/// · 不比当前版本新 ⇒ 不弹（已是最新，静默）；
/// · [manual]（用户自己点了「检查更新」）⇒ **只要更新就弹**（他主动问的，无视"忽略过"）；
/// · 自动检查 ⇒ 只跳过**用户点过「忽略此版本」**的那一个版本。
///
/// ★ 2026-10-28 晚（用户拍板）：弹窗拆成两个"不更"的理由 ——
///   · **暂不更新** = 只关这次，**下次启动依旧弹**（什么都不记）；
///   · **忽略此版本** = 记进 `updateIgnoredVersion`，等下一个版本再说。
bool shouldPromptUpdate({
  required VersionRef? current,
  required VersionRef? latest,
  String ignoredVersion = '',
  required bool manual,
}) {
  if (current == null || latest == null) return false;
  if (!latest.isNewerThan(current)) return false;
  if (manual) return true;
  return ignoredVersion.trim() != latest.toString();
}
