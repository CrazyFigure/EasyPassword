/// 文件夹内页：展示某个文件夹下的条目，支持新增、批量删除、移出文件夹
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/folder_palette.dart';
import '../core/name_sort.dart';
import '../models/folder.dart';
import '../models/password_item.dart';
import '../state/app_state.dart';
import 'common/app_menu.dart';
import 'common/confirm_dialog.dart';
import 'common/drag_handle.dart';
import 'common/reveal_scroll.dart';
import 'common/row_trailing.dart';
import 'common/site_color.dart';
import 'detail/apikey_detail_page.dart';
import 'detail/password_detail_page.dart';
import 'center_dialog.dart';
import 'folder_edit_dialog.dart';
import 'item_edit_sheet.dart';
import 'item_list_view.dart';
import 'move_to_folder_dialog.dart';

class FolderPage extends StatefulWidget {
  final String type;
  final Folder folder;

  const FolderPage({super.key, required this.type, required this.folder});

  @override
  State<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  late Folder _folder;
  List<PasswordItem> _items = [];
  bool _loading = true;
  bool _batchMode = false;
  final Set<String> _selected = {};
  // 列表滚动控制器：新增条目后据此把新行滚进视野
  final _scrollCtrl = ScrollController();
  // 待定位的条目 id，等列表用新数据重新布局后再消费
  String? _pendingRevealId;

  bool get _isApi => widget.type == ItemType.apikey;

