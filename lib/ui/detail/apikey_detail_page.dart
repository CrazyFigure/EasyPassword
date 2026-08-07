/// API Key 详情页：网站级备注 + 用户列表 + 每个用户下多套 API Key（三级结构）
/// 拖动排序：用户级 + API Key 级（需求 2.x）
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../models/account.dart';
import '../../models/api_key.dart';
import '../../models/password_item.dart';
import '../../state/app_state.dart';
import '../center_dialog.dart';
import '../common/confirm_dialog.dart';
import '../common/copy_util.dart';
import '../common/detail_field_row.dart';
import '../common/drag_handle.dart';
import '../common/inline_edit_form.dart';
import '../common/row_action_menu.dart';
import '../common/site_color.dart';
import '../item_edit_sheet.dart';

class ApiKeyDetailPage extends StatefulWidget {
  final PasswordItem item;
  const ApiKeyDetailPage({super.key, required this.item});

  @override
  State<ApiKeyDetailPage> createState() => _ApiKeyDetailPageState();
}

class _ApiKeyDetailPageState extends State<ApiKeyDetailPage> {
  late PasswordItem _item;
  List<Account> _users = [];
  bool _loading = true;
  bool _reveal = false; // 本页"显示全部"开关
  bool _adding = false; // 是否正在就地新增用户

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final users = await state.data.listAccounts(_item.id);
    if (!mounted) return;
    setState(() {
      _users = users;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showAll = _reveal;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textMain),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('API Key 详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: AppColors.textMain),
            onPressed: _editItem,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            onPressed: _deleteItem,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SiteHeader(item: _item),
                const SizedBox(height: 12),
                _NoteCard(
                  label: '网站级备注',
                  text: _item.siteNote.isEmpty ? '暂无备注' : _item.siteNote,
                  copyText: _item.siteNote,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('用户列表（${_users.length}）',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textWeak)),
                    const Spacer(),
                    InkWell(
                      onTap: () => setState(() => _reveal = !_reveal),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Icon(
                              showAll ? Icons.visibility : Icons.visibility_off,
                              size: 15,
                              color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(showAll ? '隐藏' : '显示全部',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.primary)),
                        ]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 用户卡片（可拖动排序，需求 2.4）
                // 关闭默认把手，改用卡片内显式监听拖动
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  proxyDecorator: roundedDragProxy,
                  itemCount: _users.length,
                  onReorderItem: _onUserReorder,
                  itemBuilder: (context, index) => _UserCard(
                    key: ValueKey(_users[index].id),
                    index: index,
                    account: _users[index],
                    showAll: showAll,
                    onChanged: _load,
                  ),
                ),
                // 新增用户：就地展开编辑卡片
                if (_adding)
                  InlineEditForm(
                    title: '添加用户',
                    // 用户名与平台密码允许只填其一，但不能都为空
                    requireAnyOf: const {'username', 'password'},
                    fields: const [
                      InlineField(
                        key: 'username',
                        label: '用户名',
                        hint: '例如：user@example.com',
                      ),
                      InlineField(
                        key: 'password',
                        label: '平台密码',
                        hint: '请输入密码',
                        obscure: true,
                      ),
                      InlineField(
                        key: 'note',
                        label: '用户级备注',
                      ),
                    ],
                    onCancel: () => setState(() => _adding = false),
                    onSave: _saveNewUser,
                  ),
                const SizedBox(height: 12),
                // 添加用户
                if (!_adding)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: const Text('添加用户'),
                    onPressed: () => setState(() => _adding = true),
                  ),
                const SizedBox(height: 12),
                // 浏览器跳转（需求 2.5：二次确认）
                if (_item.url.isNotEmpty)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                    ),
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    label: const Text('在浏览器中打开'),
                    onPressed: _openBrowser,
                  ),
              ],
            ),
    );
  }

  Future<void> _onUserReorder(int oldIndex, int newIndex) async {
    // onReorderItem 的 newIndex 已按移除后位置计算
    final list = List<Account>.from(_users);
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    final state = context.read<AppState>();
    await state.data.reorderAccounts(list.map((e) => e.id).toList());
    await _load();
  }

  Future<void> _editItem() async {
    final result = await showCenterDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ItemEditSheet(type: _item.type, item: _item),
    );
    if (result != null && mounted) {
      final state = context.read<AppState>();
      _item = _item.copyWith(
        name: result['name'] as String,
        url: result['url'] as String? ?? '',
        siteNote: result['note'] as String? ?? '',
        updatedAt: DateTime.now(),
      );
      await state.data.updateItem(_item);
      setState(() {});
      await state.refresh();
    }
  }

  Future<void> _deleteItem() async {
    final ok = await showConfirmDialog(
      context: context,
      title: '删除条目',
      content: '确定删除 ${_item.name} 及其全部用户与 API Key 吗？',
      confirmText: '删除',
      isDangerous: true,
    );
    if (ok == true && mounted) {
      final state = context.read<AppState>();
      await state.data.deleteItem(_item.id);
      await state.refresh();
      if (mounted) Navigator.pop(context);
    }
  }

  /// 就地新增用户保存
  Future<void> _saveNewUser(Map<String, String> values) async {
    final state = context.read<AppState>();
    await state.data.addAccount(
      _item.id,
      values['username'] ?? '',
      values['password'] ?? '',
      note: values['note'] ?? '',
    );
    if (!mounted) return;
    setState(() => _adding = false);
    await _load();
    await state.refresh();
  }

  Future<void> _openBrowser() async {
    final uri = Uri.tryParse(_item.url);
    if (uri == null) return;
    final ok = await showConfirmDialog(
      context: context,
      title: '打开浏览器',
      content: '即将在浏览器中打开：\n${_item.url}\n\n确认继续吗？',
      confirmText: '打开',
    );
    if (ok == true && mounted) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// 用户卡片：用户名 + 平台密码 + 多套 API Key（可拖动排序 + 就地编辑）
class _UserCard extends StatefulWidget {
  final int index; // 列表下标，供拖动把手使用
  final Account account;
  final bool showAll;
  final VoidCallback onChanged;

  const _UserCard({
    super.key,
    required this.index,
    required this.account,
    required this.showAll,
    required this.onChanged,
  });

  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
  List<ApiKey> _keys = [];
  bool _loaded = false;
  bool _pwdRevealed = false;
  String? _plainPwd;
  int? _plainPwdLength; // 明文位数，仅用于铺满等长星号
  bool _editing = false; // 用户信息就地编辑态
  bool _addingKey = false; // 是否正在就地新增 API Key

  @override
  void initState() {
    super.initState();
    // 进入时若父级已开启"显示全部"，平台密码同步为可见
    _pwdRevealed = widget.showAll;
  }

  @override
  void didUpdateWidget(covariant _UserCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父级"显示全部"变化时，平台密码整体跟随（之后单条按钮仍可独立切换）
    if (widget.showAll != oldWidget.showAll) {
      _pwdRevealed = widget.showAll;
      if (_pwdRevealed) _ensurePlainPwd();
    }
  }

  /// 按需解密平台密码，解密完成后刷新
  Future<void> _ensurePlainPwd() async {
    if (_plainPwd != null) return;
    final state = context.read<AppState>();
    final plain = await state.data.plainPassword(widget.account);
    if (mounted) {
      setState(() {
        _plainPwd = plain;
        _plainPwdLength = plain.length;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _loadKeys();
    // context 可用后再解密（initState 中不能安全 read<AppState>）
    // 遮挡态也需要位数，因此始终解密一次
    _ensurePlainPwd();
  }

  Future<void> _loadKeys() async {
    final state = context.read<AppState>();
    final keys = await state.data.listApiKeys(widget.account.id);
    if (!mounted) return;
    setState(() {
      _keys = keys;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showAll = widget.showAll;
    // 就地编辑用户信息
    if (_editing) {
      return InlineEditForm(
        title: '编辑用户',
        // 用户名与平台密码允许只填其一，但不能都为空
        requireAnyOf: const {'username', 'password'},
        fields: [
          InlineField(
            key: 'username',
            label: '用户名',
            initial: widget.account.username,
          ),
          InlineField(
            key: 'password',
            label: '平台密码',
            obscure: true,
            // 编辑时带出原密码（按需解密），可用小眼睛查看
            resolveInitial: () async {
              final state = context.read<AppState>();
              return _plainPwd ??
                  await state.data.plainPassword(widget.account);
            },
          ),
          InlineField(
            key: 'note',
            label: '用户级备注',
            initial: widget.account.note,
          ),
        ],
        onCancel: () => setState(() => _editing = false),
        onSave: _saveUserEdit,
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 用户行头：仅承载身份与卡片级操作，具体字段交给下方字段行，
          // 避免出现「行头也是一个字段」造成的层级混乱
          Row(children: [
            DragHandle(index: widget.index, size: 16),
            const SizedBox(width: 4),
            const Icon(Icons.person_outline,
                size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.account.username.isEmpty
                    ? '用户 ${widget.index + 1}'
                    : widget.account.username,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const ActionSlot(count: 2),
            ActionSlot(
              child: RowActionMenu(
                size: 16,
                actions: [
                  RowAction(
                    label: '编辑',
                    icon: Icons.edit_outlined,
                    onSelected: () => setState(() => _editing = true),
                  ),
                  RowAction(
                    label: '删除用户',
                    icon: Icons.delete_outline,
                    isDangerous: true,
                    onSelected: _deleteUser,
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 4),
          // 用户名与平台密码同为字段行：标签线、值线、操作列三者对齐
          DetailFieldRow(
            label: '用户名',
            value: widget.account.username,
            copyLabel: '用户名',
            onCopy: () async => widget.account.username,
          ),
          DetailFieldRow(
            label: '平台密码',
            value:
                _pwdRevealed ? (_plainPwd ?? '') : '*' * (_plainPwdLength ?? 0),
            pending: _plainPwd == null,
            obscurable: true,
            revealed: _pwdRevealed,
            onToggle: _togglePwd,
            copyLabel: '平台密码',
            onCopy: () async {
              final state = context.read<AppState>();
              return _plainPwd ??
                  await state.data.plainPassword(widget.account);
            },
          ),
          // 备注与上方字段同格式，不再自带「：」
          if (widget.account.note.isNotEmpty)
            DetailFieldRow(
              label: '备注',
              value: widget.account.note,
              copyLabel: '备注',
              onCopy: () async => widget.account.note,
            ),
          const SizedBox(height: 4),
          // API Key 列表（可拖动排序，需求 2.4）
          if (_keys.isNotEmpty) ...[
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              proxyDecorator: roundedDragProxy,
              itemCount: _keys.length,
              onReorderItem: _onKeyReorder,
              itemBuilder: (context, index) => _ApiKeyTile(
                key: ValueKey(_keys[index].id),
                index: index,
                apiKey: _keys[index],
                showAll: showAll,
                onChanged: _loadKeys,
              ),
            ),
          ],
          // 新增 API Key：就地展开编辑
          if (_addingKey)
            InlineEditForm(
              title: '添加 API Key',
              requiredKeys: const {'key'},
              fields: const [
                InlineField(
                  key: 'key',
                  label: 'API Key',
                  hint: 'sk-...',
                ),
                InlineField(
                  key: 'note',
                  label: 'API Key 级备注',
                ),
              ],
              onCancel: () => setState(() => _addingKey = false),
              onSave: _saveNewKey,
            ),
          // 添加 API Key（需求 2.3）
          if (!_addingKey) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: AppColors.background,
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加 API Key', style: TextStyle(fontSize: 13)),
                onPressed: () => setState(() => _addingKey = true),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _onKeyReorder(int oldIndex, int newIndex) async {
    // onReorderItem 的 newIndex 已按移除后位置计算
    final list = List<ApiKey>.from(_keys);
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    final state = context.read<AppState>();
    await state.data.reorderApiKeys(list.map((e) => e.id).toList());
    await _loadKeys();
  }

  Future<void> _togglePwd() async {
    if (!_pwdRevealed) await _ensurePlainPwd();
    if (mounted) setState(() => _pwdRevealed = !_pwdRevealed);
  }

  /// 就地新增 API Key 保存
  Future<void> _saveNewKey(Map<String, String> values) async {
    final state = context.read<AppState>();
    await state.data.addApiKey(
      widget.account.id,
      values['key'] ?? '',
      note: values['note'] ?? '',
    );
    if (!mounted) return;
    setState(() => _addingKey = false);
    await _loadKeys();
    await state.refresh();
  }

  /// 就地编辑用户信息保存
  Future<void> _saveUserEdit(Map<String, String> values) async {
    final state = context.read<AppState>();
    final newPwd = values['password'] ?? '';
    await state.data.updateAccount(
      widget.account.copyWith(
        username: values['username'] ?? widget.account.username,
        note: values['note'] ?? widget.account.note,
      ),
      // 已带出原值，清空视为不改动（避免误设为空密码）
      newPassword: newPwd.isEmpty ? null : newPwd,
    );
    if (!mounted) return;
    setState(() => _editing = false);
    // 密码可能已变更，清除明文缓存后必须重新解密：
    // 遮挡态也要拿到新位数才能铺出等长星号
    _plainPwd = null;
    _plainPwdLength = null;
    await _ensurePlainPwd();
    widget.onChanged();
  }

  Future<void> _deleteUser() async {
    final ok = await showConfirmDialog(
      context: context,
      title: '删除用户',
      content: '将同时删除该用户下所有 API Key，确定吗？',
      confirmText: '删除',
      isDangerous: true,
    );
    if (ok == true && mounted) {
      final state = context.read<AppState>();
      await state.data.deleteAccount(widget.account.id);
      widget.onChanged();
    }
  }
}

/// API Key 单条展示：key 遮挡/显示 + key 级备注 + 就地编辑
class _ApiKeyTile extends StatefulWidget {
  final int index; // 列表下标，供拖动把手使用
  final ApiKey apiKey;
  final bool showAll;
  final VoidCallback onChanged;

  const _ApiKeyTile({
    super.key,
    required this.index,
    required this.apiKey,
    required this.showAll,
    required this.onChanged,
  });

  @override
  State<_ApiKeyTile> createState() => _ApiKeyTileState();
}

class _ApiKeyTileState extends State<_ApiKeyTile> {
  bool _revealed = false;
  String? _plain;
  int? _plainLength; // 明文位数，仅用于铺满等长星号
  bool _editing = false; // 就地编辑态

  @override
  void initState() {
    super.initState();
    // 进入时若父级已开启"显示全部"，同步为可见
    _revealed = widget.showAll;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // context 可用后再解密（initState 中不能安全 read<AppState>）
    // 遮挡态也需要位数，因此始终解密一次
    _ensurePlain();
  }

  @override
  void didUpdateWidget(covariant _ApiKeyTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父级"显示全部"变化时整体跟随（之后单条按钮仍可独立切换）
    if (widget.showAll != oldWidget.showAll) {
      _revealed = widget.showAll;
      if (_revealed) _ensurePlain();
    }
  }

  /// 按需解密明文 key，解密完成后刷新
  Future<void> _ensurePlain() async {
    if (_plain != null) return;
    final state = context.read<AppState>();
    final plain = await state.data.plainKey(widget.apiKey);
    if (mounted) {
      setState(() {
        _plain = plain;
        _plainLength = plain.length;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _revealed;
    // 就地编辑态：整行替换为编辑表单
    if (_editing) {
      return InlineEditForm(
        title: '编辑 API Key',
        fields: [
          InlineField(
            key: 'key',
            label: 'API Key',
            obscure: true,
            // 编辑时带出原 key（按需解密），可用小眼睛查看
            resolveInitial: () async {
              final state = context.read<AppState>();
              return _plain ?? await state.data.plainKey(widget.apiKey);
            },
          ),
          InlineField(
            key: 'note',
            label: 'API Key 级备注',
            initial: widget.apiKey.note,
          ),
        ],
        onCancel: () => setState(() => _editing = false),
        onSave: _saveEdit,
      );
    }

    // 整条可长按拖动排序：把手图标不再是唯一拖动区域
    return QuickReorderableDelayedDragStartListener(
      index: widget.index,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          // 中性浅底 + 描边，替代原来的粉色底
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            // 拖拽把手移至左侧，与操作按钮分离，避免右侧拥挤
            DragHandle(index: widget.index, size: 18),
            const SizedBox(width: 4),
            const Icon(Icons.key, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // 遮挡时按 key 实际位数铺满星号，不再暴露 sk- 前缀
                    visible ? (_plain ?? '') : '*' * (_plainLength ?? 0),
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textMain),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.apiKey.note.isNotEmpty)
                    Text(widget.apiKey.note,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textWeak)),
                ],
              ),
            ),
            // 顺序与字段行一致：显示/隐藏 → 复制 → 更多
            ActionSlot(
              child: IconButton(
                icon: Icon(
                  visible ? Icons.visibility : Icons.visibility_off,
                  size: 16,
                  color: AppColors.textWeak,
                ),
                tooltip: visible ? '隐藏' : '显示',
                visualDensity: VisualDensity.compact,
                onPressed: _toggle,
              ),
            ),
            ActionSlot(
              child: CopyIconButton(
                label: 'API Key',
                size: 16,
                onResolve: () async {
                  final state = context.read<AppState>();
                  return _plain ?? await state.data.plainKey(widget.apiKey);
                },
              ),
            ),
            // 低频/破坏性操作：编辑、删除收入菜单，减少视觉噪音
            ActionSlot(
              child: RowActionMenu(
                size: 16,
                actions: [
                  RowAction(
                    label: '编辑',
                    icon: Icons.edit_outlined,
                    onSelected: () => setState(() => _editing = true),
                  ),
                  RowAction(
                    label: '删除',
                    icon: Icons.delete_outline,
                    isDangerous: true,
                    onSelected: _delete,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle() async {
    if (!_revealed) await _ensurePlain();
    if (mounted) setState(() => _revealed = !_revealed);
  }

  /// 就地编辑保存
  Future<void> _saveEdit(Map<String, String> values) async {
    final state = context.read<AppState>();
    final newKey = values['key'] ?? '';
    await state.data.updateApiKey(
      widget.apiKey.copyWith(
        note: values['note'] ?? widget.apiKey.note,
      ),
      // 留空表示不修改 key
      newKey: newKey.isEmpty ? null : newKey,
    );
    if (!mounted) return;
    setState(() => _editing = false);
    // key 可能已变更，清除明文缓存后必须重新解密：
    // 遮挡态也要拿到新位数才能铺出等长星号
    _plain = null;
    _plainLength = null;
    await _ensurePlain();
    widget.onChanged();
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context: context,
      title: '删除 API Key',
      content: '确定删除该 API Key 吗？',
      confirmText: '删除',
      isDangerous: true,
    );
    if (ok == true && mounted) {
      final state = context.read<AppState>();
      await state.data.deleteApiKey(widget.apiKey.id);
      widget.onChanged();
    }
  }
}

class _SiteHeader extends StatelessWidget {
  final PasswordItem item;
  const _SiteHeader({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // 与主列表缩略图同一取色规则，保证同一条目两处颜色一致
            color: siteColorFor(item.name),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            siteInitialFor(item.name),
            style: const TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain)),
              if (item.url.isNotEmpty)
                Text(item.url,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textWeak)),
            ],
          ),
        ),
        // 网址可复制
        if (item.url.isNotEmpty)
          CopyIconButton(
            label: '网址',
            onResolve: () async => item.url,
          ),
      ],
    );
  }
}


/// 布局说明：标签与内容同处一行（不再上下堆叠），保证备注行与
/// 用户名/密码等普通行等高。
class _NoteCard extends StatelessWidget {
  final String label;
  final String text;
  final String? copyText; // 非空时展示复制按钮
  const _NoteCard({required this.label, required this.text, this.copyText});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textWeak)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13, color: AppColors.textMain),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (copyText != null && copyText!.isNotEmpty)
            CopyIconButton(
              label: '备注',
              size: 16,
              onResolve: () async => copyText!,
            ),
        ],
      ),
    );
  }
}
