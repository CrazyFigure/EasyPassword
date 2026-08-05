/// 统一的确认对话框：规范按钮大小与样式，避免不同弹窗按钮尺寸不一致
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// 确认弹窗内两个按钮的统一尺寸。
///
/// 治本说明：主题里 FilledButton 的 minimumSize 是 (120,44)，而 TextButton 用的是
/// Material 默认的 (64,36)，两者放在同一 actions 行里就会一大一小（截图中的
/// 「取消 / 删除」）。这里对两个按钮显式指定同一尺寸，从源头对齐。
const Size _kActionSize = Size(88, 44);

/// 显示确认对话框
///
/// [title] 标题
/// [content] 内容文本
/// [cancelText] 取消按钮文本（默认"取消"）
/// [confirmText] 确认按钮文本（默认"确定"）
/// [isDangerous] 是否危险操作（默认false），为true时确认按钮使用危险色
/// [contentWidget] 自定义内容组件（与content二选一）
///
/// 返回 true 表示用户点击了确认，false 或 null 表示取消
Future<bool?> showConfirmDialog({
  required BuildContext context,
  required String title,
  String? content,
  Widget? contentWidget,
  String cancelText = '取消',
  String confirmText = '确定',
  bool isDangerous = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: contentWidget ?? (content != null ? Text(content) : null),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: _kActionSize,
          ),
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelText),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: isDangerous ? AppColors.danger : AppColors.primary,
            minimumSize: _kActionSize,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
}
