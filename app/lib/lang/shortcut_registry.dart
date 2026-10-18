// 数语引擎 · **快捷键登记表 + 冲突检测**（纯 Dart，S4-b②）
//
// 规格：《快捷键系统.md》§二（默认绑定）· §3.1（浏览器独占键）· §四（持久化草案）。
//
// ★★ 本文件存在的**唯一理由**：让设置页"说实话"。
//   规格里有 39 条默认绑定；2026-10-17 代码里真正接上的只有 17 条，b2-② 之后 23 条。
//   ★ **2026-10-18（S4-c）**：整套 `Ctrl+Alt+*` / `Ctrl+↑↓` / `Ctrl+1..3` / `Ctrl+Shift+7..9` /
//     `Ctrl+Enter` / `Alt+=` 全部接线 ⇒ **只剩 `sourceView`（S5）未接入**。
//   接线方式由外壳 `editor_page.dart` 的 `_actionForKey` 统一匹配本表（**用户改键即刻生效**）
//   ⇒ "已接入"不再是一句声明，而是"真的按这张表匹配"的事实。
//   ⇒ 每条都带 [ShortcutStatus]，未接入的**可以改键**（存偏好），但界面上必须写明白。
//
// 三条规矩（用户 2026-10-17 确认过的边界）：
//   ① **"添加"= 给已有动作加一条副绑定**（每动作 ≤ 2 条），**不能凭空造新动作**；
//   ② 默认项**不能删**，只能"停用"或"恢复默认"；
//   ③ **浏览器独占键拒收**（`Ctrl+Shift+R` 这类页面根本拦不住，见 §3.1）。

/// 一条绑定接没接上（设置页的 `● 已接入 / ○ 未接入` 徽标）
enum ShortcutStatus {
  /// 代码里已经生效（本表与 `edit_view.dart` / `editor_page.dart` 对得上）
  wired,

  /// 规格里定了，但还没接（改键先存着，接入那天自动生效）
  planned,
}

/// 一个组合键（`Ctrl+Alt+F` 这种）
class ShortcutCombo {
  const ShortcutCombo({
    required this.key,
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
  });

  /// 主键：`Z` / `F` / `1` / `/` / `=` / `Enter` / `ArrowUp` / `Tab` / `Esc` …
  final String key;
  final bool ctrl;
  final bool alt;
  final bool shift;
  final bool meta;

  static const ShortcutCombo empty = ShortcutCombo(key: '');
  bool get isEmpty => key.isEmpty;

  /// 解析 `Ctrl+Shift+Z` / `Alt+=` / `Enter`
  factory ShortcutCombo.parse(String s) {
    final List<String> parts = s
        .split('+')
        .map((String p) => p.trim())
        .where((String p) => p.isNotEmpty)
        .toList();
    var ctrl = false, alt = false, shift = false, meta = false;
    final List<String> keys = <String>[];
    for (final String p in parts) {
      switch (p.toLowerCase()) {
        case 'ctrl':
        case 'control':
          ctrl = true;
        case 'alt':
          alt = true;
        case 'shift':
          shift = true;
        case 'meta':
        case 'cmd':
        case 'win':
          meta = true;
        default:
          keys.add(p);
      }
    }
    // `Alt+=` 这种：`=` 本身不会被当修饰键，落进 keys
    final String rawKey = keys.isEmpty ? '' : keys.join('+');
    // ★ 单字母统一大写（`ctrl+z` 与 `Ctrl+Z` 必须是同一个键，否则冲突检测会漏）
    final String key =
        rawKey.length == 1 ? rawKey.toUpperCase() : rawKey;
    return ShortcutCombo(
      key: key,
      ctrl: ctrl,
      alt: alt,
      shift: shift,
      meta: meta,
    );
  }

  /// 规范化显示（冲突检测也用它比 —— 保证 `ctrl+z` 与 `Ctrl+Z` 视为同一个）
  String get label {
    if (isEmpty) return '';
    final List<String> out = <String>[
      if (ctrl) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      if (meta) 'Meta',
      key,
    ];
    return out.join('+');
  }

