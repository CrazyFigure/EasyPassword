/// 站点配色：主列表缩略图与详情页头像共用同一套取色规则，
/// 保证同一条目在两处显示同一颜色（需求：详情页颜色跟随列表）
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// 按条目名称取站点色：知名站点用品牌色，其余按名称哈希取固定色板。
///
/// 哈希取色对同一名称是稳定的，因此列表与详情页只要调用同一函数就必然一致。
Color siteColorFor(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('google')) return AppColors.google;
  if (lower.contains('github')) return AppColors.github;
  if (lower.contains('aws')) return AppColors.aws;
  if (lower.contains('apple')) return AppColors.apple;
  if (lower.contains('openai')) return AppColors.openai;
  // 其余按名字哈希取品牌色板
  const palette = [
    Color(0xFF5C6BC0),
    Color(0xFF26A69A),
    Color(0xFFEF5350),
    Color(0xFFAB47BC),
    Color(0xFFFFA726),
    Color(0xFF66BB6A),
  ];
  return palette[name.hashCode.abs() % palette.length];
}

/// 条目首字母（空名兜底为 ?）
String siteInitialFor(String name) =>
    name.isNotEmpty ? name[0].toUpperCase() : '?';
