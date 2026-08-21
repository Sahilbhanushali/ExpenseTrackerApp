import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF2E7D6B);
  static const Color primaryDark = Color(0xFF1B5E4F);

  /// The one restrained gradient in the app — the dashboard hero card only.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1F6F5C), Color(0xFF2E7D6B)],
  );
  static const Color income = Color(0xFF2E7D6B);
  static const Color expense = Color(0xFFD9534F);
  static const Color warning = Color(0xFFE0A800);

  static const Color background = Color(0xFFF7F8FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1E2126);
  static const Color backgroundDark = Color(0xFF15171A);

  static const Color textPrimary = Color(0xFF1A1D1F);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textPrimaryDark = Color(0xFFF2F3F5);
  static const Color textSecondaryDark = Color(0xFF9AA1AB);

  static const Color border = Color(0xFFE5E7EB);
  static const Color borderDark = Color(0xFF2C3036);

  // ---- glass surfaces + aurora background ----
  static const Color voidLight = Color(0xFFF0F1F4);
  static const Color voidDark = Color(0xFF0F1114);
  static const Color glassLight = Color(0x8CFFFFFF); // rgba(255,255,255,0.55)
  static const Color glassDark = Color(0x8C24262B); // rgba(36,38,43,0.55)
  static const Color glassBorderLight = Color(0x8CFFFFFF);
  static const Color glassBorderDark = Color(0x14FFFFFF); // rgba(255,255,255,0.08)

  static const List<Color> auroraBlobsLight = [
    Color(0x527896FF), // soft blue
    Color(0x47FF91C3), // soft pink
    Color(0x4796FFD7), // soft mint
    Color(0x3DFFD278), // soft gold
  ];
  static const List<Color> auroraBlobsDark = [
    Color(0x333A4DB8), // dimmer blue
    Color(0x2EB1548A), // dimmer pink
    Color(0x2E3E9C7C), // dimmer mint
    Color(0x26B89A46), // dimmer gold
  ];

  static const List<Color> categoryPalette = [
    Color(0xFF2E7D6B),
    Color(0xFF4C8BF5),
    Color(0xFFE0A800),
    Color(0xFFD9534F),
    Color(0xFF9B59B6),
    Color(0xFF16A085),
    Color(0xFFE67E22),
    Color(0xFF34495E),
    Color(0xFFC0392B),
    Color(0xFF2980B9),
    Color(0xFF8E44AD),
    Color(0xFF7F8C8D),
  ];

  static Color categoryColor(String category) {
    final idx = category.hashCode.abs() % categoryPalette.length;
    return categoryPalette[idx];
  }
}
