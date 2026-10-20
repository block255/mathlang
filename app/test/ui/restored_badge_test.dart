// ★★ 2026-10-20（T-A 实测 F12）：**新建 / 打开之后「已恢复上次编辑」徽标要收掉**。
//
// 改前现场：新建一份文档、改两笔之后，顶栏那个蓝色徽标还挂着 ——
// 用户会以为"这份新文档是从暂存恢复的"，而且它旁边就是文档名，像是给这份文档打的标签。
//
// 根因：`_restored` 只在"真的从暂存恢复"时置 true，`newDocument()` / `openDocument()`
// 换文档时没清。修法：那两处 `setState` 里清掉（`openDocument` 走同一条）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/io/session_data.dart';
import 'package:mathlang/io/session_store.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/fake_file_gateway.dart';
import '../support/symbol_fixture.dart';

/// 只返回一份固定会话的假 store（其余方法都空转）
class _FakeSession implements SessionStore {
  _FakeSession(this.data);

  final SessionData? data;

  @override
  int saveCount = 0;

  @override
  Future<SessionData?> load() async => data;

  @override
  Future<bool> save(SessionData d) async {
    saveCount++;
    return true;
  }

  @override
  Future<void> clear() async {}

  @override
  Future<String> describe() async => '假的暂存位置';
}

const String kText = '甲乙丙';
const String kBadge = '已恢复上次编辑';

Future<EditorPageState> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final _FakeSession store = _FakeSession(const SessionData(
    text: kText,
    title: '未命名文档',
    savedText: kText, // 与正文一致 ⇒ 不脏 ⇒ 新建不会弹确认框
    caret: 1,
    anchor: 1,
  ));
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(
      library: testSymbolLibrary(),
      gateway: FakeFileGateway(),
      session: store,
    ),
  ));
  await tester.pumpAndSettle();
  return tester.state<EditorPageState>(find.byType(EditorPage));
}

void main() {
  testWidgets('★ F12：恢复出来的会话 ⇒ 徽标在；点「新建」之后 ⇒ 徽标收掉',
      (WidgetTester tester) async {
    final EditorPageState st = await _pump(tester);
    expect(st.sessionRestored, isTrue);
    expect(find.text(kBadge), findsOneWidget, reason: '恢复的会话要告诉用户一声');

    await st.newDocument();
    await tester.pumpAndSettle();

    expect(st.sessionRestored, isFalse, reason: '新建的文档不是恢复来的');
    expect(find.text(kBadge), findsNothing,
        reason: '改前徽标一直挂着（用户会以为这份新文档是从暂存恢复的）');
  });

  testWidgets('★ F12：点掉徽标本身也要能收起（既有能力不许退化）',
      (WidgetTester tester) async {
    final EditorPageState st = await _pump(tester);
    await tester.tap(find.text(kBadge));
    await tester.pumpAndSettle();
    expect(st.sessionRestored, isFalse);
    expect(find.text(kBadge), findsNothing);
  });
}
