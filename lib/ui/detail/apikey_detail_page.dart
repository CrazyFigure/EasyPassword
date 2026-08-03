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
import '../account_edit_sheet.dart';
import '../apikey_edit_sheet.dart';
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
    final state = context.watch<AppState>();
    final showAll = state.revealAll || _reveal;

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
                          Icon(showAll ? Icons.visibility : Icons.visibility_off,
                              size: 15, color: AppColors.primary),
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
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: true,
                  itemCount: _users.length,
                  onReorderItem: _onUserReorder,
                  itemBuilder: (context, index) => _UserCard(
                    key: ValueKey(_users[index].id),
                    account: _users[index],
                    showAll: showAll,
                    onChanged: _load,
                  ),
                ),
                const SizedBox(height: 12),
                // 添加用户
                OutlinedButton.icon(
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: const Text('添加用户'),
                  onPressed: _addUser,
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
                    label: const Text('在浏览器中打开（需二次确认）'),
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
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除条目'),
        content: Text('确定删除 ${_item.name} 及其全部用户与 API Key 吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final state = context.read<AppState>();
      await state.data.deleteItem(_item.id);
      await state.refresh();
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _addUser() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AccountEditSheet(),
    );
    if (result != null && mounted) {
      final state = context.read<AppState>();
      await state.data.addAccount(
        _item.id,
        result['username'] as String? ?? '',
        result['password'] as String? ?? '',
        note: result['note'] as String? ?? '',
      );
      await _load();
      await state.refresh();
    }
  }

  Future<void> _openBrowser() async {
    final uri = Uri.tryParse(_item.url);
    if (uri == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('打开浏览器'),
        content: Text('即将在浏览器中打开：\n${_item.url}\n\n确认继续吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('打开'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// 用户卡片：用户名 + 平台密码 + 多套 API Key（可拖动排序）
class _UserCard extends StatefulWidget {
  final Account account;
  final bool showAll;
  final VoidCallback onChanged;

  const _UserCard({
    super.key,
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _loadKeys();
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
          // 用户行头
          Row(children: [
            const Icon(Icons.person_outline, size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(widget.account.username,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMain)),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  size: 18, color: AppColors.textWeak),
              onPressed: _editUser,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: AppColors.danger),
              onPressed: _deleteUser,
            ),
            const Icon(Icons.drag_handle, size: 20, color: AppColors.textFaint),
          ]),
          // 平台密码
          Row(children: [
            const Text('平台密码',
                style: TextStyle(fontSize: 12, color: AppColors.textWeak)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _pwdRevealed ? (_plainPwd ?? '********') : '********',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textMain, fontFamily: 'monospace'),
              ),
            ),
            IconButton(
              icon: Icon(
                _pwdRevealed ? Icons.visibility : Icons.visibility_off,
                size: 16,
                color: AppColors.textWeak,
              ),
              onPressed: _togglePwd,
            ),
          ]),
          const SizedBox(height: 4),
          // API Key 列表（可拖动排序，需求 2.4）
          if (_keys.isNotEmpty) ...[
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: true,
              itemCount: _keys.length,
              onReorderItem: _onKeyReorder,
              itemBuilder: (context, index) => _ApiKeyTile(
                key: ValueKey(_keys[index].id),
                apiKey: _keys[index],
                showAll: showAll,
                onChanged: _loadKeys,
              ),
            ),
          ],
          // 添加 API Key（需求 2.3）
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
                backgroundColor: AppColors.primaryLightBg,
                side: BorderSide.none,
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加 API Key', style: TextStyle(fontSize: 13)),
              onPressed: _addKey,
            ),
          ),
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
    if (!_pwdRevealed && _plainPwd == null) {
      final state = context.read<AppState>();
      _plainPwd = await state.data.plainPassword(widget.account);
    }
    if (mounted) setState(() => _pwdRevealed = !_pwdRevealed);
  }

  Future<void> _addKey() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ApiKeyEditSheet(),
    );
    if (result != null && mounted) {
      final state = context.read<AppState>();
      await state.data.addApiKey(
        widget.account.id,
        result['key'] as String? ?? '',
        note: result['note'] as String? ?? '',
      );
      await _loadKeys();
      await state.refresh();
    }
  }

  Future<void> _editUser() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AccountEditSheet(account: widget.account),
    );
    if (result != null && mounted) {
      final state = context.read<AppState>();
      await state.data.updateAccount(
        widget.account.copyWith(
          username: result['username'] as String? ?? widget.account.username,
          note: result['note'] as String? ?? widget.account.note,
        ),
        newPassword: result['password'] as String?,
      );
      widget.onChanged();
    }
  }

  Future<void> _deleteUser() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除用户'),
        content: const Text('将同时删除该用户下所有 API Key，确定吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final state = context.read<AppState>();
      await state.data.deleteAccount(widget.account.id);
      widget.onChanged();
    }
  }
}

/// API Key 单条展示：key 遮挡/显示 + key 级备注
class _ApiKeyTile extends StatefulWidget {
  final ApiKey apiKey;
  final bool showAll;
  final VoidCallback onChanged;

  const _ApiKeyTile({
    super.key,
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

  @override
  Widget build(BuildContext context) {
    final visible = widget.showAll || _revealed;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryLightBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.key, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  visible ? (_plain ?? 'sk-***') : 'sk-***',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textMain, fontFamily: 'monospace'),
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
          IconButton(
            icon: Icon(
              visible ? Icons.visibility : Icons.visibility_off,
              size: 16,
              color: AppColors.textWeak,
            ),
            onPressed: _toggle,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                size: 16, color: AppColors.textWeak),
            onPressed: _edit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 16, color: AppColors.danger),
            onPressed: _delete,
          ),
          const Icon(Icons.drag_handle, size: 18, color: AppColors.textFaint),
        ],
      ),
    );
  }

  Future<void> _toggle() async {
    final visibleNow = _revealed || widget.showAll;
    if (!visibleNow && _plain == null) {
      final state = context.read<AppState>();
      _plain = await state.data.plainKey(widget.apiKey);
    }
    if (mounted) setState(() => _revealed = !_revealed);
  }

  Future<void> _edit() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ApiKeyEditSheet(apiKey: widget.apiKey),
    );
    if (result != null && mounted) {
      final state = context.read<AppState>();
      await state.data.updateApiKey(
        widget.apiKey.copyWith(
          note: result['note'] as String? ?? widget.apiKey.note,
        ),
        newKey: result['key'] as String?,
      );
      widget.onChanged();
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除 API Key'),
        content: const Text('确定删除该 API Key 吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
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
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            item.name.isNotEmpty ? item.name[0].toUpperCase() : '?',
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
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  final String label;
  final String text;
  const _NoteCard({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textWeak)),
          const SizedBox(height: 4),
          Text(text,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textMain)),
        ],
      ),
    );
  }
}
