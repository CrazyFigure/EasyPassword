/// 底部栏自定义弹窗（需求 3.5.4）：
/// 开关 密码/API Key/搜索/设置，调整顺序，设置默认打开的主界面
/// 居中弹窗样式（需求：选择框从中间出现，不再从底部弹出）
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../services/settings_service.dart';
import '../../state/app_state.dart';
import '../common/app_menu.dart';
import '../common/drag_handle.dart';

class TabCustomizeSheet extends StatefulWidget {
  const TabCustomizeSheet({super.key});

  @override
  State<TabCustomizeSheet> createState() => _TabCustomizeSheetState();
}

class _TabCustomizeSheetState extends State<TabCustomizeSheet> {
  late List<NavTab> _tabs;
  late String _defaultId;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final cfg = await state.settings.getTabConfig();
    if (!mounted) return;
    setState(() {
      _tabs = [
        for (final id in cfg.visibleIds)
          NavTab.all
              .firstWhere((t) => t.id == id, orElse: () => NavTab(id, id)),
      ];
      _defaultId = cfg.defaultTabId;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    await state.updateTabConfig(
      TabConfig(
        visibleIds: _tabs.map((t) => t.id).toList(),
        defaultTabId: _defaultId,
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 居中弹窗内使用固定上下留白；键盘避让由 showCenterDialog 统一处理
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('底部栏自定义',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMain)),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: AppColors.textWeak),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 8),
          if (!_loaded)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            // Tab 开关 + 顺序（固定高度列表，避免与弹窗滚动冲突）
            SizedBox(
              height: _tabs.isEmpty ? 48 : (_tabs.length * 52.0).clamp(52, 208),
              child: _tabs.isEmpty
                  ? const Center(
                      child: Text('全部 Tab 已隐藏',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textWeak)))
                  : ReorderableListView.builder(
                      shrinkWrap: true,
                      itemCount: _tabs.length,
                      // 关闭默认把手：桌面端会在行尾自动叠加一个 drag_handle 图标，
                      // 正好压在 Switch 上，看起来像开关中间多了一条横杠。
                      // 拖动改由左侧把手图标显式承接。
                      buildDefaultDragHandles: false,
                      onReorderItem: (oldIndex, newIndex) {
                        setState(() {
                          final item = _tabs.removeAt(oldIndex);
                          _tabs.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, index) {
                        final tab = _tabs[index];
                        return ListTile(
                          key: ValueKey(tab.id),
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: EdgeInsets.zero,
                          leading: DragHandle(index: index),
                          title: Text(tab.label,
                              style: const TextStyle(
                                  fontSize: 15, color: AppColors.textMain)),
                          trailing: Switch(
                            value: true,
                            activeTrackColor: AppColors.primary,
                            onChanged: (_) => _toggleOff(tab),
                          ),
                        );
                      },
                    ),
            ),
            // 隐藏的 tab 补充开关
            ...NavTab.all.where((t) => !_tabs.any((e) => e.id == t.id)).map(
                  (tab) => ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.drag_handle,
                        color: Colors.transparent),
                    title: Text(tab.label,
                        style: const TextStyle(
                            fontSize: 15, color: AppColors.textWeak)),
                    trailing: Switch(
                      value: false,
                      onChanged: (_) => _toggleOn(tab),
                    ),
                  ),
                ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: AppColors.border),
            // 默认主页
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const Text('启动时默认打开',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMain)),
                  const Spacer(),
                  // 默认主页复用统一的锚点式选择器，与其他设置项保持一致。
                  AppMenuPicker<String>(
                    value: _defaultId,
                    items: [
                      for (final tab in _tabs)
                        AppMenuItem(value: tab.id, label: tab.label),
                    ],
                    onChanged: (v) => setState(() => _defaultId = v),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: _save,
              child: const Text('保存'),
            ),
          ],
        ],
      ),
    );
  }

  void _toggleOff(NavTab tab) {
    setState(() {
      _tabs.remove(tab);
      if (_defaultId == tab.id) {
        _defaultId = _tabs.isNotEmpty ? _tabs.first.id : 'password';
      }
    });
  }

  void _toggleOn(NavTab tab) {
    setState(() => _tabs.add(tab));
  }
}
