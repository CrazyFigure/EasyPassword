/// 列表行尾的紧凑操作区：「⋮」菜单 + 「›」指示箭头
///
/// 原先每个列表各自在 ListTile.trailing 里手写 IconButton + Icon，有两个问题：
/// 1. IconButton 默认带 48×48 的最小触摸区与 8px 内边距，两个图标合计吃掉
///    近百像素，条目名称在移动端被过早截断；
/// 2. ListTile 自身还有 16px 右内边距，图标离屏幕边缘留白过多，视觉上却又
///    紧贴标题，观感是"挤在中间"。
///
/// 这里统一收口：收紧图标自身的占位、把箭头贴向右缘，同时用 [kRowTrailingHitSize]
/// 保证「⋮」的实际可点区域不小于无障碍下限——省的是留白，不是触摸区。
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// 「⋮」的可点区域尺寸。视觉上图标只有 18px，但热区保持在这个尺寸，
/// 满足触摸目标下限，不因为排版收紧而变得难点。
const double kRowTrailingHitSize = 40;

/// 行尾操作区：左为「⋮」菜单，右为「›」指示箭头。
///
/// [onMenu] 为空时「⋮」不可点（例如批量模式下的文件夹行）。
class RowTrailing extends StatelessWidget {
  /// 「⋮」的点击回调；需要拿到按钮自身位置来锚定弹出菜单，
  /// 因此回调携带按钮的 BuildContext。
  final Future<void> Function(BuildContext anchorContext)? onMenu;

  /// 「⋮」的无障碍提示，例如「条目操作」「文件夹操作」
  final String menuTooltip;

  const RowTrailing({
    super.key,
    required this.onMenu,
    required this.menuTooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Builder(
          builder: (btnContext) => IconButton(
            icon: const Icon(Icons.more_vert,
                size: 18, color: AppColors.textFaint),
            tooltip: menuTooltip,
            // 去掉默认的 8px 内边距与 48px 最小约束，改由 constraints 显式给热区。
            // 这里不能再叠 visualDensity.compact：它会在 constraints 之上又减
            // 8px，热区被缩到 32 而低于触摸目标下限。
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(
              width: kRowTrailingHitSize,
              height: kRowTrailingHitSize,
            ),
            onPressed:
                onMenu == null ? null : () => onMenu!(btnContext),
          ),
        ),
        // 箭头只是"可进入"的视觉提示，不可点，无需触摸区，贴紧右缘即可
        const Icon(Icons.chevron_right, size: 20, color: AppColors.textFaint),
      ],
    );
  }
}

/// 列表行的内容内边距。
///
/// 相比 ListTile 默认的左右各 16，右侧收到 4：行尾的箭头本就是贴边元素，
/// 留 16px 反而让图标组看起来往标题那边挤。左侧保持 16 不动。
const EdgeInsets kRowContentPadding = EdgeInsets.only(left: 16, right: 4);
