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

  // Amount colours are read as small bold text on both a near-white and a
  // near-black background, so they are the one place the neon palette had
  // to give way: spring green and pure yellow sit at roughly 1.2:1 against
  // white, which is invisible rather than vibrant. Same hues, deepened to
  // clear 4.5:1 on light and stay legible on dark. The colour energy lives
  // in the aurora, the hero gradient and the category chips instead.
  static const Color income = Color(0xFF00814F);
  static const Color expense = Color(0xFFC2185B);
  static const Color warning = Color(0xFFB26A00);

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
  // Near-opaque. At 0xCC the aurora bled through every card and tinted the
  // text behind it; "glass" is only worth having while it stays readable.
  static const Color glassLight = Color(0xFAFFFFFF);
  static const Color glassDark = Color(0xF01A1A1A);
  static const Color glassBorderLight = Color(0x40000000);
  static const Color glassBorderDark = Color(0x26FFFFFF);

  /// Backdrop only — it must never compete with content. At 0x66 the blobs
  /// showed straight through the cards and, on the transaction list, sat
  /// directly behind the text. Kept in the brand's violet/pink family with
  /// two cooler accents, at an alpha you notice only when you look for it.
  static const List<Color> auroraBlobsLight = [
    Color(0x1FFF3D9A), // pink
    Color(0x1F8A2BE2), // electric purple
    Color(0x1A00BFA5), // teal
    Color(0x1A6C8CFF), // periwinkle
  ];
  static const List<Color> auroraBlobsDark = [
    Color(0x2EFF3D9A),
    Color(0x2E8A2BE2),
    Color(0x2600BFA5),
    Color(0x266C8CFF),
  ];

  /// Twelve hues spaced around the wheel, deep enough to read as a small
  /// icon on white and to carry white percentage labels inside a pie slice.
  /// The previous set was neon — cyan, chartreuse and electric yellow are
  /// invisible against a light background however vivid they look on paper.
  static const List<Color> categoryPalette = [
    Color(0xFFDC2626), // red
    Color(0xFFEA580C), // orange
    Color(0xFFB45309), // amber
    Color(0xFF65A30D), // lime
    Color(0xFF059669), // emerald
    Color(0xFF0D9488), // teal
    Color(0xFF0891B2), // cyan
    Color(0xFF2563EB), // blue
    Color(0xFF6366F1), // indigo
    Color(0xFF7C3AED), // violet
    Color(0xFFC026D3), // fuchsia
    Color(0xFFE11D74), // rose
  ];

  static Color categoryColor(String category) {
    final idx = category.hashCode.abs() % categoryPalette.length;
    return categoryPalette[idx];
  }
}
