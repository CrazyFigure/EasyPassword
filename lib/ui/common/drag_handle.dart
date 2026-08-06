/// 拖动排序相关的共用组件
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// 整行长按拖动的触发时长。250ms 足以区分普通点击，同时比 Flutter 默认
/// kLongPressTimeout（500ms）更利落；拖动把手仍保持按下即拖。
const Duration _quickDragDelay = Duration(milliseconds: 250);

/// 可调延迟的整行拖动监听器。
///
/// Flutter 自带 ReorderableDelayedDragStartListener 没有暴露 delay 参数，
/// 因此仅替换其识别器，复用框架原本的拖动排序与手势冲突处理。
class QuickReorderableDelayedDragStartListener
    extends ReorderableDragStartListener {
  const QuickReorderableDelayedDragStartListener({
    super.key,
    required super.child,
    required super.index,
    super.enabled,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return DelayedMultiDragGestureRecognizer(
      delay: _quickDragDelay,
      debugOwner: this,
    );
  }
}

/// 统一的拖动把手：鼠标悬停显示抓手光标，包裹唯一的把手图标。
///
/// 使用前提：父级 ReorderableListView 必须设置 buildDefaultDragHandles: false，
/// 否则桌面端会额外叠加一个默认把手，造成图标重复错位。
class DragHandle extends StatelessWidget {
  final int index;
  final IconData icon;
  final double size;

  const DragHandle({
    super.key,
    required this.index,
    this.icon = Icons.drag_handle,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(
      index: index,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Icon(icon, size: size, color: AppColors.textFaint),
        ),
      ),
    );
  }
}

/// ReorderableListView 的 proxyDecorator：拖动中的元素保持圆角 + 柔和投影。
///
/// 默认实现用的是直角 Material 阴影，圆角卡片拖起来会露出方形底板，
/// 这里改为与卡片一致的圆角裁剪。
Widget roundedDragProxy(Widget child, int index, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      // 抬起过程中轻微放大并加深阴影，落下时回位
      final t = Curves.easeInOut.transform(animation.value);
      return Transform.scale(
        scale: 1 + 0.02 * t,
        child: Material(
          color: Colors.transparent,
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimens.cardRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14 * t),
                  blurRadius: 16 * t,
                  offset: Offset(0, 4 * t),
                ),
              ],
            ),
            child: child,
          ),
        ),
      );
    },
    child: child,
  );
}
