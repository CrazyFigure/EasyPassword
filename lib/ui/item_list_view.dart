/// 条目列表视图（密码区 / API Key 区通用）
/// 含：标题行、排序按钮、显示全部开关、批量操作、可拖动排序的卡片列表
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../models/password_item.dart';
import '../state/app_state.dart';
import 'detail/apikey_detail_page.dart';
import 'detail/password_detail_page.dart';

class ItemListView extends StatefulWidget {
  final String type;
  const ItemListView({super.key, required this.type});

  @override
  State<ItemListView> createState() => _ItemListViewState();
}

class _ItemListViewState extends State<ItemListView> {
  bool _batchMode = false;
  final Set<String> _selected = {};

  bool get _isApi => widget.type == ItemType.apikey;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final items = _isApi ? state.apikeyItems : state.passwordItems;
    final customSort = state.sortMode == 'custom';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, state, items.length),
        const Divider(height: 1, color: AppColors.border),
        _buildToolRow(context, state),
        const SizedBox(height: 8),
        Expanded(child: _buildList(state, items, customSort)),
      ],
    );
  }

  // ---- 标题行 ----
  Widget _buildHeader(BuildContext context, AppState state, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _isApi ? 'API Key' : '密码',
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain),
            ),
          ),
          // 搜索入口
          IconButton(
            icon: const Icon(Icons.search, color: AppColors.textMain),
            onPressed: () => state.setTab('search'),
          ),
          // 排序按钮（需求 3.5.5）
          const _SortMenuButton(),
          // 设置入口
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: AppColors.textMain),
            onPressed: () => state.setTab('settings'),
          ),
        ],
      ),
    );
  }

  // ---- 工具行：显示全部开关 + 批量操作 ----
  Widget _buildToolRow(BuildContext context, AppState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // 显示全部开关（需求 1.1 / 2.1）
          InkWell(
            onTap: state.toggleRevealAll,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    state.revealAll
                        ? Icons.visibility
                        : Icons.visibility_off,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    state.revealAll ? '已显示全部' : '显示全部',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // 批量操作（需求 3.4）
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(72, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _batchMode ? _confirmBatchDelete : _enterBatch,
            child: Text(
              _batchMode
                  ? '删除(${_selected.length})'
                  : (_isApi ? '批量' : '批量'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _enterBatch() {
    setState(() {
      _batchMode = true;
      _selected.clear();
    });
  }

  Future<void> _confirmBatchDelete() async {
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定删除选中的 ${_selected.length} 个条目吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final state = context.read<AppState>();
      await state.data.deleteItems(_selected.toList());
      setState(() {
        _batchMode = false;
        _selected.clear();
      });
      await state.refresh();
    }
  }

  // ---- 列表 ----
  Widget _buildList(AppState state, List<PasswordItem> items, bool customSort) {
    if (items.isEmpty) {
      return const _EmptyHint();
    }
    final children = <Widget>[
      for (var i = 0; i < items.length; i++)
        _buildItemCard(state, items[i], customSort),
    ];
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      itemCount: children.length,
      buildDefaultDragHandles: customSort,
      onReorderItem: customSort
          ? (oldIndex, newIndex) => _onReorder(state, items, oldIndex, newIndex)
          : null,
      itemBuilder: (context, index) => children[index],
    );
  }

  Future<void> _onReorder(
      AppState state, List<PasswordItem> items, int oldIndex, int newIndex) async {
    // onReorderItem 的 newIndex 已按移除后位置计算
    final list = List<PasswordItem>.from(items);
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    await state.data.reorderItems(list.map((e) => e.id).toList());
    await state.refresh();
  }

  Widget _buildItemCard(AppState state, PasswordItem item, bool customSort) {
    final selected = _selected.contains(item.id);
    return Card(
      key: ValueKey(item.id),
      margin: const EdgeInsets.only(bottom: 10),
      color: selected ? AppColors.primaryLight : Colors.white,
      child: ListTile(
        onTap: () {
          if (_batchMode) {
            setState(() {
              selected ? _selected.remove(item.id) : _selected.add(item.id);
            });
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _isApi
                    ? ApiKeyDetailPage(item: item)
                    : PasswordDetailPage(item: item),
              ),
            );
          }
        },
        onLongPress: _batchMode
            ? null
            : () => setState(() {
                  _batchMode = true;
                  _selected.add(item.id);
                }),
        leading: _SiteAvatar(item: item),
        title: Text(
          item.name,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textMain),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          item.siteNote.isEmpty ? item.url : item.siteNote,
          style: const TextStyle(
              fontSize: 12, color: AppColors.textWeak),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _batchMode
            ? Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? AppColors.primary : AppColors.textFaint,
              )
            : customSort
                ? const Icon(Icons.drag_handle,
                    color: AppColors.textFaint, size: 20)
                : const Icon(Icons.chevron_right,
                    color: AppColors.textFaint),
      ),
    );
  }
}

/// 排序方式菜单（3.5.5：默认名称升序 / 自定义）
class _SortMenuButton extends StatelessWidget {
  const _SortMenuButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.sort, color: AppColors.textMain),
      tooltip: '排序',
      onPressed: () async {
        if (!context.mounted) return;
        final choice = await showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(200, 80, 16, 0),
          items: const [
            PopupMenuItem(
              value: 'name_asc',
              child: Row(children: [
                Icon(Icons.sort_by_alpha, size: 18),
                SizedBox(width: 8),
                Text('按名称升序'),
              ]),
            ),
            PopupMenuItem(
              value: 'custom',
              child: Row(children: [
                Icon(Icons.swap_vert, size: 18),
                SizedBox(width: 8),
                Text('自定义排序（长按拖动）'),
              ]),
            ),
          ],
        );
        if (choice != null && context.mounted) {
          await context.read<AppState>().updateSortMode(choice);
        }
      },
    );
  }
}

/// 站点头像：品牌色底 + 首字母
class _SiteAvatar extends StatelessWidget {
  final PasswordItem item;
  const _SiteAvatar({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(item.name);
    final letter = item.name.isNotEmpty ? item.name[0].toUpperCase() : '?';
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        letter,
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }

  Color _colorFor(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('google')) return AppColors.google;
    if (lower.contains('github')) return AppColors.github;
    if (lower.contains('aws')) return AppColors.aws;
    if (lower.contains('apple')) return AppColors.apple;
    if (lower.contains('openai')) return AppColors.openai;
    // 其余按名字哈希取品牌色板
    const palette = [
      Color(0xFF5C6BC0), Color(0xFF26A69A), Color(0xFFEF5350),
      Color(0xFFAB47BC), Color(0xFFFFA726), Color(0xFF66BB6A),
    ];
    return palette[name.hashCode.abs() % palette.length];
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: AppColors.textFaint),
          SizedBox(height: 8),
          Text('还没有条目，点击右下角 + 添加',
              style: TextStyle(color: AppColors.textWeak)),
        ],
      ),
    );
  }
}
