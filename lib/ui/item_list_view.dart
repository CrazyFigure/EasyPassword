/// 条目列表视图（密码区 / API Key 区通用）
/// 含：标题行、排序按钮、显示全部开关、批量操作、文件夹分组、可拖动排序的卡片列表
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/folder_palette.dart';
import '../models/folder.dart';
import '../models/list_entry.dart';
import '../models/password_item.dart';
import '../state/app_state.dart';
import 'common/app_menu.dart';
import 'common/confirm_dialog.dart';
import 'common/drag_handle.dart';
import 'common/site_color.dart';
import 'detail/apikey_detail_page.dart';
import 'detail/password_detail_page.dart';
import 'folder_edit_dialog.dart';
import 'folder_page.dart';
import 'move_to_folder_dialog.dart';

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
    // 文件夹与条目合并为统一的行序列，排序规则见 AppState.rootEntries
    final entries = state.rootEntries(widget.type);
    final customSort = state.sortMode == 'custom';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, state, entries.length),
        const Divider(height: 1, color: AppColors.border),
        _buildToolRow(context, state),
        const SizedBox(height: 8),
        Expanded(child: _buildList(state, entries, customSort)),
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
            icon:
                const Icon(Icons.settings_outlined, color: AppColors.textMain),
            onPressed: () => state.setTab('settings'),
          ),
        ],
      ),
    );
  }

  // ---- 工具行：批量操作 ----
  Widget _buildToolRow(BuildContext context, AppState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // 批量模式下左侧提示已选数量
          if (_batchMode)
            Text(
              '已选 ${_selected.length} 项',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary),
            ),
          const Spacer(),
          // 批量模式下提供退出入口
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
            // 批量移动到文件夹
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(72, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _selected.isEmpty ? null : _moveSelectedToFolder,
              child: const Text('移动', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
          ],
          // 新建文件夹（非批量模式）
          if (!_batchMode) ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(72, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.create_new_folder_outlined, size: 15),
              label: const Text('新建文件夹', style: TextStyle(fontSize: 12)),
              onPressed: _createFolder,
            ),
            const SizedBox(width: 8),
          ],
          // 批量操作（需求 3.4）
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(72, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              visualDensity: VisualDensity.compact,
              // 有选中项时用危险色强调删除动作
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

  void _enterBatch() {
    setState(() {
      _batchMode = true;
      _selected.clear();
    });
  }

  /// 退出批量模式并清空选择
  void _exitBatch() {
    setState(() {
      _batchMode = false;
      _selected.clear();
    });
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

  /// 新建文件夹
  Future<void> _createFolder() async {
    final result = await showFolderEditDialog(context: context);
    if (result == null || !mounted) return;
    final state = context.read<AppState>();
    await state.data.addFolder(widget.type, result.name, color: result.color);
    await state.refresh();
  }

  /// 把批量选中的条目移动到某个文件夹（或移出到根目录）
  Future<void> _moveSelectedToFolder() async {
    if (_selected.isEmpty) return;
    final state = context.read<AppState>();
    final folders = _isApi ? state.apikeyFolders : state.passwordFolders;
    final choice = await showMoveToFolderDialog(
      context: context,
      folders: folders,
      // 根列表里选中的条目本就在根目录，不需要"移出"选项
      allowRoot: false,
    );
    if (choice == null || !mounted) return;
    await state.data.moveItemsToFolder(_selected.toList(), choice.folderId);
    setState(() {
      _batchMode = false;
      _selected.clear();
    });
    await state.refresh();
  }

  // ---- 列表 ----
  Widget _buildList(AppState state, List<ListEntry> entries, bool customSort) {
    if (entries.isEmpty) {
      return const _EmptyHint();
    }
    // 文件夹与条目同处一个序列，自定义排序时可任意交叉拖动
    final children = <Widget>[
      for (var i = 0; i < entries.length; i++)
        _buildEntryCard(state, entries[i], customSort, i),
    ];
    // 治本说明：Flutter 3.44.8 起 ReorderableListView.builder 要求
    // onReorderItem 与 onReorder 必须"恰好一个非空"。当 customSort=false
    // （默认按名称排序）时，强行传入 onReorderItem:null 会触发断言导致整个
    // 页面红色错误。这里按 customSort 分流 widget：开启拖动排序才用
    // ReorderableListView.builder，否则用普通 ListView（无拖动也避免断言）。
    if (customSort) {
      return ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
        itemCount: children.length,
        // 关闭默认把手：桌面端会自动叠加一个，与卡片内的把手重复错位
        buildDefaultDragHandles: false,
        // 拖动预览保持圆角，避免露出方形底板
        proxyDecorator: roundedDragProxy,
        onReorderItem: (oldIndex, newIndex) =>
            _onReorder(state, entries, oldIndex, newIndex),
        itemBuilder: (context, index) => children[index],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      children: children,
    );
  }

  /// 一行：按类型分派到文件夹卡片或条目卡片
  Widget _buildEntryCard(
      AppState state, ListEntry entry, bool customSort, int index) {
    if (entry.isFolder) {
      final folder = entry.folder!;
      final card = _FolderCard(
        key: ValueKey(entry.entryKey),
        folder: folder,
        count: state.folderCounts[folder.id] ?? 0,
        enabled: !_batchMode,
        onOpen: () => _openFolder(folder),
        onEdit: () => _editFolder(folder),
        onDelete: () => _deleteFolder(folder),
      );
      // 自定义排序模式下文件夹同样可长按拖动
      if (customSort && !_batchMode) {
        return QuickReorderableDelayedDragStartListener(
          key: ValueKey(entry.entryKey),
          index: index,
          child: card,
        );
      }
      return card;
    }
    return _buildItemCard(
        state, entry.item!, customSort, index, entry.entryKey);
  }

  /// 进入文件夹
  Future<void> _openFolder(Folder folder) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FolderPage(type: widget.type, folder: folder),
      ),
    );
    if (!mounted) return;
    // 文件夹内可能有增删/移出，回来后刷新根列表与计数
    await context.read<AppState>().refresh();
  }

  /// 编辑文件夹（名称 + 颜色）
  Future<void> _editFolder(Folder folder) async {
    final result = await showFolderEditDialog(
      context: context,
      initialName: folder.name,
      initialColor: folder.color,
    );
    if (result == null || !mounted) return;
    final state = context.read<AppState>();
    await state.data.updateFolder(
      folder.copyWith(name: result.name, color: result.color),
    );
    await state.refresh();
  }

  /// 删除文件夹：内部条目移回根目录，不随文件夹一起删除
  Future<void> _deleteFolder(Folder folder) async {
    final count = context.read<AppState>().folderCounts[folder.id] ?? 0;
    final ok = await showConfirmDialog(
      context: context,
      title: '删除文件夹',
      content: count == 0
          ? '确定删除文件夹「${folder.name}」吗？'
          : '确定删除文件夹「${folder.name}」吗？\n\n'
              '其中的 $count 个条目不会被删除，将移回上一级列表。',
      confirmText: '删除',
      isDangerous: true,
    );
    if (ok != true || !mounted) return;
    final state = context.read<AppState>();
    await state.data.deleteFolder(folder.id);
    await state.refresh();
  }

  /// 混合重排：文件夹与条目共用一套序号写回各自的表
  Future<void> _onReorder(AppState state, List<ListEntry> entries, int oldIndex,
      int newIndex) async {
    // onReorderItem 的 newIndex 已按移除后位置计算
    final list = List<ListEntry>.from(entries);
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    await state.data.reorderRootEntries(
      [for (final e in list) (e.isFolder ? 'folder' : 'item', e.id)],
    );
    await state.refresh();
  }

  /// [entryKey] 为混排列表里的唯一 Key（文件夹与条目 id 空间独立，需加前缀区分）
  Widget _buildItemCard(AppState state, PasswordItem item, bool customSort,
      int index, String entryKey) {
    final selected = _selected.contains(item.id);

    // 自定义排序模式：整条可长按拖动。
    // 用 Delayed 版本而非 ReorderableDragStartListener：后者按下即接管手势，
    // 会吃掉 ListTile 的点击，导致点条目进不了详情页。
    if (customSort && !_batchMode) {
      return QuickReorderableDelayedDragStartListener(
        // key 必须挂在 itemBuilder 返回的根 widget 上，
        // 否则 ReorderableListView 会断言「every item must have a key」
        key: ValueKey(entryKey),
        index: index,
        child: Card(
          margin: const EdgeInsets.only(bottom: 10),
          color: selected ? AppColors.primaryLight : Colors.white,
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _isApi
                      ? ApiKeyDetailPage(item: item)
                      : PasswordDetailPage(item: item),
                ),
              );
            },
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
              style: const TextStyle(fontSize: 12, color: AppColors.textWeak),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing:
                const Icon(Icons.chevron_right, color: AppColors.textFaint),
          ),
        ),
      );
    }

    // 普通模式或批量模式
    return Card(
      key: ValueKey(entryKey),
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
          style: const TextStyle(fontSize: 12, color: AppColors.textWeak),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _batchMode
            ? Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? AppColors.primary : AppColors.textFaint,
              )
            : const Icon(Icons.chevron_right, color: AppColors.textFaint),
      ),
    );
  }
}

