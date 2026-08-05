/// 应用主题：浅粉主色 #F48FB1，对齐 Ardot 设计稿
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:win32_registry/win32_registry.dart';

import 'constants.dart';

class AppTheme {
  /// 构建主题，[fontScale] 为字体缩放（默认 1.0 = 跟随系统），
  /// [systemFont] 为系统默认字体名（Windows 为字体名，Android 为 FontLoader 注册名）
  static ThemeData build({double fontScale = 1.0, String? systemFont}) {
    // Windows 使用系统字体，Android 使用 FontLoader 注册的字体
    final fontFamily = systemFont;
    // 中文 fallback 字体列表：Windows 主字体不含中文字形时回退
    final fontFamilyFallback = Platform.isWindows
        ? const <String>['Microsoft YaHei', 'SimSun', 'DengXian', 'SimHei']
        : null;

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.primaryDark,
        surface: AppColors.card,
        error: AppColors.danger,
      ),
      scaffoldBackgroundColor: AppColors.background,
      // 使用系统默认字体（Windows 从注册表读取 MessageFont；
      // Android 通过 FontLoader 加载系统字体文件）
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );

    final textTheme = base.textTheme.apply(
      bodyColor: AppColors.textMain,
      displayColor: AppColors.textMain,
    );

    return base.copyWith(
      textTheme: textTheme.apply(fontSizeFactor: fontScale),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textMain,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: AppColors.textMain),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.cardRadius),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(120, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          minimumSize: const Size(120, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textMain,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

/// 获取平台系统默认字体：
/// Windows 从注册表 [HKCU\Control Panel\Desktop\WindowMetrics] 读取 MessageFont 字体名；
/// Android 通过平台通道读取系统字体文件并用 FontLoader 注册为 "SystemFont"；
/// 返回 null 表示使用 Flutter 默认字体（兜底）
Future<String?> getSystemFont() async {
  if (Platform.isWindows) {
    return _readWindowsSystemFont();
  }
  if (Platform.isAndroid) {
    return _loadAndroidSystemFont();
  }
  return null;
}

/// Windows：从注册表读取系统默认字体名
String? _readWindowsSystemFont() {
  try {
    final key = CURRENT_USER.open(
      r'Control Panel\Desktop\WindowMetrics',
    );
    // MessageFont 格式: "FontName,fontHeight"（如 "Segoe UI,-12"）
    final msgFont = key.getString('MessageFont');
    if (msgFont != null && msgFont.isNotEmpty) {
      final commaIdx = msgFont.indexOf(',');
      if (commaIdx > 0) return msgFont.substring(0, commaIdx);
      return msgFont;
    }
    // 备选：CaptionFont（窗口标题栏字体）
    final captionFont = key.getString('CaptionFont');
    if (captionFont != null && captionFont.isNotEmpty) {
      final commaIdx = captionFont.indexOf(',');
      if (commaIdx > 0) return captionFont.substring(0, commaIdx);
      return captionFont;
    }
  } catch (_) {
    // 注册表读取失败（权限/键缺失），返回 null 由 Flutter 使用默认字体
  }
  return null;
}

/// Android：通过平台通道读取系统字体文件字节，用 FontLoader 注册为 "SystemFont"
Future<String?> _loadAndroidSystemFont() async {
  try {
    // 调用原生侧解析 fonts.xml 获取系统默认 sans-serif 字体文件字节
    final bytes = await const MethodChannel('easypassword/system_font')
        .invokeMethod<Uint8List>('getSystemFontBytes');
    if (bytes == null || bytes.isEmpty) return null;
    // 用 FontLoader 将字体字节注册到 Flutter 字体集合
    final loader = FontLoader('SystemFont');
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    return 'SystemFont';
  } catch (_) {
    // 读取/注册失败，返回 null 由 Flutter 使用默认 Roboto
    return null;
  }
}
