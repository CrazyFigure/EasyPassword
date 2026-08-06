/// 应用主题：浅粉主色 #F48FB1，对齐 Ardot 设计稿
library;

import 'dart:io';

import 'package:flutter/material.dart';

import 'constants.dart';

class AppTheme {
  /// 构建主题。
  ///
  /// [fontFamily] 为空时不覆盖 Flutter 的平台默认字体：Windows 使用
  /// Segoe UI，Android 使用设备 ROM 配置的 sans-serif；非空时使用用户从
  /// 当前设备已安装字体中选择的字体，并保留平台系统字体作为缺字回退。
  /// 字号缩放不在 TextTheme 上做乘法，统一由根 MediaQuery 处理，避免新版
  /// Flutter 对 fontSize 为空的 TextStyle 应用 factor 时触发断言。
  static ThemeData build({String? fontFamily}) {
    // 中文及缺字回退只引用系统字体，不随应用打包第三方字体文件。
    final fontFamilyFallback = Platform.isWindows
        ? const <String>['Microsoft YaHei UI', 'Microsoft YaHei', 'Segoe UI']
        : Platform.isAndroid
            ? const <String>['Noto Sans CJK SC', 'Roboto', 'sans-serif']
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
      // null 表示完全交给平台选择默认字体；显式值来自已安装字体列表。
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );

    final textTheme = base.textTheme.apply(
      bodyColor: AppColors.textMain,
      displayColor: AppColors.textMain,
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textMain,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        ),
        iconTheme: const IconThemeData(color: AppColors.textMain),
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
