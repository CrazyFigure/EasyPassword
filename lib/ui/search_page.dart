/// 全局搜索页：搜索框 + 分区筛选（全部/密码/API Key）+ 结果列表
/// 点击结果跳转到对应条目详情（需求 3.3）
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import 'common/app_toast.dart';
import '../services/search_service.dart';
import '../state/app_state.dart';
import 'common/site_color.dart';
import 'detail/apikey_detail_page.dart';
import 'detail/password_detail_page.dart';
import 'folder_page.dart';

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
              prefixIcon: const Icon(Icons.search, color: AppColors.textWeak),
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
            Text('输入关键词开始搜索', style: TextStyle(color: AppColors.textWeak)),
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
        return _buildResultCard(r);
      },
    );
  }

  /// 构建搜索结果卡片：
  /// 将类型标签与箭头移入 title 行，避免 ListTile.trailing 垂直霸占整列空间，
  /// 从而彻底释放右下角红框区域供 subtitle 展开；
  /// 同时保留 ListTile 结构与完整的目录、网址、用户名、密码、备注等上下文信息。
  Widget _buildResultCard(SearchResult r) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: siteColorFor(r.title),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            siteInitialFor(r.title),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        // 标题行包含标题、类型标签与箭头；
        // 将类型标签与箭头移入本行，使得 trailing 为 null，
        // 彻底消除原本在右侧整列的宽度占位，红框区域被下方内容充分利用。
        title: Row(
          children: [
            Expanded(
              child: Text(
                r.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMain,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _typeTag(r.itemType),
            const SizedBox(width: 2),
            const Tooltip(
              message: '查看详情',
              waitDuration: Duration(milliseconds: 100),
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.textFaint,
              ),
            ),
          ],
        ),
        subtitle: _buildSubtitle(r),
        isThreeLine: true,
        onTap: () => _jumpTo(r),
      ),
    );
  }

  /// 构建卡片详细内容与位置上下文（利用无 trailing 的全宽展开展示）
  Widget _buildSubtitle(SearchResult r) {
    final folderText = r.folderName != null ? r.folderName! : '根目录';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        // 1) 命中定位指示条：明确标识命中位置与具体匹配值，避免原先「名称：」后空白的问题
        _buildHitBadge(r),

        // 2) 目录/文件夹位置：无论在文件夹内还是根目录，均明确展示所在位置（使用深色字体，清晰突出）
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              const Icon(Icons.folder_outlined,
                  size: 13, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '目录：$folderText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMain),
                ),
              ),
            ],
          ),
        ),

        // 3) 网址（如果有）
        if (r.url.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(Icons.language_outlined,
                    size: 13, color: AppColors.textWeak),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '网址：${r.url}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),

        // 4) 用户名（如果有）
        if (r.username != null && r.username!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(Icons.person_outline_rounded,
                    size: 13, color: AppColors.textWeak),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '用户名：${r.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),

        // 5) 密码（仅在命中密码时展示，保证敏感信息安全合规）
        if (r.hitField == '密码' &&
            (r.password != null || r.hitValue.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(Icons.lock_outline_rounded,
                    size: 13, color: AppColors.textWeak),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '密码：${r.password ?? r.hitValue}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),

        // 6) 用户级备注（若未在命中行展示，则作为上下文展示）
        if (r.accountNote != null &&
            r.accountNote!.isNotEmpty &&
            r.hitField != '用户级备注')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline_rounded,
                    size: 13, color: AppColors.textWeak),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '用户备注：${r.accountNote}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),

        // 7) 网站级备注（若未在命中行展示，则作为上下文展示）
        if (r.siteNote.isNotEmpty && r.hitField != '网站级备注')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(Icons.notes_rounded,
                    size: 13, color: AppColors.textWeak),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '网站备注：${r.siteNote}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),

        // 8) API Key 分区专属字段
        if (r.itemType == ItemType.apikey) ...[
          if (r.hitField == 'API Key' &&
              (r.apiKey != null || r.hitValue.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.key_outlined,
                      size: 13, color: AppColors.textWeak),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'API Key：${r.apiKey ?? r.hitValue}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          if (r.apiKeyNote != null &&
              r.apiKeyNote!.isNotEmpty &&
              r.hitField != 'API Key 备注')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.label_outline_rounded,
                      size: 13, color: AppColors.textWeak),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Key备注：${r.apiKeyNote}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  /// 构建命中高亮指示条：清晰展示命中的字段与匹配内容
  Widget _buildHitBadge(SearchResult r) {
    final String fieldName = r.hitField == '名称' ? '条目名称' : r.hitField;
    // 提取具体匹配内容，确保命中名称、网址、备注、账号或Key均完整展示匹配值
    final String value = r.hitField == '名称'
        ? r.title
        : (r.hitValue.isNotEmpty ? r.hitValue : r.subtitle);
    final String label = '匹配$fieldName：$value';

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(Icons.gps_fixed_rounded,
              size: 12, color: AppColors.primary),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ),
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

  /// 点击结果跳转到对应详情（需求 3.3）。
  ///
  /// 文件夹内条目先把 [FolderPage] 压入导航栈，并由文件夹页继续打开详情；
  /// 因而详情返回时能保留正确目录层级，同时由文件夹页负责滚动定位。
  Future<void> _jumpTo(SearchResult r) async {
    final state = context.read<AppState>();
    // 直接按 id 查库，避免根目录缓存列表查不到文件夹内的条目
    final item = await state.data.getItem(r.itemId);
    if (!mounted) return;
    if (item == null || item.deleted) {
      showAppToast(context, '条目不存在或已删除', kind: ToastKind.error);
      return;
    }
    // 以点击时的最新条目归属为准，避免搜索完成后条目被移动导致返回旧目录。
    final folderId = item.folderId;
    final folder =
        folderId == null ? null : await state.data.getFolder(folderId);
    if (!mounted) return;

    // 查询完导航上下文后再切换 Tab；setTab 会让搜索页退出组件树，之后不能
    // 再等待数据库查询或读取本页 context。
    state.setTab(r.itemType);
    if (folderId != null) {
      // 已删除、类型不匹配的文件夹属于异常或并发变更，安全回退为直接详情。
      if (folder != null && !folder.deleted && folder.type == r.itemType) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FolderPage(
              type: r.itemType,
              folder: folder,
              initialItem: item,
            ),
          ),
        );
        await state.refresh();
        return;
      }
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => r.itemType == ItemType.apikey
            ? ApiKeyDetailPage(item: item)
            : PasswordDetailPage(item: item),
      ),
    );
    await state.refresh();
  }
}
