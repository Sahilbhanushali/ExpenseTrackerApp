import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Vibrant, high-contrast base
  static const Color primary = Color(0xFF8A2BE2); // Electric Purple
  static const Color primaryDark = Color(0xFF5E00A3);

  /// Vibrant, multi-stop gradient for hero cards
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFF007F), // Hot Pink
      Color(0xFF8A2BE2), // Electric Purple
      Color(0xFFFF7F50), // Coral
    ],
  );

  static const Color income = Color(0xFF00FF7F); // Spring Green
  static const Color expense = Color(0xFFFF007F); // Hot Pink
  static const Color warning = Color(0xFFFFEA00); // Yellow

  static const Color background = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF121212); // Off-black
  static const Color backgroundDark = Color(0xFF000000); // Pure black

  static const Color textPrimary = Color(0xFF0F0F0F);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryDark = Color(0xFFA0A0A0);

  static const Color border = Color(0xFFEEEEEE);
  static const Color borderDark = Color(0xFF222222);

  // ---- glass surfaces + aurora background ----
  static const Color voidLight = Color(0xFFF9F9F9);
  static const Color voidDark = Color(0xFF080808);
  static const Color glassLight = Color(
    0xCCFFFFFF,
  ); // slightly more opaque glass
  static const Color glassDark = Color(0x8C1A1A1A);
  static const Color glassBorderLight = Color(0x40000000);
  static const Color glassBorderDark = Color(0x26FFFFFF);

  static const List<Color> auroraBlobsLight = [
    Color(0x66FF007F), // hot pink
    Color(0x668A2BE2), // purple
    Color(0x6600FF7F), // lime
    Color(0x66FFEA00), // yellow
  ];
  static const List<Color> auroraBlobsDark = [
    Color(0x33FF007F),
    Color(0x338A2BE2),
    Color(0x3300FF7F),
    Color(0x33FFEA00),
  ];

  static const List<Color> categoryPalette = [
    Color(0xFFFF007F), // Hot Pink
    Color(0xFF8A2BE2), // Electric Purple
    Color(0xFF00FF7F), // Lime/Spring Green
    Color(0xFFFF7F50), // Coral
    Color(0xFF00FFFF), // Cyan/Teal
    Color(0xFFFFEA00), // Electric Yellow
    Color(0xFFFF1493), // Deep Pink
    Color(0xFF00BFFF), // Deep Sky Blue
    Color(0xFF7FFF00), // Chartreuse
    Color(0xFFFF4500), // Orange Red
    Color(0xFFBA55D3), // Medium Orchid
    Color(0xFF1E90FF), // Dodger Blue
  ];

  static Color categoryColor(String category) {
    final idx = category.hashCode.abs() % categoryPalette.length;
    return categoryPalette[idx];
  }
}