  /// 用户在设置页按键捕获时是不是"只有修饰键"（还不能算一个组合）
  static bool isModifierOnly(String key) => const <String>{
        'Control',
        'Shift',
        'Alt',
        'Meta',
        'ControlLeft',
        'ControlRight',
        'ShiftLeft',
        'ShiftRight',
        'AltLeft',
        'AltRight',
        'MetaLeft',
        'MetaRight',
      }.contains(key);

  @override
  bool operator ==(Object other) =>
      other is ShortcutCombo && other.label == label;

  @override
  int get hashCode => label.hashCode;

  @override
  String toString() => label;
}

/// 一条动作（默认绑定 + 状态 + 分组）
class ShortcutAction {
  const ShortcutAction({
    required this.id,
    required this.name,
    required this.group,
    required this.combo,
    required this.status,
    this.note = '',
  });

  final String id;
  final String name;

  /// 分组（结构类 / 数学类 / 结构内 / 面板 / 编辑类）
  final String group;
  final String combo;
  final ShortcutStatus status;

  /// 未接入的现实说明（例：`随 S4-c 接入`）
  final String note;

  bool get wired => status == ShortcutStatus.wired;
}

/// ★ §3.1 浏览器独占键：**页面拦不住**，只能避开
const List<String> kBrowserOwnedKeys = <String>[
  'Ctrl+Shift+R', // 强制刷新
  'Ctrl+Shift+I', // 开发者工具
  'Ctrl+Shift+C', // 检查元素
  'Ctrl+Shift+B', // 书签栏
  'Ctrl+Shift+M', // 切换用户
  'Ctrl+Shift+A', // 搜索标签页
  'Ctrl+Shift+T', // 重开标签
  'Ctrl+Shift+D', // 加书签
  'Ctrl+Shift+N', // 无痕窗口
  'Ctrl+Shift+W', // 关闭窗口
  'Ctrl+W', // 关闭标签
  'Ctrl+N', // 新标签
  'Ctrl+T', // 新标签（另一路径）
  'Ctrl+P', // 打印
  'Ctrl+Tab', // 切标签
];