/// 文件夹卡片：与条目卡片同样的行高，靠图标颜色与右侧计数区分
class _FolderCard extends StatelessWidget {
  final Folder folder;
  final int count;
  final bool enabled; // 批量选择条目时，文件夹行不可点
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _FolderCard({
    super.key,
    required this.folder,
    required this.count,
    required this.enabled,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: ListTile(
          onTap: enabled ? onOpen : null,
          leading: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // 自定义颜色的浅色底 + 同色图标
              color: FolderPalette.bgOf(folder.color),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.folder_rounded,
                size: 22, color: FolderPalette.colorOf(folder.color)),
          ),
          title: Text(
            folder.name,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textMain),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '$count 项',
            style: const TextStyle(fontSize: 12, color: AppColors.textWeak),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 文件夹操作：统一样式的轻量下拉菜单
              Builder(
                builder: (btnContext) => IconButton(
                  icon: const Icon(Icons.more_vert,
                      size: 18, color: AppColors.textFaint),
                  tooltip: '文件夹操作',
                  onPressed: enabled
                      ? () async {
                          final choice = await showAppMenu<String>(
                            anchorContext: btnContext,
                            width: 190,
                            items: const [
                              AppMenuItem(
                                value: 'edit',
                                label: '编辑文件夹',
                                icon: Icons.edit_outlined,
                                subtitle: '修改名称与颜色',
                              ),
                              AppMenuItem(
                                value: 'delete',
                                label: '删除文件夹',
                                icon: Icons.delete_outline,
                                isDangerous: true,
                              ),
                            ],
                          );
                          if (choice == 'edit') onEdit();
                          if (choice == 'delete') onDelete();
                        }
                      : null,
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// 排序方式入口：点击后在按钮下方弹出轻量下拉菜单
/// （原先是居中大弹窗，对"选一个排序方式"这种小操作过重）
class _SortMenuButton extends StatelessWidget {
  const _SortMenuButton();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // 用 Builder 取到 IconButton 自身的 context，菜单才能对齐到按钮位置
    return Builder(
      builder: (btnContext) => IconButton(
        icon: const Icon(Icons.sort, color: AppColors.textMain),
        tooltip: '排序',
        onPressed: () async {
          final choice = await showAppMenu<String>(
            anchorContext: btnContext,
            selected: state.sortMode,
            width: 230,
            items: const [
              AppMenuItem(
                value: 'name_asc',
                label: '按名称升序',
                icon: Icons.sort_by_alpha,
                subtitle: '文件夹在前，A → Z 排列',
              ),
              AppMenuItem(
                value: 'custom',
                label: '自定义排序',
                icon: Icons.drag_indicator,
                subtitle: '长按拖动，可与文件夹混排',
              ),
            ],
          );
          if (choice != null &&
              choice != state.sortMode &&
              btnContext.mounted) {
            await btnContext.read<AppState>().updateSortMode(choice);
          }
        },
      ),
    );
  }
}

/// 站点头像：品牌色底 + 首字母（取色规则见 common/site_color.dart，详情页共用）
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
          Text('还没有条目，点击右下角 + 添加\n也可以点「新建文件夹」先分组',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textWeak)),
        ],
      ),
    );
  }
}
