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
  Future<UpdateInfo?> checkLatest() async => null;

  @override
  Future<String?> downloadMsix(UpdateInfo info) async => null;

  @override
  Future<bool> installMsix(String path) async => false;

  @override
  Future<void> relaunch() async {}

  @override
  Future<void> openReleasePage(String url) async {}
}
