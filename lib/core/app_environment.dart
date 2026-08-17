/// 应用运行环境：统一决定开发版与正式版是否隔离本地数据。
library;

import 'package:flutter/foundation.dart';

abstract final class AppEnvironment {
  /// Debug/Profile 默认使用开发数据；Release 默认使用正式数据。
  /// 本地调试 Release 构建时可通过
  /// --dart-define=EASYPASSWORD_DEV_STORAGE=true 强制使用开发数据。
  static const bool usesDevelopmentStorage = bool.fromEnvironment(
    'EASYPASSWORD_DEV_STORAGE',
    defaultValue: !kReleaseMode,
  );

  /// 可选的开发数据目录。相对路径以启动工作目录为基准；未传时自动定位项目根目录。
  static const String configuredDevelopmentDataDirectory =
      String.fromEnvironment('EASYPASSWORD_DEV_DATA_DIR');

  /// 开发工作库固定放在 Git 忽略的本机私有目录，不内置任何真实数据快照。
  static const String developmentDatabaseFileName = 'easypassword.db';

  /// WebDAV 快照也按环境使用不同文件名，防止开发库经自动同步污染正式数据。
  static const String webDavSnapshotFileName = usesDevelopmentStorage
      ? 'easypassword-dev-snapshot.json.enc'
      : 'easypassword-snapshot.json.enc';
}
