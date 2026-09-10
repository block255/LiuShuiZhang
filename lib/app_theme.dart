import 'package:flutter/material.dart';

/// 「流水账」全局配色
/// 视觉稿 v1：蓝白 · 数据优先 · 密度适中
/// 原则：主色蓝只做点缀，红绿只属于金额数据。
class AppColors {
  // 主色（点缀用：导航选中/按钮/选中态）
  static const primary = Color(0xFF2563EB);
  static const primarySoft = Color(0xFFEFF6FF); // 浅蓝底（图标圆底/选中背景）

  // 背景与分区
  static const background = Color(0xFFFFFFFF);
  static const surfaceGroup = Color(0xFFF5F7FA);

  // 文字
  static const textMain = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);

  // 分隔
  static const divider = Color(0xFFE5E7EB);

  // 数据语义色（仅允许用于金额与汇总数字）
  static const income = Color(0xFF059669);
  static const expense = Color(0xFFDC2626);

  // 提示/警示色（非数据色：只用于"盲区提醒/需授权"这类提示条，不参与金额语义）
  static const warn = Color(0xFFC2410C);
  static const warnSoft = Color(0xFFFFF7ED);
}

/// 全局主题
class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.background,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textMain,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textMain,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.background,
        indicatorColor: AppColors.primarySoft,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textSecondary,
            size: 24,
          );
        }),
      ),
    );
  }
}
