/// 新增元素后把它滚进视野的共用逻辑。
///
/// 此前列表新增一条后仍停在原处：按名称排序时新条目可能落在列表任意位置，
/// 自定义排序时落在末尾，两种情况用户都得自己翻页去找，等于"存完了不知道
/// 存到哪儿去了"。这里统一由新增方在写库成功后调用，把目标行滚到视野中。
library;

import 'package:flutter/material.dart';

/// 定位动画时长与曲线：够快不拖沓，又能让用户看清列表滚动过去的方向，
/// 从而建立"新条目在这个位置"的空间感——直接 jumpTo 会丢掉这个信息。
const Duration _kRevealDuration = Duration(milliseconds: 320);
const Curve _kRevealCurve = Curves.easeOutCubic;

/// 根列表与文件夹内页共用的列表留白。
///
/// 定义在这里而不是各写一份：[revealIndex] 反推行高时要减掉这份留白，
/// 两处一旦写岔，定位就会偏移半屏。
const EdgeInsets kListPadding = EdgeInsets.fromLTRB(16, 4, 16, 80);

/// 把 [controller] 控制的列表滚动到第 [index] 行，尽量让该行居中。
///
/// 不引入 scrollable_positioned_list：本项目列表行结构完全统一（头像 +
/// 标题 + 副标题，文件夹行与条目行同高），可由内容总高反推单行高度直接
/// 算出目标偏移，精度足够且不增加依赖。
Future<void> revealIndex({
  required ScrollController controller,
  required int index,
  required int itemCount,
  EdgeInsets padding = kListPadding,
}) async {
  if (!controller.hasClients || index < 0 || itemCount <= 0) return;
  final position = controller.position;
  final viewport = position.viewportDimension;
  // 内容总高 = 剩余可滚动距离 + 一屏；再去掉列表自身的上下留白才是所有行的高度
  final rowsHeight = position.maxScrollExtent + viewport - padding.vertical;
  if (rowsHeight <= 0) return;
  final rowHeight = rowsHeight / itemCount;
  // 目标行居中；首尾几行会被 clamp 到边界，不会滚出空白
  final target = padding.top + index * rowHeight - (viewport - rowHeight) / 2;
  final clamped =
      target.clamp(position.minScrollExtent, position.maxScrollExtent);
  // 已经在位就不要再动一下，避免无意义的抖动
  if ((clamped - position.pixels).abs() < 1) return;
  await controller.animateTo(
    clamped,
    duration: _kRevealDuration,
    curve: _kRevealCurve,
  );
}

/// 把列表滚到底部。
///
/// 用于详情页：账号 / 用户 / API Key 都追加在末尾，新增表单也展开在末尾，
/// 滚到底就是滚到目标。详情页各卡片高度不一（备注行可有可无、API Key 数量
/// 不等），反推行高不成立，而"到底部"本身就是精确的。
///
/// 分两次滚动：新展开的卡片里有 autofocus 的输入框，聚焦会带来键盘内边距，
/// 内嵌的账号列表也要等自己那一帧才定高，因此第一次 animateTo 结束时
/// maxScrollExtent 往往还会再长一截。滚完再取一次，长了就补上。
Future<void> revealBottom(ScrollController controller) async {
  if (!controller.hasClients) return;
  await _animateToBottom(controller);
  // 等布局稳定后再看一眼终点有没有变
  await WidgetsBinding.instance.endOfFrame;
  if (!controller.hasClients) return;
  await _animateToBottom(controller);
}

Future<void> _animateToBottom(ScrollController controller) async {
  final position = controller.position;
  if ((position.maxScrollExtent - position.pixels).abs() < 1) return;
  await controller.animateTo(
    position.maxScrollExtent,
    duration: _kRevealDuration,
    curve: _kRevealCurve,
  );
}

/// 在下一帧执行 [action]。
///
/// 新增后必须等列表用新数据重新布局完，滚动区间（maxScrollExtent）才是新的；
/// 在 setState 之后立刻滚动会按旧高度计算，停在错误的位置。
void afterNextFrame(VoidCallback action) {
  WidgetsBinding.instance.addPostFrameCallback((_) => action());
}

/// 把 [key] 标记的组件滚进视野。
///
/// 用于目标不在页面末尾、也算不出行高的场景：例如 API Key 追加在所属用户
/// 卡片的中间位置，滚到底会滑过头。[Scrollable.ensureVisible] 自己会找到
/// 外层滚动容器并做最小滚动，因此不需要传 ScrollController。
///
/// [alignment] 取 1.0 表示把目标对齐到视口底部——新增的元素总是出现在
/// 卡片下方，贴着底边露出即可，不必把整张卡片顶到屏幕中间。
Future<void> revealKey(GlobalKey key, {double alignment = 1.0}) async {
  final context = key.currentContext;
  if (context == null) return;
  await Scrollable.ensureVisible(
    context,
    alignment: alignment,
    duration: _kRevealDuration,
    curve: _kRevealCurve,
  );
}
