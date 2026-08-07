/// 统一复制到剪贴板的工具：复制 + 袖珍悬浮提示
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import 'app_toast.dart';

/// 复制文本到剪贴板并弹出袖珍悬浮提示。
/// [label] 用于提示文案，例如「密码已复制」。
Future<void> copyToClipboard(
  BuildContext context,
  String text, {
  String label = '内容',
}) async {
  if (text.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  showAppToast(context, '$label已复制', kind: ToastKind.success);
}

/// 统一样式的复制图标按钮（行内操作用）
class CopyIconButton extends StatelessWidget {
  /// 取待复制文本；返回 null / 空串时按钮置灰不可点
  final Future<String?> Function() onResolve;
  final String label;
  final double size;

  const CopyIconButton({
    super.key,
    required this.onResolve,
    required this.label,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.copy_rounded, size: size, color: AppColors.textWeak),
      tooltip: '复制$label',
      visualDensity: VisualDensity.compact,
      onPressed: () async {
        final text = await onResolve();
        if (text == null || text.isEmpty) return;
        if (!context.mounted) return;
        await copyToClipboard(context, text, label: label);
      },
    );
  }
}
