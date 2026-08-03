/// 底部栏自定义弹窗（需求 3.5.4）：
/// 开关 密码/API Key/搜索/设置，调整顺序，设置默认打开的主界面
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../services/settings_service.dart';
import '../../state/app_state.dart';

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
          NavTab.all.firstWhere((t) => t.id == id, orElse: () => NavTab(id, id)),
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
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text('底部栏自定义',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain)),
          ),
          const Divider(height: 1, color: AppColors.border),
          if (!_loaded)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            )
          else ...[
            // Tab 开关 + 顺序
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                itemCount: _tabs.length,
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
                    leading: const Icon(Icons.drag_handle,
                        color: AppColors.textFaint),
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
                    leading:
                        const Icon(Icons.drag_handle, color: Colors.transparent),
                    title: Text(tab.label,
                        style: const TextStyle(
                            fontSize: 15, color: AppColors.textWeak)),
                    trailing: Switch(
                      value: false,
                      onChanged: (_) => _toggleOn(tab),
                    ),
                  ),
                ),
            const Divider(height: 1, color: AppColors.border),
            // 默认主页
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  const Text('启动时默认打开',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMain)),
                  const Spacer(),
                  DropdownButton<String>(
                    value: _defaultId,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final t in _tabs)
                        DropdownMenuItem(value: t.id, child: Text(t.label)),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _defaultId = v);
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: FilledButton(
                onPressed: _save,
                child: const Text('保存'),
              ),
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
