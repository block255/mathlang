// 1.2.10 守卫：**取消要真的取消**（2026-10-28 晚）
//
// 以前弹窗上的【取消】只让进度条别再更新，后台照样把安装包下完、照样写出文件 ——
// 「界面说取消，实际没停」。现在 `DownloadCancelToken.cancel()` 会掐断连接。
//
// 这里用**假连接**验证契约（不联网）：token 只依赖"挂上来的东西有 close(force:)"。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/io/update_gateway.dart';

/// 假连接：记录被关了几次
class _FakeClient {
  int closed = 0;
  bool lastForce = false;
  void close({bool force = false}) {
    closed++;
    lastForce = force;
  }
}

void main() {
  group('DownloadCancelToken', () {
    test('还没取消时 isCancelled = false', () {
      expect(DownloadCancelToken().isCancelled, isFalse);
    });

    test('cancel ⇒ isCancelled = true', () {
      final DownloadCancelToken t = DownloadCancelToken()..cancel();
      expect(t.isCancelled, isTrue);
    });

    test('cancel 会**真的关掉**挂上来的连接（force = true）', () {
      final _FakeClient c = _FakeClient();
      final DownloadCancelToken t = DownloadCancelToken()..attach(c);
      t.cancel();
      expect(c.closed, 1, reason: '必须真的 close —— 否则带宽还在被吃');
      expect(c.lastForce, isTrue, reason: '要 force，普通 close 会等当前块写完');
    });

    test('重复 cancel 只关一次（幂等）', () {
      final _FakeClient c = _FakeClient();
      final DownloadCancelToken t = DownloadCancelToken()..attach(c);
      t.cancel();
      t.cancel();
      t.cancel();
      expect(c.closed, 1);
    });

    test('detach 之后取消不再碰那个连接（下载已经收尾了）', () {
      final _FakeClient c = _FakeClient();
      final DownloadCancelToken t = DownloadCancelToken()..attach(c);
      t.detach();
      t.cancel();
      expect(c.closed, 0);
      expect(t.isCancelled, isTrue, reason: '仍然要记下"用户取消了"');
    });
  });
}
