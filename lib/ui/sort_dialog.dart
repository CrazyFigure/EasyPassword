/// 排序方式选择弹窗（现代化改造）：
/// 替代旧式 showMenu 弹出菜单，使用居中 Dialog + 卡片式单选，
/// 选中态带主题色描边与对勾，点击有涟漪动效。
library;

import 'package:flutter/material.dart';

import '../core/constants.dart';
import 'center_dialog.dart';

/// 弹出排序方式选择框，返回选中的模式（'name_asc' | 'custom'），取消返回 null。
Future<String?> showSortModeDialog(BuildContext context, String current) {
  return showCenterDialog<String>(
    context: context,
    maxWidth: 360,
    builder: (_) => _SortModeDialog(current: current),
  );
}

class _SortModeDialog extends StatelessWidget {
  final String current;
  const _SortModeDialog({required this.current});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题行：图标 + 标题 + 关闭按钮
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryLightBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    const Icon(Icons.swap_vert, size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              const Text('排序方式',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppColors.textWeak),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 排序选项卡片
          _OptionCard(
            value: 'name_asc',
            selected: current == 'name_asc',
            icon: Icons.sort_by_alpha,
            title: '按名称升序',
            subtitle: 'A → Z 自动排列',
            onTap: () => Navigator.pop(context, 'name_asc'),
          ),
          const SizedBox(height: 10),
          _OptionCard(
            value: 'custom',
            selected: current == 'custom',
            icon: Icons.drag_indicator,
            title: '自定义排序',
            subtitle: '长按条目拖动调整顺序',
            onTap: () => Navigator.pop(context, 'custom'),
          ),
        ],
      ),
    );
  }
}

/// 单选选项卡片：选中时主题色描边 + 浅粉底色 + 对勾徽标，未选中为灰边白底。
class _OptionCard extends StatelessWidget {
  final String value;
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionCard({
    required this.value,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryLight : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // 图标徽标
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : AppColors.background,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon,
                    size: 20,
                    color: selected ? Colors.white : AppColors.textSecondary),
              ),
              const SizedBox(width: 12),
              // 标题 + 描述
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMain)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textWeak)),
                  ],
                ),
              ),
              // 选中对勾
              if (selected)
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 14, color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