/// 默认登记表（39 条；顺序 = 设置页里的显示顺序）
const List<ShortcutAction> kShortcutActions = <ShortcutAction>[
  // ---------------- 结构类 ----------------
  ShortcutAction(id: 'newblock', name: '新块', group: '结构类', combo: 'Enter', status: ShortcutStatus.wired),
  ShortcutAction(id: 'blockNewline', name: '块内换行', group: '结构类', combo: 'Shift+Enter', status: ShortcutStatus.wired),
  ShortcutAction(id: 'h1', name: '标题 1（再按回正文）', group: '结构类', combo: 'Ctrl+1', status: ShortcutStatus.wired),
  ShortcutAction(id: 'h2', name: '标题 2', group: '结构类', combo: 'Ctrl+2', status: ShortcutStatus.wired),
  ShortcutAction(id: 'h3', name: '标题 3', group: '结构类', combo: 'Ctrl+3', status: ShortcutStatus.wired),
  ShortcutAction(id: 'ol', name: '有序列表', group: '结构类', combo: 'Ctrl+Shift+7', status: ShortcutStatus.wired),
  ShortcutAction(id: 'ul', name: '无序列表', group: '结构类', combo: 'Ctrl+Shift+8', status: ShortcutStatus.wired),
  ShortcutAction(id: 'quote', name: '引用块', group: '结构类', combo: 'Ctrl+Shift+9', status: ShortcutStatus.wired),
  ShortcutAction(id: 'codeblock', name: '代码块', group: '结构类', combo: 'Ctrl+Alt+C', status: ShortcutStatus.wired),
  ShortcutAction(id: 'pagebreak', name: '插入分页符', group: '结构类', combo: 'Ctrl+Enter', status: ShortcutStatus.wired),

  // ---------------- 数学类 ----------------
  // ★★ 2026-10-18（用户拍板）：**`Alt+=`（行内公式）撤掉**，但 **`Ctrl+Alt+E` 回来了** ——
  //   语义变成「**插入一个行间公式段**」（块级排版单位，**不是**"进入公式态"）。
  //   判据（用户原话归纳）：行间是一个**段/块**，"不写内容也成立"（空态由 `EmptyMathMark`
  //   画成淡虚线小框 ⇒ 看得见、点得到）；而**行内公式必须由内容产生** ——
  //   平权不接受"行内多项式当成一个整体"，所以行内没有"先造空壳再写"这条路。
  ShortcutAction(id: 'mathDisplay', name: '插入行间公式段', group: '数学类', combo: 'Ctrl+Alt+E', status: ShortcutStatus.wired),
  ShortcutAction(id: 'frac', name: '分式', group: '数学类', combo: 'Ctrl+Alt+F', status: ShortcutStatus.wired),
  ShortcutAction(id: 'sqrt', name: '根号', group: '数学类', combo: 'Ctrl+Alt+R', status: ShortcutStatus.wired),
  ShortcutAction(id: 'sup', name: '上标', group: '数学类', combo: 'Ctrl+ArrowUp', status: ShortcutStatus.wired),
  ShortcutAction(id: 'sub', name: '下标', group: '数学类', combo: 'Ctrl+ArrowDown', status: ShortcutStatus.wired),
  ShortcutAction(id: 'integral', name: '积分', group: '数学类', combo: 'Ctrl+Alt+I', status: ShortcutStatus.wired),
  ShortcutAction(id: 'summ', name: '求和', group: '数学类', combo: 'Ctrl+Alt+S', status: ShortcutStatus.wired),
  ShortcutAction(id: 'limit', name: '极限', group: '数学类', combo: 'Ctrl+Alt+L', status: ShortcutStatus.wired),
  ShortcutAction(id: 'aligned', name: '对齐推导模板', group: '数学类', combo: 'Ctrl+Alt+A', status: ShortcutStatus.wired),
  ShortcutAction(id: 'cases', name: '分段函数模板', group: '数学类', combo: 'Ctrl+Alt+T', status: ShortcutStatus.wired),
  ShortcutAction(id: 'pmatrix', name: '矩阵模板', group: '数学类', combo: 'Ctrl+Alt+X', status: ShortcutStatus.wired),
  ShortcutAction(id: 'binom', name: '组合数', group: '数学类', combo: 'Ctrl+Alt+B', status: ShortcutStatus.wired),

  // ---------------- 结构内（公式里） ----------------
  ShortcutAction(id: 'slotNext', name: '下一个槽', group: '结构内', combo: 'Tab', status: ShortcutStatus.wired),
  ShortcutAction(id: 'slotPrev', name: '上一个槽', group: '结构内', combo: 'Shift+Tab', status: ShortcutStatus.wired),
  ShortcutAction(id: 'siteUp', name: '上一层（分子↔分母）', group: '结构内', combo: 'ArrowUp', status: ShortcutStatus.wired),
  ShortcutAction(id: 'siteDown', name: '下一层', group: '结构内', combo: 'ArrowDown', status: ShortcutStatus.wired),
  ShortcutAction(id: 'charLeft', name: '左移一位', group: '结构内', combo: 'ArrowLeft', status: ShortcutStatus.wired),
  ShortcutAction(id: 'charRight', name: '右移一位', group: '结构内', combo: 'ArrowRight', status: ShortcutStatus.wired),
  ShortcutAction(id: 'smartDelete', name: '结构感知删除', group: '结构内', combo: 'Backspace', status: ShortcutStatus.wired),
  ShortcutAction(id: 'esc', name: '关闭面板 / 取消选区', group: '结构内', combo: 'Esc', status: ShortcutStatus.wired),

  // ---------------- 面板 ----------------
  ShortcutAction(id: 'panelToggle', name: '开 / 关符号面板', group: '面板', combo: 'Ctrl+/', status: ShortcutStatus.wired),
  ShortcutAction(id: 'quickSlot', name: '插入快捷栏第 1..8 格', group: '面板', combo: 'Alt+1', status: ShortcutStatus.wired, note: 'Alt+1..8 连用；Web 上被 Chrome 抢（见 §3.1）'),
  ShortcutAction(id: 'settings', name: '打开设置页', group: '面板', combo: 'Ctrl+,', status: ShortcutStatus.wired),

  // ---------------- 编辑类 ----------------
  ShortcutAction(id: 'undo', name: '撤销', group: '编辑类', combo: 'Ctrl+Z', status: ShortcutStatus.wired),
  ShortcutAction(id: 'redo', name: '重做', group: '编辑类', combo: 'Ctrl+Shift+Z', status: ShortcutStatus.wired, note: 'Ctrl+Y 也认'),
  ShortcutAction(id: 'selectAll', name: '全选', group: '编辑类', combo: 'Ctrl+A', status: ShortcutStatus.wired),
  ShortcutAction(id: 'copy', name: '复制', group: '编辑类', combo: 'Ctrl+C', status: ShortcutStatus.wired),
  ShortcutAction(id: 'cut', name: '剪切', group: '编辑类', combo: 'Ctrl+X', status: ShortcutStatus.wired),
  ShortcutAction(id: 'paste', name: '粘贴', group: '编辑类', combo: 'Ctrl+V', status: ShortcutStatus.wired),
  ShortcutAction(id: 'newdoc', name: '新建', group: '编辑类', combo: 'Ctrl+N', status: ShortcutStatus.wired),
  ShortcutAction(id: 'open', name: '打开…', group: '编辑类', combo: 'Ctrl+O', status: ShortcutStatus.wired),
  ShortcutAction(id: 'save', name: '保存', group: '编辑类', combo: 'Ctrl+S', status: ShortcutStatus.wired),
  ShortcutAction(id: 'saveAs', name: '另存为…', group: '编辑类', combo: 'Ctrl+Shift+S', status: ShortcutStatus.wired),
  ShortcutAction(id: 'sourceView', name: '源码视图', group: '编辑类', combo: 'Ctrl+Alt+D', status: ShortcutStatus.planned, note: 'S5'),
];

