import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF5B5FEF);
  static const background = Color(0xFFF7F7FA);
  static const surface = Colors.white;

  static const textPrimary = Color(0xFF17171C);
  static const textSecondary = Color(0xFF73737D);

  static const success = Color(0xFF22A06B);
  static const warning = Color(0xFFF5A524);
  static const error = Color(0xFFE5484D);
}

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ),
      fontFamily: 'Arial',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
    );
  }
}
