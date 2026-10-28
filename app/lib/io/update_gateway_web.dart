// 数语引擎 · 检查更新的 **Web 空实现**
//
// Web 端只是开发实验台（`整体设计` §现行口径校正 2），不发布、也不该联网查更新。
// 所有方法都安静地失败：查不到 ⇒ null、装不了 ⇒ false、打不开 ⇒ 什么都不做。

import '../core/update_check.dart';
import 'update_gateway.dart';

UpdateGateway createUpdateGateway() => const WebUpdateGateway();

class WebUpdateGateway implements UpdateGateway {
  const WebUpdateGateway();

  @override
  bool get isPackaged => false;

  @override
  bool get supportsAutoCheck => false;

  @override
  String? get lastError => 'Web 端不做更新';

  @override
  Future<UpdateInfo?> checkLatest() async => null;

  @override
  Future<String?> downloadMsix(
    UpdateInfo info, {
    void Function(int got, int total)? onProgress,
    DownloadCancelToken? cancel,
  }) async =>
      null;

  @override
  String get downloadsHint => '';

  @override
  Future<int> downloadedUpdateFiles() async => 0;

  @override
  Future<int> downloadedUpdateBytes() async => 0;

  @override
  Future<int> clearDownloadedUpdates() async => 0;

  @override
  Future<bool> launchInstaller(
    String msixPath, {
    required String version,
    String notes = '',
    String pageUrl = '',
  }) async =>
      false;

  @override
  Future<String?> takeLastUpdateResult() async => null;

  @override
  Future<PendingUpdate?> takePendingInfo() async => null;

  @override
  Future<void> sweepOldUpdateFiles({int olderThanDays = 3}) async {}

  @override
  Future<String> describeChannel() async => '网络通道：Web 端不做更新';

  @override
  Future<void> revealFile(String path) async {}

  @override
  Future<void> openReleasePage(String url) async {}
}
