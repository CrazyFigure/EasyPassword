/// 全局搜索页：搜索框 + 分区筛选（全部/密码/API Key）+ 结果列表
/// 点击结果跳转到对应条目详情（需求 3.3）
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../models/password_item.dart';
import '../services/search_service.dart';
import '../state/app_state.dart';
import 'detail/apikey_detail_page.dart';
import 'detail/password_detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  String _scope = 'all';
  List<SearchResult> _results = [];
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _doSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final state = context.read<AppState>();
    final results = await state.search.search(query, scope: _scope);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  void _setScope(String scope) {
    setState(() => _scope = scope);
    _doSearch(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('全局搜索',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain)),
        ),
        // 搜索框（不自动聚焦：切到搜索页时不主动弹出键盘，需要输入时再点击）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: '搜索网站/App、备注、用户名、密码、API Key...',
              prefixIcon:
                  const Icon(Icons.search, color: AppColors.textWeak),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear,
                          size: 18, color: AppColors.textWeak),
                      onPressed: () {
                        _controller.clear();
                        _doSearch('');
                      },
                    )
                  : null,
            ),
            onChanged: _doSearch,
            textInputAction: TextInputAction.search,
          ),
        ),
        const SizedBox(height: 10),
        // 分区筛选
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _chip('all', '全部'),
              const SizedBox(width: 8),
              _chip('password', '密码'),
              const SizedBox(width: 8),
              _chip('apikey', 'API Key'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1, color: AppColors.border),
        // 结果区
        Expanded(child: _buildResults()),
      ],
    );
  }

  Widget _chip(String value, String label) {
    final active = _scope == value;
    return InkWell(
      onTap: () => _setScope(value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: active ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.text.trim().isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 48, color: AppColors.textFaint),
            SizedBox(height: 8),
            Text('输入关键词开始搜索',
                style: TextStyle(color: AppColors.textWeak)),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: AppColors.textFaint),
            SizedBox(height: 8),
            Text('未找到匹配结果', style: TextStyle(color: AppColors.textWeak)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final r = _results[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: r.itemType == ItemType.apikey
                    ? AppColors.openai
                    : AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                r.title.isNotEmpty ? r.title[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
              ),
            ),
            title: Text(r.title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain)),
            subtitle: Text(
              '${r.hitField}：${r.subtitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textWeak),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _typeTag(r.itemType),
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.textFaint),
              ],
            ),
            onTap: () => _jumpTo(r),
          ),
        );
      },
    );
  }

  Widget _typeTag(String type) {
    final isApi = type == ItemType.apikey;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryLightBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isApi ? 'API Key' : '密码',
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.primary),
      ),
    );
  }

  /// 点击结果跳转到对应详情（需求 3.3）
  void _jumpTo(SearchResult r) {
    final state = context.read<AppState>();
    // 从对应列表找到完整条目对象
    final items = r.itemType == ItemType.apikey
        ? state.apikeyItems
        : state.passwordItems;
    PasswordItem? item;
    for (final e in items) {
      if (e.id == r.itemId) {
        item = e;
        break;
      }
    }
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('条目不存在或已删除')),
      );
      return;
    }
    // 跳转对应功能区 tab
    state.setTab(r.itemType);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => r.itemType == ItemType.apikey
            ? ApiKeyDetailPage(item: item!)
            : PasswordDetailPage(item: item!),
      ),
    ).then((_) => state.refresh());
  }
}
