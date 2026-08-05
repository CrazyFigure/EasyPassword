/// 统一的轻量下拉菜单：替代 Material 默认的 PopupMenuButton / DropdownButton。
///
/// 默认样式的问题是直角白底、行高过大、无图标、投影生硬，与本应用
/// 圆角卡片 + 浅粉主色的风格不搭。这里用 showGeneralDialog 手动定位，
/// 在锚点正下方（空间不足时向上）弹出一张圆角卡片，带缩放淡入动效。
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// 下拉菜单里的一项
class AppMenuItem<T> {
  final T value;
  final String label;
  final IconData? icon;
  final String? subtitle;

  /// 危险操作（如删除）用红色文字与图标
  final bool isDangerous;

  const AppMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.subtitle,
    this.isDangerous = false,
  });
}

/// 在 [anchorContext] 对应控件的下方弹出菜单，返回选中项的值；点击外部返回 null。
///
/// [selected] 命中的项会显示主色高亮与对勾。
Future<T?> showAppMenu<T>({
  required BuildContext anchorContext,
  required List<AppMenuItem<T>> items,
  T? selected,
  double width = 210,
}) {
  // 计算锚点在屏幕中的位置，菜单据此对齐
  final box = anchorContext.findRenderObject() as RenderBox?;
  final overlay =
      Navigator.of(anchorContext).overlay!.context.findRenderObject() as RenderBox;
  if (box == null) return Future<T?>.value(null);

  final anchorTopLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final anchorSize = box.size;
  final screen = overlay.size;

  const margin = 8.0;
  // 估算菜单高度，用于判断下方空间是否够用
  final estimatedHeight = items.fold<double>(
        12,
        (sum, e) => sum + (e.subtitle == null ? 44 : 58),
      ) +
      4;

  // 水平：与锚点右缘对齐，超出屏幕则回拉
  var left = anchorTopLeft.dx + anchorSize.width - width;
  left = left.clamp(margin, (screen.width - width - margin).clamp(margin, double.infinity));

  // 垂直：优先锚点下方；空间不足则翻到上方
  final belowTop = anchorTopLeft.dy + anchorSize.height + 6;
  final fitsBelow = belowTop + estimatedHeight <= screen.height - margin;
  final top = fitsBelow
      ? belowTop
      : (anchorTopLeft.dy - estimatedHeight - 6).clamp(margin, screen.height);

  return showGeneralDialog<T>(
    context: anchorContext,
    barrierLabel: '关闭菜单',
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, __, ___) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: width,
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
                // 从靠近锚点的一侧展开，视觉上"长"出来
                alignment:
                    fitsBelow ? Alignment.topRight : Alignment.bottomRight,
                child: _MenuCard<T>(items: items, selected: selected),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _MenuCard<T> extends StatelessWidget {
  final List<AppMenuItem<T>> items;
  final T? selected;

  const _MenuCard({required this.items, this.selected});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              _MenuRow<T>(
                item: item,
                selected: item.value == selected,
                onTap: () => Navigator.pop(context, item.value),
              ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow<T> extends StatelessWidget {
  final AppMenuItem<T> item;
  final bool selected;
  final VoidCallback onTap;

  const _MenuRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = item.isDangerous
        ? AppColors.danger
        : (selected ? AppColors.primary : AppColors.textMain);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: selected ? AppColors.primaryLight : Colors.transparent,
        child: Row(
          children: [
            if (item.icon != null) ...[
              Icon(item.icon,
                  size: 17,
                  color: item.isDangerous
                      ? AppColors.danger
                      : (selected ? AppColors.primary : AppColors.textSecondary)),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(item.subtitle!,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textWeak),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check, size: 15, color: AppColors.primary),
            ],
          ],
        ),
      ),
    );
  }
}
