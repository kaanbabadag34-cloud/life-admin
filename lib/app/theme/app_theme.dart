import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // =========================
  // BRAND
  // =========================

  static const Color accent = Color(0xFF7567E8);
  static const Color accentLight = Color(0xFF968BFF);

  // =========================
  // DARK
  // =========================

  static const Color darkBackground = Color(0xFF0D0F12);
  static const Color darkSurface = Color(0xFF171A1F);
  static const Color darkSurfaceSoft = Color(0xFF1D2026);
  static const Color darkBorder = Color(0xFF2B2F36);

  static const Color darkText = Color(0xFFF4F4F6);
  static const Color darkTextSecondary = Color(0xFFA7A9B0);

  // =========================
  // LIGHT
  // =========================

  static const Color lightBackground = Color(0xFFF7F7F8);
  static const Color lightSurface = Colors.white;
  static const Color lightBorder = Color(0xFFE5E5E8);

  static const Color lightText = Color(0xFF17171A);
  static const Color lightTextSecondary = Color(0xFF74747C);

  // =========================
  // LIGHT THEME
  // =========================

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: accent,
      surface: lightSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      colorScheme: scheme,

      scaffoldBackgroundColor: lightBackground,

      dividerColor: lightBorder,

      cardColor: lightSurface,

      appBarTheme: const AppBarTheme(
        backgroundColor: lightBackground,
        foregroundColor: lightText,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),

      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: lightText,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.7,
        ),
        titleLarge: TextStyle(
          color: lightText,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: lightText,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: lightText,
          fontSize: 15,
        ),
        bodyMedium: TextStyle(
          color: lightTextSecondary,
          fontSize: 14,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightBackground,
        hintStyle: const TextStyle(
          color: lightTextSecondary,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: lightBorder,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: lightBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: accent,
          ),
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightSurface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
    );
  }

  // =========================
  // DARK THEME
  // =========================

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: accentLight,
      surface: darkSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      colorScheme: scheme,

      scaffoldBackgroundColor: darkBackground,

      dividerColor: darkBorder,

      cardColor: darkSurface,

      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        foregroundColor: darkText,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),

      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: darkText,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.7,
        ),
        titleLarge: TextStyle(
          color: darkText,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: darkText,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: darkText,
          fontSize: 15,
        ),
        bodyMedium: TextStyle(
          color: darkTextSecondary,
          fontSize: 14,
        ),
      ),

      iconTheme: const IconThemeData(
        color: darkText,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkText,
          side: const BorderSide(
            color: darkBorder,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF111318),

        hintStyle: const TextStyle(
          color: darkTextSecondary,
        ),

        labelStyle: const TextStyle(
          color: darkTextSecondary,
        ),

        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: darkBorder,
          ),
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: darkBorder,
          ),
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: accentLight,
          ),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 72,

        backgroundColor: const Color(
          0xFF121418,
        ),

        indicatorColor: accent.withValues(
          alpha: 0.25,
        ),

        elevation: 0,

        surfaceTintColor: Colors.transparent,

        labelTextStyle:
            WidgetStateProperty.resolveWith(
          (states) {
            final selected = states.contains(
              WidgetState.selected,
            );

            return TextStyle(
              color: selected
                  ? darkText
                  : darkTextSecondary,
              fontSize: 12,
              fontWeight: selected
                  ? FontWeight.w600
                  : FontWeight.w400,
            );
          },
        ),

        iconTheme:
            WidgetStateProperty.resolveWith(
          (states) {
            final selected = states.contains(
              WidgetState.selected,
            );

            return IconThemeData(
              color: selected
                  ? accentLight
                  : darkTextSecondary,
              size: 23,
            );
          },
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: darkTextSecondary,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkSurfaceSoft,
        contentTextStyle: const TextStyle(
          color: darkText,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}