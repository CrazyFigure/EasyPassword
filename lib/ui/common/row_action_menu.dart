/// 行内操作列：固定宽度插槽 + 「更多操作」菜单
///
/// 详情页每行原本平铺 复制 / 显示 / 编辑 / 删除 / 拖动 五枚图标，
/// 窄屏下会挤压正文，且各行图标数量不同导致右侧参差不齐。
///
/// 这里做两件事：
/// 1. 低频与破坏性操作（编辑、删除）收进 [RowActionMenu]；
/// 2. 行尾操作统一放进等宽的 [ActionSlot]，缺项用空插槽占位，
///    使「复制 / 显示 / 更多」三列在竖向上严格对齐。
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// 窄屏阈值：低于此宽度按移动端紧凑尺寸排布
const double _kCompactWidth = 420;

/// 操作插槽宽度。桌面端取 IconButton(compact) 的交互尺寸 40；
/// 窄屏收紧到 36，避免三列固定宽度过度压缩正文。
double actionSlotWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width < _kCompactWidth ? 36 : 40;

/// 操作插槽高度：与 IconButton(compact) 的实际高度一致。
/// 空插槽必须撑起同样的高度，否则「没有按钮的字段行」会比
/// 「有按钮的行」矮一截，行距看起来忽大忽小。
double actionSlotHeight(BuildContext context) =>
    MediaQuery.sizeOf(context).width < _kCompactWidth ? 36 : 40;

/// 等宽等高操作插槽：[child] 为空时仅占位，用于让各行图标列在竖向上对齐
class ActionSlot extends StatelessWidget {
  final Widget? child;
  final int count; // 连续占位数量，空插槽可一次占多列

  const ActionSlot({super.key, this.child, this.count = 1});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: actionSlotWidth(context) * count,
      // 固定高度：保证有值行与空值行等高
      height: actionSlotHeight(context),
      child: child == null ? null : Center(child: child),
    );
  }
}


/// 菜单项：文案 + 图标 + 回调，[isDangerous] 为真时用语义红色
class RowAction {
  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final bool isDangerous;

  const RowAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.isDangerous = false,
  });
}

/// 行尾「更多操作」菜单。
///
/// 使用 child 而非 icon 构造，避免 PopupMenuButton 内部 IconButton
/// 强制 48px 最小约束，撑破 [ActionSlot] 的固定宽度。
class RowActionMenu extends StatelessWidget {
  final List<RowAction> actions;
  final double size;

  const RowActionMenu({
    super.key,
    required this.actions,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: '更多操作',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 150),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      color: AppColors.card,
      elevation: 3,
      onSelected: (index) => actions[index].onSelected(),
      itemBuilder: (context) => [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: 42,
            child: Row(children: [
              Icon(
                actions[i].icon,
                size: 17,
                color: actions[i].isDangerous
                    ? AppColors.danger
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Text(
                actions[i].label,
                style: TextStyle(
                  fontSize: 13,
                  color: actions[i].isDangerous
                      ? AppColors.danger
                      : AppColors.textMain,
                ),
              ),
            ]),
          ),
      ],
      child: SizedBox(
        width: actionSlotWidth(context),
        height: actionSlotWidth(context),
        child: Icon(Icons.more_vert, size: size, color: AppColors.textWeak),
      ),
    );
  }
}
