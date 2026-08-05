/// 密码详情页：网站级备注 + 多套账号（拖动排序）+ 浏览器跳转（需求 1.x）
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../models/account.dart';
import '../../models/password_item.dart';
import '../../state/app_state.dart';
import '../center_dialog.dart';
import '../common/copy_util.dart';
import '../common/drag_handle.dart';
import '../common/inline_edit_form.dart';
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
  bool _reveal = false; // 本页"显示全部"开关
  bool _adding = false; // 是否正在就地新增账号

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
    final showAll = _reveal;

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
                // 站点信息头（URL 可复制）
                _SiteHeader(item: _item),
                const SizedBox(height: 12),
                // 网站级备注（可复制）
                _NoteCard(
                  label: '网站级备注',
                  text: _item.siteNote.isEmpty ? '暂无备注' : _item.siteNote,
                  copyText: _item.siteNote,
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
                // 拖动把手统一由 ReorderableListView 提供：桌面端 buildDefaultDragHandles
                // 会自动在行尾叠加一个默认把手，卡片内若再画一个 drag_handle 图标就会
                // 重复且错位（Windows 上尤其明显）。这里关掉默认把手，改由卡片内的
                // ReorderableDragStartListener 显式包裹唯一的把手图标。
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  proxyDecorator: roundedDragProxy,
                  itemCount: _accounts.length,
                  onReorderItem: _onReorder,
                  itemBuilder: (context, index) => _AccountCard(
                    key: ValueKey(_accounts[index].id),
                    index: index,
                    account: _accounts[index],
                    showAll: showAll,
                    onChanged: _load,
                  ),
                ),
                // 新增账号：就地展开编辑卡片，不再弹窗
                if (_adding)
                  InlineEditForm(
                    title: '添加账号',
                    requiredKeys: const {'username'},
                    fields: const [
                      InlineField(
                        key: 'username',
                        label: '用户名',
                        hint: '例如：user@example.com',
                      ),
                      InlineField(
                        key: 'password',
                        label: '密码',
                        hint: '请输入密码',
                        obscure: true,
                      ),
                      InlineField(
                        key: 'note',
                        label: '用户级备注',
                        maxLines: 2,
                      ),
                    ],
                    onCancel: () => setState(() => _adding = false),
                    onSave: _saveNewAccount,
                  ),
                const SizedBox(height: 12),
                // 添加账号
                if (!_adding)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加账号'),
                    onPressed: () => setState(() => _adding = true),
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
                    label: const Text('在浏览器中打开'),
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

  /// 就地新增账号保存
  Future<void> _saveNewAccount(Map<String, String> values) async {
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

/// 备注卡片（可选复制）
class _NoteCard extends StatelessWidget {
  final String label;
  final String text;
  final String? copyText; // 非空时展示复制按钮
  const _NoteCard({required this.label, required this.text, this.copyText});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
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

/// 账号卡片（用户名 + 密码遮挡 + 用户级备注 + 就地编辑）
class _AccountCard extends StatefulWidget {
  final int index; // 列表下标，供拖动把手使用
  final Account account;
  final bool showAll;
  final VoidCallback onChanged;

  const _AccountCard({
    super.key,
    required this.index,
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
  bool _editing = false; // 是否处于就地编辑态

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
    if (_revealed) _ensurePlain();
  }

  @override
  void didUpdateWidget(covariant _AccountCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父级"显示全部"开关变化时，整体跟随（之后单条按钮仍可独立切换）
    if (widget.showAll != oldWidget.showAll) {
      _revealed = widget.showAll;
      if (_revealed) _ensurePlain();
    }
  }

  /// 按需解密明文密码，解密完成后刷新
  Future<void> _ensurePlain() async {
    if (_plain != null) return;
    final state = context.read<AppState>();
    final plain = await state.data.plainPassword(widget.account);
    if (mounted) setState(() => _plain = plain);
  }

  bool get _visible => _revealed;

  @override
  Widget build(BuildContext context) {
    // 就地编辑态：整张卡片替换为编辑表单（密码需先解密以便回填）
    if (_editing) {
      return InlineEditForm(
        title: '编辑账号',
        requiredKeys: const {'username'},
        fields: [
          InlineField(
            key: 'username',
            label: '用户名',
            initial: widget.account.username,
          ),
          InlineField(
            key: 'password',
            label: '密码',
            obscure: true,
            // 编辑时带出原密码（按需解密），可用小眼睛查看
            resolveInitial: () async {
              final state = context.read<AppState>();
              return _plain ?? await state.data.plainPassword(widget.account);
            },
          ),
          InlineField(
            key: 'note',
            label: '用户级备注',
            initial: widget.account.note,
            maxLines: 2,
          ),
        ],
        onCancel: () => setState(() => _editing = false),
        onSave: _saveEdit,
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
          // 顶部居中的拖动把手（横向短杠，视觉上像卡片抓取条）
          Center(
            child: DragHandle(
              index: widget.index,
              icon: Icons.drag_handle,
              size: 22,
            ),
          ),
          // 行头：账号序号 + 操作
          Row(
            children: [
              Text('账号 ${widget.index + 1}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMain)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: AppColors.textWeak),
                tooltip: '编辑',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _editing = true),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: AppColors.danger),
                tooltip: '删除',
                visualDensity: VisualDensity.compact,
                onPressed: _delete,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 用户名（可复制）
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
            CopyIconButton(
              label: '用户名',
              onResolve: () async => widget.account.username,
            ),
          ]),
          const SizedBox(height: 6),
          // 密码行（遮挡 / 显示 / 复制）
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
                    color: AppColors.textMain),
              ),
            ),
            // 复制无需先显示：按需解密后直接进剪贴板
            CopyIconButton(
              label: '密码',
              onResolve: () async {
                final state = context.read<AppState>();
                return _plain ?? await state.data.plainPassword(widget.account);
              },
            ),
            // 单条查看按钮（需求 1.1）
            IconButton(
              icon: Icon(
                _visible ? Icons.visibility : Icons.visibility_off,
                size: 18,
                color: AppColors.textWeak,
              ),
              tooltip: _visible ? '隐藏' : '显示',
              visualDensity: VisualDensity.compact,
              onPressed: _toggleReveal,
            ),
          ]),
          // 用户级备注（可复制）
          if (widget.account.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: Text('备注：${widget.account.note}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textWeak)),
              ),
              CopyIconButton(
                label: '备注',
                size: 16,
                onResolve: () async => widget.account.note,
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleReveal() async {
    // 需要明文时异步解密
    if (!_visible) await _ensurePlain();
    if (mounted) setState(() => _revealed = !_revealed);
  }

  /// 就地编辑保存
  Future<void> _saveEdit(Map<String, String> values) async {
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
    // 密码可能已变更，清除明文缓存；仍在显示状态则重新解密
    _plain = null;
    if (_revealed) await _ensurePlain();
    widget.onChanged();
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
