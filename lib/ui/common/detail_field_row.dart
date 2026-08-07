/// 详情页统一字段行：标签定宽 → 值同起点 → 操作列对齐
///
/// 此前用户名 / 密码 / 备注各自手写 Row，导致三处问题：
/// 标签宽度不一使值的起始位置参差、备注多带一个「：」与其他字段格式不符、
/// 操作按钮数量不同导致右侧不齐。这里统一为一个组件，
/// 让同一张卡片内所有字段共享同一条标签线、值线与操作列。
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import 'copy_util.dart';
import 'row_action_menu.dart';

/// 窄屏阈值，与 row_action_menu 保持一致
const double _kCompactWidth = 420;

/// 标签列宽度：以最长标签「平台密码」四字为准，
/// 保证同卡片内各行的值从同一竖向位置开始。
double fieldLabelWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width < _kCompactWidth ? 58 : 66;

/// 字段区相对卡片的左缩进：仅让开拖拽把手的宽度，
/// 使字段与行头图标左对齐，不做多余的层层递进。
double fieldIndent(BuildContext context) =>
    MediaQuery.sizeOf(context).width < _kCompactWidth ? 22 : 26;

/// 统一字段行。
///
/// [value] 传入已处理好的显示文本（明文或等长星号）；
/// [obscurable] 为真时在最左操作列渲染显示/隐藏按钮，否则留空占位。
/// 操作列顺序固定为：显示/隐藏 → 复制 → 更多，缺项以空插槽占位。
class DetailFieldRow extends StatelessWidget {
  final String label;
  final String value;

  /// 是否可遮挡（渲染显示/隐藏按钮）
  final bool obscurable;
  final bool revealed;
  final VoidCallback? onToggle;

  /// 复制取值回调；为 null 时不渲染复制按钮
  final Future<String?> Function()? onCopy;
  final String? copyLabel;

  /// 行尾「更多」列，通常传 RowActionMenu；为 null 时空占位
  final Widget? menu;

  /// 值为空时的占位文案，例如「未设置」
  final String emptyHint;

  /// 值是否用强调样式（行头下的主要字段）
  final bool emphasized;

  /// 解密尚未完成：此时值为空并不代表字段没有值，
  /// 需抑制「未设置」占位与操作按钮，避免闪烁与误判
  final bool pending;

  const DetailFieldRow({
    super.key,
    required this.label,
    required this.value,
    this.obscurable = false,
    this.revealed = false,
    this.onToggle,
    this.onCopy,
    this.copyLabel,
    this.menu,
    this.emptyHint = '未设置',
    this.emphasized = false,
    this.pending = false,
  });

  @override
  Widget build(BuildContext context) {
    // 加载中视作「有值但未就绪」，不显示空占位也不禁用按钮
    final isEmpty = value.isEmpty && !pending;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(width: fieldIndent(context)),
          // 标签列：定宽，各行值因此从同一位置开始
          SizedBox(
            width: fieldLabelWidth(context),
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textWeak),
            ),
          ),
          Expanded(
            child: Text(
              isEmpty ? emptyHint : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: emphasized ? 14 : 13,
                fontWeight: emphasized ? FontWeight.w500 : FontWeight.w400,
                color: isEmpty ? AppColors.textFaint : AppColors.textMain,
                // 等宽数字：手机号与星号纵向更齐整
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          // 显示/隐藏在复制之前：先决定看不看得见，再决定取不取走
          ActionSlot(
            child: obscurable && !isEmpty
                ? IconButton(
                    icon: Icon(
                      revealed ? Icons.visibility : Icons.visibility_off,
                      size: 16,
                      color: AppColors.textWeak,
                    ),
                    tooltip: revealed ? '隐藏' : '显示',
                    visualDensity: VisualDensity.compact,
                    onPressed: onToggle,
                  )
                : null,
          ),
          ActionSlot(
            child: onCopy != null && !isEmpty
                ? CopyIconButton(
                    label: copyLabel ?? label,
                    size: 16,
                    onResolve: onCopy!,
                  )
                : null,
          ),
          menu ?? const ActionSlot(),
        ],
      ),
    );
  }
}