/// 一个动作最多几条键（主键 + 副键）
const int kMaxBindingsPerAction = 2;

/// 用户的快捷键偏好（内存态；持久化随 S4-e）
class ShortcutSettings {
  const ShortcutSettings({
    required this.bindings,
    required this.disabled,
  });

  /// actionId → 组合键列表（**第 0 条是主键**）
  final Map<String, List<ShortcutCombo>> bindings;

  /// 被停用的动作 id（默认项不能删，只能停用）
  final Set<String> disabled;

  factory ShortcutSettings.defaults() => ShortcutSettings(
        bindings: <String, List<ShortcutCombo>>{
          for (final ShortcutAction a in kShortcutActions)
            a.id: <ShortcutCombo>[ShortcutCombo.parse(a.combo)],
        },
        disabled: <String>{},
      );

  bool isDisabled(String id) => disabled.contains(id);

  List<ShortcutCombo> combosOf(String id) =>
      bindings[id] ?? const <ShortcutCombo>[];

  ShortcutAction? actionOf(String id) {
    for (final ShortcutAction a in kShortcutActions) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// 某条动作的**默认**组合键
  ShortcutCombo defaultOf(String id) =>
      ShortcutCombo.parse(actionOf(id)?.combo ?? '');

  /// 这条动作有没有被改过（主键与默认不同 / 多了副键 / 被停用）
  bool isModified(String id) {
    final List<ShortcutCombo> now = combosOf(id);
    final ShortcutCombo def = defaultOf(id);
    if (isDisabled(id)) return true;
    if (now.isEmpty || now.first != def) return true;
    return now.length > 1;
  }

  /// ★ 冲突检测：**只看启用的动作**。
  /// 返回"卷进冲突的动作 id"（同一个组合被两个动作占，或同一动作里重复）。
  Set<String> conflicts() {
    final Map<String, List<String>> byCombo = <String, List<String>>{};
    for (final ShortcutAction a in kShortcutActions) {
      if (isDisabled(a.id)) continue;
      for (final ShortcutCombo c in combosOf(a.id)) {
        if (c.isEmpty) continue;
        byCombo.putIfAbsent(c.label, () => <String>[]).add(a.id);
      }
    }
    final Set<String> bad = <String>{};
    byCombo.forEach((String combo, List<String> ids) {
      final bool dupSame = ids.length != ids.toSet().length;
      if (ids.length > 1 || dupSame) bad.addAll(ids);
    });
    return bad;
  }

  /// 某个组合键归谁（用于"已被「撤销」占用"的提示）
  String? ownerOf(ShortcutCombo c, {String? except}) {
    for (final ShortcutAction a in kShortcutActions) {
      if (a.id == except) continue;
      if (isDisabled(a.id)) continue;
      if (combosOf(a.id).contains(c)) return a.name;
    }
    return null;
  }

  /// 这个组合键能不能用（空 / 浏览器独占 ⇒ 不行，附原因）
  String? rejectionOf(ShortcutCombo c, {String? except}) {
    if (c.isEmpty) return '还没按键';
    if (kBrowserOwnedKeys.contains(c.label)) return '浏览器独占，页面拦不住';
    final String? owner = ownerOf(c, except: except);
    if (owner != null) return '已被「$owner」占用';
    return null;
  }

  // ---------------- 修改（都返回新对象；方便 setState） ----------------

  ShortcutSettings _copy({
    Map<String, List<ShortcutCombo>>? b,
    Set<String>? d,
  }) =>
      ShortcutSettings(bindings: b ?? bindings, disabled: d ?? disabled);

  /// 换掉第 [index] 条（主键 index = 0）
  ShortcutSettings withCombo(String id, int index, ShortcutCombo c) {
    final List<ShortcutCombo> now = List<ShortcutCombo>.of(combosOf(id));
    if (index < 0 || index >= now.length) return this;
    now[index] = c;
    return _copy(b: <String, List<ShortcutCombo>>{...bindings, id: now});
  }

  /// ★ "添加自定义" = 给同一个动作**加一条副绑定**（每动作 ≤ [kMaxBindingsPerAction]）
  ShortcutSettings? addCombo(String id, ShortcutCombo c) {
    final List<ShortcutCombo> now = List<ShortcutCombo>.of(combosOf(id));
    if (now.length >= kMaxBindingsPerAction) return null;
    if (now.contains(c)) return null;
    now.add(c);
    return _copy(b: <String, List<ShortcutCombo>>{...bindings, id: now});
  }

  /// 删一条（**主键删不得** —— 默认项不能删，只能停用）
  ShortcutSettings? removeCombo(String id, int index) {
    if (index <= 0) return null;
    final List<ShortcutCombo> now = List<ShortcutCombo>.of(combosOf(id));
    if (index >= now.length) return null;
    now.removeAt(index);
    return _copy(b: <String, List<ShortcutCombo>>{...bindings, id: now});
  }

  ShortcutSettings toggleEnabled(String id) {
    final Set<String> d = <String>{...disabled};
    if (!d.remove(id)) d.add(id);
    return _copy(d: d);
  }

  /// 单条恢复默认（主键回默认、去掉副键、重新启用）
  ShortcutSettings resetOne(String id) {
    final Set<String> d = <String>{...disabled}..remove(id);
    return ShortcutSettings(
      bindings: <String, List<ShortcutCombo>>{
        ...bindings,
        id: <ShortcutCombo>[defaultOf(id)],
      },
      disabled: d,
    );
  }

  /// 统计（设置页顶部那行"已接入 17 / 共 39"）
  static int get total => kShortcutActions.length;
  static int get wiredCount =>
      kShortcutActions.where((ShortcutAction a) => a.wired).length;
}
