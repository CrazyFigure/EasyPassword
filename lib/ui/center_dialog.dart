/// 统一居中弹窗：所有输入框/选择框弹窗改为从屏幕中间弹出
/// （替代 showModalBottomSheet 的底部弹出方式），风格对齐现代卡片式 Dialog。
library;

import 'package:flutter/material.dart';

/// 以居中 Dialog 形式展示弹窗内容。
///
/// - 内容最大宽度 [maxWidth]、最大高度为屏幕的 82%，超高自动滚动；
/// - 键盘弹出时借助 SingleChildScrollView + viewInsets 自动避让，
///   保证底部按钮不被遮挡；
/// - 圆角 20、无投影的高对比白卡，与 AppTheme.dialogTheme 一致。
Future<T?> showCenterDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxWidth = 420,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final maxHeight = MediaQuery.of(ctx).size.height * 0.82;
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 4,
              right: 4,
              top: 4,
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: builder(ctx),
          ),
        ),
      );
    },
  );
}
