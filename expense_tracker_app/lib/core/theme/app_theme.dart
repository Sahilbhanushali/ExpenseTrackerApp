import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final base = ThemeData(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: Brightness.light),
      // Transparent so the single root AuroraBackground (see main.dart) shows
      // through every screen instead of each Scaffold painting over it.
      scaffoldBackgroundColor: Colors.transparent,
      useMaterial3: true,
    );
    return base.copyWith(
      textTheme: _textTheme(base.textTheme, AppColors.textPrimary, AppColors.textSecondary),
      cardTheme: _cardTheme(AppColors.glassLight, AppColors.glassBorderLight),
      appBarTheme: _appBarTheme(AppColors.textPrimary),
      inputDecorationTheme: _inputTheme(AppColors.surface, AppColors.border),
      elevatedButtonTheme: _elevatedButtonTheme(),
      dividerColor: AppColors.border,
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: Brightness.dark),
      scaffoldBackgroundColor: Colors.transparent,
      useMaterial3: true,
    );
    return base.copyWith(
      textTheme: _textTheme(base.textTheme, AppColors.textPrimaryDark, AppColors.textSecondaryDark),
      cardTheme: _cardTheme(AppColors.glassDark, AppColors.glassBorderDark),
      appBarTheme: _appBarTheme(AppColors.textPrimaryDark),
      inputDecorationTheme: _inputTheme(AppColors.surfaceDark, AppColors.borderDark),
      elevatedButtonTheme: _elevatedButtonTheme(),
      dividerColor: AppColors.borderDark,
    );
  }

  static TextTheme _textTheme(TextTheme base, Color primary, Color secondary) {
    final scaled = GoogleFonts.manropeTextTheme(base);
    return scaled.copyWith(
      headlineSmall: scaled.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: primary, letterSpacing: -0.5),
      titleLarge: scaled.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: primary),
      titleMedium: scaled.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: primary),
      bodyLarge: scaled.bodyLarge?.copyWith(color: primary),
      bodyMedium: scaled.bodyMedium?.copyWith(color: primary),
      bodySmall: scaled.bodySmall?.copyWith(color: secondary),
      labelMedium: scaled.labelMedium?.copyWith(color: secondary),
    );
  }

  static CardThemeData _cardTheme(Color glassFill, Color glassBorder) {
    return CardThemeData(
      color: glassFill,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: glassBorder),
      ),
    );
  }

  static AppBarTheme _appBarTheme(Color fg) {
    return AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    );
  }

  static InputDecorationTheme _inputTheme(Color fill, Color border) {
    return InputDecorationTheme(
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  static ElevatedButtonThemeData _elevatedButtonTheme() {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        elevation: 0,
      ),
    );
  }
}