  @override
  void initState() {
    super.initState();
    _folder = widget.folder;
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// 消费待定位请求：在本帧渲染完成后按新数据算位置并滚动。
  /// [items] 必须是实际展示顺序（已按当前排序规则派生），否则会定位到错行。
  void _consumePendingReveal(List<PasswordItem> items) {
    final id = _pendingRevealId;
    if (id == null) return;
    final index = items.indexWhere((e) => e.id == id);
    _pendingRevealId = null;
    if (index < 0) return;
    afterNextFrame(() {
      if (!mounted) return;
      revealIndex(
        controller: _scrollCtrl,
        index: index,
        itemCount: items.length,
      );
    });
  }

  /// 加载本文件夹内的条目。这里恒按 sort_order 取出，展示顺序在 build 里
  /// 按当前规则派生：用户在本页切换排序方式时无需重新查库即可立即生效。
  Future<void> _load() async {
    final state = context.read<AppState>();
    final items =
        await state.data.listItems(widget.type, folderId: _folder.id);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final customSort = state.sortModeFor(widget.type) == 'custom';
    // 名称模式与根列表共用 compareNames，两级列表的顺序规则完全一致
    final items =
        customSort ? _items : sortByName(_items, (item) => item.name);
    // 新数据已就位，可以安排本轮的滚动定位
    _consumePendingReveal(items);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textMain),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Icon(Icons.folder_rounded,
                size: 18, color: FolderPalette.colorOf(_folder.color)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_folder.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          // 与根列表共用同一个按钮和同一份分区设置：文件夹内也要能看出并切换规则
          SortMenuButton(type: widget.type),
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: AppColors.textMain),
            tooltip: '编辑文件夹',
            onPressed: _editFolder,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildToolRow(),
                const SizedBox(height: 4),
                Expanded(child: _buildList(items, customSort)),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addItem,
        child: const Icon(Icons.add),
      ),
    );
  }

  // ---- 工具行：条目数 + 批量操作 ----
  Widget _buildToolRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Text(
            _batchMode ? '已选 ${_selected.length} 项' : '共 ${_items.length} 项',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary),
          ),
          const Spacer(),
          if (_batchMode) ...[
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(56, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
                foregroundColor: AppColors.textSecondary,
              ),
              onPressed: _exitBatch,
              child: const Text('取消', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(72, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _selected.isEmpty ? null : _moveSelected,
              child: const Text('移动', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
          ],
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(72, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              visualDensity: VisualDensity.compact,
              foregroundColor:
                  _batchMode && _selected.isNotEmpty ? AppColors.danger : null,
            ),
            onPressed: _batchMode ? _confirmBatchDelete : _enterBatch,
            child: Text(
              _batchMode ? '删除(${_selected.length})' : '批量',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ---- 列表 ----
  Widget _buildList(List<PasswordItem> items, bool customSort) {
    if (items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 48, color: AppColors.textFaint),
            SizedBox(height: 8),
            Text('文件夹是空的，点击右下角 + 添加',
                style: TextStyle(color: AppColors.textWeak)),
          ],
        ),
      );
    }
    final children = <Widget>[
      for (var i = 0; i < items.length; i++)
        _buildItemCard(items[i], customSort, i),
    ];
    // 与主列表同一处理：仅自定义排序模式使用可拖动列表，
    // 否则用普通 ListView（避免 onReorderItem 断言）
    if (customSort) {
      return ReorderableListView.builder(
        scrollController: _scrollCtrl,
        padding: kListPadding,
        itemCount: children.length,
        buildDefaultDragHandles: false,
        proxyDecorator: roundedDragProxy,
        onReorderItem: _onReorder,
        itemBuilder: (context, index) => children[index],
      );
    }
    return ListView(
      controller: _scrollCtrl,
      padding: kListPadding,
      children: children,
    );
  }

  Widget _buildItemCard(PasswordItem item, bool customSort, int index) {
    final selected = _selected.contains(item.id);
    // 自定义排序且非批量模式时整条可长按拖动（与主列表一致），
    // 此时长按手势归拖动所有，不能再用来进批量模式
    final draggable = customSort && !_batchMode;

    final card = Card(
      key: ValueKey(item.id),
      margin: const EdgeInsets.only(bottom: 10),
      color: selected ? AppColors.primaryLight : Colors.white,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () {
          if (_batchMode) {
            setState(() {
              selected ? _selected.remove(item.id) : _selected.add(item.id);
            });
          } else {
            _openDetail(item);
          }
        },
        onLongPress: (_batchMode || draggable)
            ? null
            : () => setState(() {
                  _batchMode = true;
                  _selected.add(item.id);
                }),
        leading: _SiteAvatar(item: item),
        // 与主列表同一套右侧留白
        contentPadding: kRowContentPadding,
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
          style: const TextStyle(fontSize: 12, color: AppColors.textWeak),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _batchMode
            ? Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? AppColors.primary : AppColors.textFaint,
              )
            // 条目操作：与主列表同一套「⋮」下拉菜单
            : RowTrailing(
                menuTooltip: '条目操作',
                onMenu: (btnContext) async {
                  final choice = await showAppMenu<String>(
                    anchorContext: btnContext,
                    width: 200,
                    items: const [
                      AppMenuItem(
                        value: 'move',
                        label: '移动到文件夹',
                        icon: Icons.drive_file_move_outline,
                        // 文件夹内页额外支持移出到上一级
                        subtitle: '可选其他文件夹或移出',
                      ),
                      AppMenuItem(
                        value: 'delete',
                        label: '删除条目',
                        icon: Icons.delete_outline,
                        isDangerous: true,
                      ),
                    ],
                  );
                  if (choice == 'move') await _moveSingleItem(item);
                  if (choice == 'delete') await _deleteSingleItem(item);
                },
              ),
      ),
    );
    if (draggable) {
      return QuickReorderableDelayedDragStartListener(
        key: ValueKey(item.id),
        index: index,
        child: card,
      );
    }
    return card;
  }

  /// 单条条目移动（右侧「⋮」菜单入口，无需先进批量模式）。
  /// 与批量移动共用弹窗：这里同样允许「移出到上一级」。
  Future<void> _moveSingleItem(PasswordItem item) async {
    final state = context.read<AppState>();
    final folders = _isApi ? state.apikeyFolders : state.passwordFolders;
    final choice = await showMoveToFolderDialog(
      context: context,
      folders: folders,
      allowRoot: true,
      currentFolderId: _folder.id,
    );
    if (choice == null || !mounted) return;
    await state.data.moveItemsToFolder([item.id], choice.folderId);
    await _load();
    await state.refresh();
  }

  /// 单条条目删除（右侧「⋮」菜单入口）
  Future<void> _deleteSingleItem(PasswordItem item) async {
    final ok = await showConfirmDialog(
      context: context,
      title: '删除条目',
      content: '确定删除「${item.name}」吗？此操作不可撤销。',
      confirmText: '删除',
      isDangerous: true,
    );
    if (ok != true || !mounted) return;
    final state = context.read<AppState>();
    await state.data.deleteItem(item.id);
    await _load();
    await state.refresh();
  }

  Future<void> _openDetail(PasswordItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _isApi
            ? ApiKeyDetailPage(item: item)
            : PasswordDetailPage(item: item),
      ),
    );
    // 详情页可能改名或删除条目，返回后重新加载本文件夹
    await _load();
  }

  /// 拖动重排。只在自定义排序模式下可触发，此时展示列表与 [_items] 同序，
  /// 因此下标可以直接用来重排 [_items]。
  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final list = List<PasswordItem>.from(_items);
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    final state = context.read<AppState>();
    await state.data.reorderItems(list.map((e) => e.id).toList());
    await _load();
  }

  void _enterBatch() {
    setState(() {
      _batchMode = true;
      _selected.clear();
    });
  }

  void _exitBatch() {
    setState(() {
      _batchMode = false;
      _selected.clear();
    });
  }

  /// 在当前文件夹内新增条目
  Future<void> _addItem() async {
    final result = await showCenterDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ItemEditSheet(type: widget.type),
    );
    if (result == null || !mounted) return;
    final state = context.read<AppState>();
    final item = await state.data.addItem(
      widget.type,
      result['name'] as String,
      url: result['url'] as String? ?? '',
      siteNote: result['note'] as String? ?? '',
      // 关键：新增的条目直接归属当前文件夹
      folderId: _folder.id,
    );
    // 先置位再加载：_load 的 setState 会触发 build，正好在那里消费定位请求
    _pendingRevealId = item.id;
    await _load();
    await state.refresh();
  }

  /// 把选中条目移动到其他文件夹或移出到上一级
  Future<void> _moveSelected() async {
    if (_selected.isEmpty) return;
    final state = context.read<AppState>();
    final folders = _isApi ? state.apikeyFolders : state.passwordFolders;
    final choice = await showMoveToFolderDialog(
      context: context,
      folders: folders,
      allowRoot: true,
      currentFolderId: _folder.id,
    );
    if (choice == null || !mounted) return;
    await state.data.moveItemsToFolder(_selected.toList(), choice.folderId);
    setState(() {
      _batchMode = false;
      _selected.clear();
    });
    await _load();
    await state.refresh();
  }

  Future<void> _confirmBatchDelete() async {
    if (_selected.isEmpty) return;
    final ok = await showConfirmDialog(
      context: context,
      title: '批量删除',
      content: '确定删除选中的 ${_selected.length} 个条目吗？此操作不可撤销。',
      confirmText: '删除',
      isDangerous: true,
    );
    if (ok != true || !mounted) return;
    final state = context.read<AppState>();
    await state.data.deleteItems(_selected.toList());
    setState(() {
      _batchMode = false;
      _selected.clear();
    });
    await _load();
    await state.refresh();
  }

  /// 编辑文件夹（名称 + 颜色）
  Future<void> _editFolder() async {
    final result = await showFolderEditDialog(
      context: context,
      initialName: _folder.name,
      initialColor: _folder.color,
    );
    if (result == null || !mounted) return;
    final state = context.read<AppState>();
    final updated = _folder.copyWith(name: result.name, color: result.color);
    await state.data.updateFolder(updated);
    setState(() => _folder = updated);
    await state.refresh();
  }
}

/// 站点头像：与主列表同一取色规则
class _SiteAvatar extends StatelessWidget {
  final PasswordItem item;
  const _SiteAvatar({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: siteColorFor(item.name),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        siteInitialFor(item.name),
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }
}
