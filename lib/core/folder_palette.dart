/// 文件夹配色：可选调色板与取色规则
library;

import 'package:flutter/material.dart';

import 'constants.dart';

/// 文件夹可选颜色（柔和低饱和，与浅粉主题协调）
class FolderPalette {
  /// 调色板顺序即 UI 上的展示顺序，第一个为主题默认粉
  static const List<Color> colors = [
    AppColors.primary, // 主题粉
    Color(0xFFEF9A9A), // 珊瑚红
    Color(0xFFFFB74D), // 暖橙
    Color(0xFFFFD54F), // 明黄
    Color(0xFF81C784), // 草绿
    Color(0xFF4DB6AC), // 青碧
    Color(0xFF64B5F6), // 天蓝
    Color(0xFF7986CB), // 靛蓝
    Color(0xFFBA68C8), // 薰衣草紫
    Color(0xFFA1887F), // 摩卡棕
    Color(0xFF90A4AE), // 石板灰
  ];

  /// 文件夹图标主色：未自定义时回退到主题粉
  static Color colorOf(int? value) =>
      value == null ? AppColors.primary : Color(value);

  /// 图标底色：主色的浅色版本（同色系低透明度铺底）
  static Color bgOf(int? value) => colorOf(value).withValues(alpha: 0.16);
}
