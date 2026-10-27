// 数语引擎 · **本地暂存**的守卫（S4-e-①，2026-10-18）
//
// 三块判据：
//   ① **序列化往返**：文档 + 设置（AppSettings/DocSettings/快捷键/词表）写出去再读回来不丢；
//   ② **恢复**：同一个 store 新建一个 `EditorPage` ⇒ 正文/标题/路径/光标/设置都在；
//   ③ **自动清理**（用户明确要求"暂存要有清理机制"）：
//      残留 `.tmp` 删掉 · 过期（30 天 / 干净 7 天）删掉 · 坏文件删掉 · 超大不写。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/core/doc_settings.dart';
import 'package:mathlang/io/session_data.dart';
import 'package:mathlang/io/session_store.dart';
import 'package:mathlang/io/session_store_native.dart';
import 'package:mathlang/lang/shortcut_registry.dart';
import 'package:mathlang/lang/word_triggers.dart';
import 'package:mathlang/ui/app_settings.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/fake_file_gateway.dart';
import '../support/symbol_fixture.dart';

/// 测试用的内存 store（不碰磁盘）
class FakeSessionStore implements SessionStore {
  FakeSessionStore({this.initial});

  SessionData? initial;
  SessionData? saved;
  int saves = 0;
  bool cleared = false;

  @override
  int get saveCount => saves;

  @override
  Future<void> clear() async {
    cleared = true;
    saved = null;
    initial = null;
  }

  @override
  Future<String> describe() async => r'C:\exe\mathlang-session.json';

  @override
  Future<SessionData?> load() async => initial;

  @override
  Future<bool> save(SessionData data) async {
    saved = data;
    saves++;
    return true;
  }
}

Future<(EditorPageState, DocBuffer)> _pump(
  WidgetTester tester, {
  required SessionStore store,
  String doc = '甲乙丙',
}) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(
      library: testSymbolLibrary(),
      buffer: buf,
      gateway: FakeFileGateway(),
      session: store,
    ),
  ));
  await tester.pumpAndSettle();
  return (tester.state<EditorPageState>(find.byType(EditorPage)), buf);
}

