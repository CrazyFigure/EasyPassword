/// 主界面：底部导航（可自定义）+ 密码/API Key 列表 + 搜索/设置入口 + 排序
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../services/settings_service.dart';
import '../state/app_state.dart';
import 'center_dialog.dart';
import 'item_list_view.dart';
import 'search_page.dart';
import 'settings/ai_recognize_page.dart';
import 'settings/settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 两个列表页的 Key：新增条目后要反向调用列表把新行滚进视野
  final _passwordListKey = GlobalKey<ItemListViewState>();
  final _apikeyListKey = GlobalKey<ItemListViewState>();

  // 页面缓存（避免切 Tab 重复构建）
  late final _pages = <String, Widget>{
    'password':
        ItemListView(key: _passwordListKey, type: ItemType.password),
    'apikey': ItemListView(key: _apikeyListKey, type: ItemType.apikey),
    'search': const SearchPage(),
    // standalone: false —— 外层已有 Scaffold，避免双层 AppBar
    'ai': const AiRecognizePage(standalone: false),
    'settings': const SettingsPage(),
  };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final visibleTabs = _resolveVisibleTabs(state);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _pages[state.currentTab] ?? _pages['password']!),
          ],
        ),
      ),
      floatingActionButton:
          state.currentTab == 'password' || state.currentTab == 'apikey'
              ? FloatingActionButton(
                  onPressed: () => _openAddItem(context, state.currentTab),
                  child: const Icon(Icons.add),
                )
              : null,
      bottomNavigationBar: _BottomNavBar(
        tabs: visibleTabs,
        current: state.currentTab,
        onSelect: state.setTab,
      ),
    );
  }

  /// 依据设置过滤并排序底部 tab
  List<NavTab> _resolveVisibleTabs(AppState state) {
    final visible = state.currentVisibleTabs;
    return visible;
  }

  Future<void> _openAddItem(BuildContext context, String type) async {
    // 居中弹窗（需求：输入框弹窗从中间出现，而非底部）
    final result = await showCenterDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AddItemSheet(type: type),
    );
    if (result != null && context.mounted) {
      final state = context.read<AppState>();
      final item = await state.data.addItem(
        type,
        result['name'] as String,
        url: result['url'] as String? ?? '',
        siteNote: result['note'] as String? ?? '',
      );
      await state.refresh();
      // 按名称排序时新条目会插进列表中间，自定义排序时落在末尾，
      // 两种情况都滚过去，用户存完即可看到它在哪儿
      final listKey =
          type == ItemType.apikey ? _apikeyListKey : _passwordListKey;
      listKey.currentState?.revealItem(item.id);
    }
  }
}

/// 底部导航（对齐设计稿：Pill 风格，可自定义显隐/顺序/默认项）
class _BottomNavBar extends StatelessWidget {
  final List<NavTab> tabs;
  final String current;
  final ValueChanged<String> onSelect;

  const _BottomNavBar({
    required this.tabs,
    required this.current,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            for (final tab in tabs)
              Expanded(
                child: _NavItem(
                  tab: tab,
                  active: tab.id == current,
                  onTap: () => onSelect(tab.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final NavTab tab;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconFor(tab.id),
                size: 20,
                color: active ? Colors.white : AppColors.textSecondary),
            const SizedBox(height: 2),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: active ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String id) {
    switch (id) {
      case 'password':
        return Icons.lock_outline;
      case 'apikey':
        return Icons.key_outlined;
      case 'search':
        return Icons.search;
      case 'ai':
        return Icons.auto_awesome_outlined;
      case 'settings':
        return Icons.settings_outlined;
      default:
        return Icons.circle_outlined;
    }
  }
}

/// 新增条目底部弹窗
class _AddItemSheet extends StatefulWidget {
  final String type;
  const _AddItemSheet({required this.type});

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isApi = widget.type == ItemType.apikey;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '新增${isApi ? 'API Key' : '密码'}条目',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: AppColors.textWeak),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '网站 / App 名称',
              hintText: '例如：Google、OpenAI',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: '网站地址（可选）',
              hintText: 'https://...',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(
              labelText: '网站级备注',
              hintText: '备注信息',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(context, {
                'name': _nameCtrl.text.trim(),
                'url': _urlCtrl.text.trim(),
                'note': _noteCtrl.text.trim(),
              });
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
