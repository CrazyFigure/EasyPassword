/// 密码详情页：网站级备注 + 多套账号（拖动排序）+ 浏览器跳转（需求 1.x）
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../models/account.dart';
import '../../models/password_item.dart';
import '../../state/app_state.dart';
import '../account_edit_sheet.dart';
import '../item_edit_sheet.dart';

class PasswordDetailPage extends StatefulWidget {
  final PasswordItem item;
  const PasswordDetailPage({super.key, required this.item});

  @override
  State<PasswordDetailPage> createState() => _PasswordDetailPageState();
}

class _PasswordDetailPageState extends State<PasswordDetailPage> {
  late PasswordItem _item;
  List<Account> _accounts = [];
  bool _loading = true;
  bool _reveal = false; // 本页"显示全部"开关（叠加全局开关）

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final accounts = await state.data.listAccounts(_item.id);
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
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
        title: const Text('密码详情'),
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
                // 站点信息头
                _SiteHeader(item: _item),
                const SizedBox(height: 12),
                // 网站级备注
                _NoteCard(
                  label: '网站级备注',
                  text: _item.siteNote.isEmpty ? '暂无备注' : _item.siteNote,
                ),
                const SizedBox(height: 12),
                // 显示全部开关（单页）
                Row(
                  children: [
                    Text('账号列表（${_accounts.length}）',
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
                          Text(showAll ? '隐藏' : '显示全部密码',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.primary)),
                        ]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 账号卡片（可拖动排序，需求 1.3）
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: true,
                  itemCount: _accounts.length,
                  onReorderItem: _onReorder,
                  itemBuilder: (context, index) => _AccountCard(
                    key: ValueKey(_accounts[index].id),
                    account: _accounts[index],
                    showAll: showAll,
                    onChanged: _load,
                  ),
                ),
                const SizedBox(height: 12),
                // 添加账号
                OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加账号'),
                  onPressed: _addAccount,
                ),
                const SizedBox(height: 12),
                // 浏览器跳转（需求 1.4：二次确认）
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

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    // onReorderItem 的 newIndex 已按移除后位置计算，无需再调整
    final list = List<Account>.from(_accounts);
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
        content: Text('确定删除 ${_item.name} 及其全部账号吗？'),
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

  Future<void> _addAccount() async {
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
    // 二次确认
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

/// 站点信息头
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

/// 备注卡片
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

/// 账号卡片（用户名 + 密码遮挡 + 用户级备注）
class _AccountCard extends StatefulWidget {
  final Account account;
  final bool showAll;
  final VoidCallback onChanged;

  const _AccountCard({
    super.key,
    required this.account,
    required this.showAll,
    required this.onChanged,
  });

  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  bool _revealed = false;
  String? _plain; // 解密后的密码（按需解密）

  bool get _visible => widget.showAll || _revealed;

  @override
  Widget build(BuildContext context) {
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
          // 行头：账号序号 + 拖动把手 + 操作
          Row(
            children: [
              Text('账号 ${widget.account.sortOrder + 1}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMain)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: AppColors.textWeak),
                onPressed: _edit,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: AppColors.danger),
                onPressed: _delete,
              ),
              const Icon(Icons.drag_handle,
                  size: 20, color: AppColors.textFaint),
            ],
          ),
          const SizedBox(height: 4),
          // 用户名
          Row(children: [
            const Text('用户名',
                style: TextStyle(fontSize: 13, color: AppColors.textWeak)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(widget.account.username,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMain)),
            ),
          ]),
          const SizedBox(height: 6),
          // 密码行（遮挡 / 显示）
          Row(children: [
            const Text('密码',
                style: TextStyle(fontSize: 13, color: AppColors.textWeak)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _visible ? (_plain ?? '********') : '********',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMain,
                    fontFamily: 'monospace'),
              ),
            ),
            // 单条查看按钮（需求 1.1）
            IconButton(
              icon: Icon(
                _visible ? Icons.visibility : Icons.visibility_off,
                size: 18,
                color: AppColors.textWeak,
              ),
              onPressed: _toggleReveal,
            ),
          ]),
          // 用户级备注
          if (widget.account.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('备注：${widget.account.note}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textWeak)),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleReveal() async {
    // 需要明文时异步解密
    if (!_visible && _plain == null) {
      final state = context.read<AppState>();
      _plain = await state.data.plainPassword(widget.account);
    }
    if (mounted) setState(() => _revealed = !_revealed);
  }

  Future<void> _edit() async {
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

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账号'),
        content: const Text('确定删除该账号吗？'),
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