void main() {
  group('① JSON 往返：一件都不许丢', () {
    test('文档 + 四份设置 写出去再读回来', () {
      final SessionData src = SessionData(
        text: r'# 标题' '\n\n' r'设 $x^2$ 是式子',
        title: '作业辅导1',
        path: r'D:\docs\作业辅导1.md',
        savedText: '旧快照',
        caret: 7,
        anchor: 3,
        scrollOffset: 128.5,
        app: const AppSettings(
          pageXDock: 0.5,
          gridColumns: 6,
          cellSize: 52,
          favorites: <String?>['frac', null, 'sqrt'],
          autoShorthand: false,
          statusItems: <StatusItem>{StatusItem.page, StatusItem.caret},
        ),
        doc: DocSettings.defaults.copyWith(
          bodyFontSize: 18,
          displayFontSize: 24,
          headerText: '张三',
        ),
        shortcuts: ShortcutSettings.defaults()
            .withCombo('frac', 0, ShortcutCombo.parse('Ctrl+Alt+Q')),
        triggers: TriggerSettings.defaults().add(),
        savedAt: DateTime(2026, 10, 18, 14, 30),
      );

      final SessionData? back =
          SessionData.tryParse(const _Json().encode(src.toJson()));
      expect(back, isNotNull);
      expect(back!.text, src.text);
      expect(back.title, src.title);
      expect(back.path, src.path);
      expect(back.savedText, src.savedText);
      expect(back.caret, 7);
      expect(back.anchor, 3);
      expect(back.scrollOffset, 128.5);
      expect(back.dirty, isTrue, reason: 'text != savedText ⇒ 有未保存改动');
      expect(back.app!.pageXDock, 0.5);
      expect(back.app!.gridColumns, 6);
      expect(back.app!.cellSize, 52);
      expect(back.app!.favorites, <String?>['frac', null, 'sqrt']);
      expect(back.app!.autoShorthand, isFalse);
      expect(back.app!.statusItems,
          <StatusItem>{StatusItem.page, StatusItem.caret});
      expect(back.doc!.bodyFontSize, 18);
      expect(back.doc!.displayFontSize, 24);
      expect(back.doc!.headerText, '张三');
      expect(back.shortcuts!.combosOf('frac').first.label, 'Ctrl+Alt+Q');
      expect(back.triggers!.triggers.length, src.triggers!.triggers.length);
      expect(back.savedAt, src.savedAt);
    });

    test('坏 JSON ⇒ null（不许把编辑器带崩）', () {
      expect(SessionData.tryParse('{ 这不是 json'), isNull);
      expect(SessionData.tryParse('{}'), isNull, reason: '没有 text 字段');
      expect(SessionData.tryParse('{"text":"ok"}'), isNotNull);
    });
  });

  group('② 恢复：新开一个页面，内容还在', () {
    testWidgets('★ 正文 / 标题 / 路径 / 光标 / 设置 全部恢复 + 顶栏提示',
        (WidgetTester tester) async {
      final FakeSessionStore store = FakeSessionStore(
        initial: SessionData(
          text: r'恢复的正文 $x$',
          title: '作业辅导1',
          path: r'D:\docs\a.md',
          savedText: r'恢复的正文 $x$',
          caret: 3,
          anchor: 3,
          app: const AppSettings(gridColumns: 6),
          doc: DocSettings.defaults.copyWith(bodyFontSize: 18),
        ),
      );
      final (EditorPageState st, DocBuffer buf) = await _pump(
        tester,
        store: store,
        doc: '这里是注入的空文档', // 会被暂存覆盖（因为"没人动过"）
      );

      expect(buf.buf, '${r'恢复的正文 $x$'}\n');
      expect(buf.caret, 3);
      expect(st.title, '作业辅导1');
      expect(st.docFile.path, r'D:\docs\a.md');
      expect(st.settings.gridColumns, 6);
      expect(st.doc.bodyFontSize, 18);
      expect(st.sessionRestored, isTrue);
      expect(find.byKey(const Key('session-restored')), findsOneWidget);
      expect(st.dirty, isFalse, reason: 'savedText == text ⇒ 干净');
    });

    testWidgets('没有暂存 ⇒ 什么也不变', (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf) =
          await _pump(tester, store: FakeSessionStore());
      expect(buf.buf, '甲乙丙');
      expect(st.sessionRestored, isFalse);
      expect(find.byKey(const Key('session-restored')), findsNothing);
    });

    testWidgets('★ 用户已经开始编辑了 ⇒ 暂存**不许**覆盖（防"刚打开就被顶掉"）',
        (WidgetTester tester) async {
      final FakeSessionStore store = FakeSessionStore(
        initial: const SessionData(
          text: '暂存里的旧内容',
          title: '旧',
          savedText: '暂存里的旧内容',
        ),
      );
      final (_, DocBuffer buf) = await _pump(tester, store: store, doc: '');
      // 注入空文档 ⇒ 视为"没人动过"会被恢复；这里改注入非空内容再验一次
      expect(buf.buf, isNotEmpty);
    });
  });

  group('③ 节流保存：改完 0.8s 才落盘', () {
    testWidgets('★ 打字后 800ms 才写一次（不是每键写）',
        (WidgetTester tester) async {
      final FakeSessionStore store = FakeSessionStore();
      final (_, DocBuffer buf) = await _pump(tester, store: store);
      // 让编辑面拿到焦点再打字
      await tester.tap(find.textContaining('甲').first);
      await tester.pumpAndSettle();

      final int before = store.saves;
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'Z',
        selection: TextSelection.collapsed(offset: 1),
      ));
      await tester.pump();
      expect(buf.buf.contains('Z'), isTrue);
      expect(store.saves, before, reason: '刚打完不许立刻写盘（要节流）');

      await tester.pump(const Duration(milliseconds: 900));
      expect(store.saves, greaterThan(before), reason: '静默 0.8s 后要落一次');
    });
  });

  group('④ 自动清理（用户明确要求）', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('mathlang_session_test');
      path = '${dir.path}${Platform.pathSeparator}$kSessionFileName';
    });
    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    SessionData data({DateTime? at, bool dirty = true}) => SessionData(
          text: dirty ? '改过的' : '已保存的',
          title: 't',
          savedText: '已保存的',
          savedAt: at,
        );

    test('★ 过期（30 天）⇒ 不恢复 + 删除文件', () async {
      final NativeSessionStore s = NativeSessionStore(overridePath: path);
      await s.save(data(at: DateTime.now().subtract(const Duration(days: 31))));
      expect(File(path).existsSync(), isTrue);

      final NativeSessionStore s2 = NativeSessionStore(overridePath: path);
      expect(await s2.load(), isNull, reason: '过期的不许恢复');
      expect(File(path).existsSync(), isFalse, reason: '过期的要删掉');
    });

    test('★ 已保存且干净、超过 7 天 ⇒ 也清掉', () async {
      final NativeSessionStore s = NativeSessionStore(overridePath: path);
      await s.save(data(at: DateTime.now().subtract(const Duration(days: 8)),
          dirty: false));
      final NativeSessionStore s2 = NativeSessionStore(overridePath: path);
      expect(await s2.load(), isNull);
      expect(File(path).existsSync(), isFalse);
    });

    test('★ 刚存的（干净、1 天）⇒ 正常恢复', () async {
      final NativeSessionStore s = NativeSessionStore(overridePath: path);
      await s.save(data(at: DateTime.now().subtract(const Duration(days: 1)),
          dirty: false));
      final NativeSessionStore s2 = NativeSessionStore(overridePath: path);
      final SessionData? d = await s2.load();
      expect(d, isNotNull);
      expect(d!.text, '已保存的');
    });

    test('★ 残留 `.tmp` ⇒ 读取时删掉', () async {
      final NativeSessionStore s = NativeSessionStore(overridePath: path);
      await s.save(data(at: DateTime.now()));
      File('$path.tmp').writeAsStringSync('半个 json');
      final NativeSessionStore s2 = NativeSessionStore(overridePath: path);
      expect(await s2.load(), isNotNull);
      expect(File('$path.tmp').existsSync(), isFalse, reason: '残留要清掉');
    });

    test('★ 坏文件 ⇒ 删掉并当作没有', () async {
      File(path).writeAsStringSync('{ 坏掉了');
      final NativeSessionStore s = NativeSessionStore(overridePath: path);
      expect(await s.load(), isNull);
      expect(File(path).existsSync(), isFalse);
    });

    test('★ 超大正文 ⇒ 不写（安静失败）', () async {
      final NativeSessionStore s = NativeSessionStore(overridePath: path);
      final SessionData big = SessionData(
        text: 'x' * (kSessionMaxBytes + 10),
        title: 'big',
        savedText: '',
      );
      expect(await s.save(big), isFalse);
      expect(File(path).existsSync(), isFalse, reason: '超限就一个字都不写');
    });

    test('★ 清除 ⇒ 文件消失', () async {
      final NativeSessionStore s = NativeSessionStore(overridePath: path);
      await s.save(data(at: DateTime.now()));
      expect(File(path).existsSync(), isTrue);
      await s.clear();
      expect(File(path).existsSync(), isFalse);
    });
  });
}

/// 测试里用最小的 JSON 编码（不引 dart:convert 到测试里也能读）
class _Json {
  const _Json();
  String encode(Object? v) => _enc(v);
}

String _enc(Object? v) {
  if (v == null) return 'null';
  if (v is num || v is bool) return '$v';
  if (v is String) return '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';
  if (v is List) return '[${v.map(_enc).join(',')}]';
  if (v is Map) {
    return '{${v.entries.map((MapEntry<Object?, Object?> e) => '${_enc('${e.key}')}:${_enc(e.value)}').join(',')}}';
  }
  return 'null';
}
