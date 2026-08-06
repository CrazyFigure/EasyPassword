/// EasyPassword 全局常量与设计令牌
/// 对齐 Ardot 设计稿（浅粉主题 #F48FB1）
library;

import 'package:flutter/material.dart';

/// ---- 设计令牌 ----
class AppColors {
  // 主色系
  static const Color primary = Color(0xFFF48FB1); // 浅粉主色
  static const Color primaryDark = Color(0xFFEC6391); // 主色深一档（按压态）
  static const Color primaryLight = Color(0xFFFFF0F3); // 主色浅底（选中卡片）
  static const Color primaryLightBg = Color(0xFFFBE3EA); // 更浅背景（浅粉按钮底）

  // 中性色
  static const Color background = Color(0xFFF9F9F9); // 页面暖白底
  static const Color card = Color(0xFFFFFFFF); // 卡片
  static const Color border = Color(0xFFEDEDED); // 描边
  static const Color divider = Color(0xFFF0F0F0); // 分隔线

  // 文字
  static const Color textMain = Color(0xFF262626);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textWeak = Color(0xFF999999);
  static const Color textFaint = Color(0xFFCCCCCC);

  // 语义色
  static const Color danger = Color(0xFFFF6B6B);
  static const Color dangerLight = Color(0xFFFFF0F0);
  static const Color success = Color(0xFF10A37F);

  // 站点图标色（列表缩略）
  static const Color google = Color(0xFF0B5B8E);
  static const Color github = Color(0xFF24292F);
  static const Color aws = Color(0xFFFF9900);
  static const Color apple = Color(0xFF000000);
  static const Color openai = Color(0xFF10A37F);
}

/// ---- 尺寸 ----
class AppDimens {
  static const double pagePadding = 16;
  static const double cardRadius = 12;
  static const double sheetRadius = 16;
  static const double fabSize = 56;
  static const double navBarHeight = 64;
  static const double itemHeight = 64;
}

/// ---- 数据库键 ----
class DbKeys {
  static const String appLockEnabled = 'app_lock_enabled';
  static const String appLockPin = 'app_lock_pin_hash';
  static const String appLockSalt = 'app_lock_salt';
  static const String securityQuestion = 'security_question';
  static const String securityAnswer = 'security_answer_hash';
  static const String fontScale = 'font_scale'; // FontSizeMode.name；兼容旧数值
  static const String fontFamily = 'font_family'; // 当前设备字体；空值=系统默认
  static const String webdavUrl = 'webdav_url';
  static const String webdavUser = 'webdav_username';
  static const String webdavPass = 'webdav_password';
  static const String syncRevision = 'sync_revision';
  // 旧版共用排序键仅用于升级兼容；新版按密码/API Key 分区独立保存。
  static const String sortMode = 'sort_mode';
  static const String passwordSortMode = 'sort_mode_password';
  static const String apikeySortMode = 'sort_mode_apikey';
  static const String defaultTab = 'default_tab';
  static const String deviceKey = 'device_key'; // 无应用锁时的本地密钥
  static const String tabVisibility = 'tab_visibility'; // json: 底部栏开关与顺序
  static const String revealAll = 'reveal_all'; // 是否显示全部密码
}

/// ---- 应用信息与更新检查（对齐 GitHub Releases 版本号）----
class AppInfo {
  /// 当前版本：与 pubspec.yaml version 保持一致，CI 按 tag 出包（v1.1.0 -> 1.1.0）
  static const String currentVersion = '1.1.0';

  /// GitHub 仓库主页
  static const String repoUrl = 'https://github.com/CrazyFigure/EasyPassword';

  /// GitHub Releases 页面（有新版本时引导用户跳转下载）
  static const String releasePageUrl = '$repoUrl/releases/latest';

  /// GitHub API 最新 Release 接口（检测更新用）
  static const String releaseApiUrl =
      'https://api.github.com/repos/CrazyFigure/EasyPassword/releases/latest';
}

/// 条目类型（3.1 两类数据分离）
class ItemType {
  static const String password = 'password';
  static const String apikey = 'apikey';
}
