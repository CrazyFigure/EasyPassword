/// 当前设备已安装字体目录：仅在字体选择器展开后通过平台通道查询。
library;

import 'dart:io';

import 'package:flutter/services.dart';

class FontCatalogService {
  static const MethodChannel _channel =
      MethodChannel('easypassword/system_font');

  /// 读取 Windows 或 Android 已安装的系统字体族。
  ///
  /// 平台查询失败时返回空列表，由界面保留“系统默认”并展示可恢复的提示；
  /// 不在应用启动阶段调用，避免大量字体拖慢首屏。
  Future<List<String>> listInstalledFamilies() async {
    if (!Platform.isWindows && !Platform.isAndroid) return const [];
    try {
      final values =
          await _channel.invokeListMethod<String>('listSystemFonts') ??
              const [];
      final families = values
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty && !value.startsWith('@'))
          .toSet()
          .toList(growable: false);
      families.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return families;
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}
