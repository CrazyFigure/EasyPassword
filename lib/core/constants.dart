/// EasyPassword 全局常量与设计令牌
/// 对齐 Ardot 设计稿（浅粉主题 #F48FB1）
library;

import 'package:package_info_plus/package_info_plus.dart';

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

  // 悬浮提示（袖珍 pill）：主体统一深色，语义只由左侧小图标承担。
  // 页面上的 success/danger 是给浅底用的，放到 #262626 上会发闷，
  // 因此这里各提亮一档，保证 14px 图标在深色 pill 上依然清晰。
  static const Color toastSurface = Color(0xFF262626);
  static const Color toastSuccess = Color(0xFF3DDC97);
  static const Color toastError = Color(0xFFFF8A8A);

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
  static const String secureKeyboardEnabled = 'secure_keyboard_enabled';
  static const String webdavEnabled = 'webdav_enabled';
  static const String webdavUrl = 'webdav_url';
  static const String webdavUser = 'webdav_username';
  static const String webdavPass = 'webdav_password';
  static const String webdavPath = 'webdav_path';
  static const String webdavAutoSyncEnabled = 'webdav_auto_sync_enabled';
  static const String webdavAutoSyncInterval = 'webdav_auto_sync_interval';
  static const String syncRevision = 'sync_revision';
  // 旧版共用排序键仅用于升级兼容；新版按密码/API Key 分区独立保存。
  static const String sortMode = 'sort_mode';
  static const String passwordSortMode = 'sort_mode_password';
  static const String apikeySortMode = 'sort_mode_apikey';
  static const String defaultTab = 'default_tab';
  static const String deviceKey = 'device_key'; // 无应用锁时的本地密钥
  static const String tabVisibility = 'tab_visibility'; // json: 底部栏开关与顺序
  static const String revealAll = 'reveal_all'; // 是否显示全部密码
  // AI 识别接入点配置（json）。API Key 以明文存放：设置项在同步合并时按 value
  // 原样复制（见 WebDavService._applySnapshot），若用本机 device_key 加密，
  // 其他设备将无法解密。快照整体仍由 WebDAV 凭据派生密钥加密后才上传。
  static const String aiProviders = 'ai_providers';
  static const String aiCustomPrompt = 'ai_custom_prompt'; // 用户追加的识别提示词
}

/// WebDAV 新配置的默认值。远端路径独立于服务器根地址，便于应用自动建目录。
class WebDavDefaults {
  static const String remotePath = '/EasyPassword';
}

/// ---- 应用信息与更新检查（对齐 Flutter 构建版本与 GitHub Releases）----
class AppInfo {
  AppInfo._();

  // 应用启动阶段写入的真实包版本。初始化完成前保留空值，禁止再用易过期的硬编码版本兜底。
  static String _currentVersion = '';

  /// 当前 Flutter 构建产物的语义版本。必须先调用 [initialize]，再创建依赖版本号的服务或页面。
  static String get currentVersion => _currentVersion;

  /// 从平台包元数据初始化版本号：本地开发读取 pubspec.yaml，正式发布读取 CI
  /// 通过 --build-name 写入的 Git 标签版本，保证界面、EXE/APK 与安装包版本一致。
  static Future<void> initialize() async {
    if (_currentVersion.isNotEmpty) return;
    final packageInfo = await PackageInfo.fromPlatform();
    final version =
        packageInfo.version.trim().replaceFirst(RegExp(r'^[vV]'), '');
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
      throw StateError('应用版本号格式无效：${packageInfo.version}');
    }
    _currentVersion = version;
  }

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
