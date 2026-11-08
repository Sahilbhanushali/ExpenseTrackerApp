import 'package:flutter/material.dart';

/// Brand + semantic colour constants. Anything that differs between light
/// and dark mode lives in [AppPalette] (a ThemeExtension) instead — read it
/// with `context.palette`.
class AppColors {
  AppColors._();

  // Brand
  static const Color ink = Color(0xFF0E1A33); // midnight navy
  static const Color blue = Color(0xFF2F6BFF); // modern blue accent
  static const Color blueLight = Color(0xFF7AA2FF);

  /// Kept as the app-wide "primary" alias so existing call sites stay
  /// meaningful: it is the accent used for selection and focus.
  static const Color primary = blue;

  // Semantic — tuned to clear 4.5:1 on white for small bold text.
  static const Color income = Color(0xFF047857); // emerald
  static const Color expense = Color(0xFFD63B41); // coral red
  static const Color warning = Color(0xFFB45309); // amber
  static const Color savings = blue;
  static const Color debt = Color(0xFF7C3AED); // violet

  // Dark-mode counterparts (used via AppPalette).
  static const Color incomeDark = Color(0xFF34D399);
  static const Color expenseDark = Color(0xFFFF7B7F);
  static const Color warningDark = Color(0xFFFBBF24);
  static const Color debtDark = Color(0xFFB39DFF);

  /// Twelve saturated hues for custom categories that have no fixed style.
  /// Deep enough to carry white text/icons on a solid tile.
  static const List<Color> categoryPalette = [
    Color(0xFF7C5CFF), // violet
    Color(0xFF2F8CFF), // blue
    Color(0xFF14A86B), // green
    Color(0xFFFF7A1A), // orange
    Color(0xFFE5487D), // pink
    Color(0xFF0EA5B7), // cyan
    Color(0xFFDB8A00), // amber
    Color(0xFF5B6CFF), // indigo
    Color(0xFFE5484D), // red
    Color(0xFF0F9F8F), // teal
    Color(0xFFB04BD9), // purple
    Color(0xFF5C7A99), // slate
  ];

  static Color categoryColor(String category) =>
      kCategoryStyles[category]?.color ??
      categoryPalette[category.hashCode.abs() % categoryPalette.length];
}

/// Fixed icon + colour per built-in category, so "food" always looks like
/// food everywhere in the app (tiles, rows, charts, pickers).
class CategoryStyle {
  final IconData icon;
  final Color color;
  const CategoryStyle(this.icon, this.color);

  static CategoryStyle of(String category) =>
      kCategoryStyles[category] ??
      CategoryStyle(Icons.sell_outlined, AppColors.categoryColor(category));
}

const Map<String, CategoryStyle> kCategoryStyles = {
  'travel': CategoryStyle(Icons.directions_car_rounded, Color(0xFF2F8CFF)),
  'food': CategoryStyle(Icons.restaurant_rounded, Color(0xFFFF7A1A)),
  'groceries': CategoryStyle(Icons.shopping_bag_rounded, Color(0xFF7C5CFF)),
  'clothes': CategoryStyle(Icons.checkroom_rounded, Color(0xFFE5487D)),
  'rent': CategoryStyle(Icons.home_rounded, Color(0xFFDB8A00)),
  'bills': CategoryStyle(Icons.receipt_long_rounded, Color(0xFF0EA5B7)),
  'luxuries': CategoryStyle(Icons.diamond_rounded, Color(0xFFB04BD9)),
  'fitness': CategoryStyle(Icons.fitness_center_rounded, Color(0xFF14A86B)),
  'investments': CategoryStyle(Icons.trending_up_rounded, Color(0xFF5B6CFF)),
  'health': CategoryStyle(Icons.favorite_rounded, Color(0xFFE5484D)),
  'education': CategoryStyle(Icons.school_rounded, Color(0xFF0F9F8F)),
  'lending': CategoryStyle(Icons.handshake_rounded, Color(0xFFDB8A00)),
  'income': CategoryStyle(Icons.south_west_rounded, Color(0xFF14A86B)),
  'other': CategoryStyle(Icons.category_rounded, Color(0xFF5C7A99)),
};

/// Light/dark-aware surface and text colours.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// The high-contrast "ink" surface used by the nav bar and primary
  /// buttons, and the colour drawn on top of it.
  final Color inkSurface;
  final Color onInk;
  final Color income;
  final Color expense;
  final Color warning;
  final Color savings;
  final Color debt;

  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.inkSurface,
    required this.onInk,
    required this.income,
    required this.expense,
    required this.warning,
    required this.savings,
    required this.debt,
  });

  static const light = AppPalette(
    background: Color(0xFFF4F5F8),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEDEFF4),
    border: Color(0xFFE3E6EC),
    textPrimary: Color(0xFF0E1A33),
    textSecondary: Color(0xFF586174),
    textTertiary: Color(0xFF7D8699),
    inkSurface: AppColors.ink,
    onInk: Color(0xFFFFFFFF),
    income: AppColors.income,
    expense: AppColors.expense,
    warning: AppColors.warning,
    savings: AppColors.blue,
    debt: AppColors.debt,
  );

  static const dark = AppPalette(
    background: Color(0xFF0A0F1C),
    surface: Color(0xFF131A2A),
    surfaceAlt: Color(0xFF1C2537),
    border: Color(0xFF263149),
    textPrimary: Color(0xFFF2F4F8),
    textSecondary: Color(0xFFA6AFC0),
    textTertiary: Color(0xFF7A8499),
    inkSurface: Color(0xFFF2F4F8),
    onInk: AppColors.ink,
    income: AppColors.incomeDark,
    expense: AppColors.expenseDark,
    warning: AppColors.warningDark,
    savings: AppColors.blueLight,
    debt: AppColors.debtDark,
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      border: l(border, other.border),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      inkSurface: l(inkSurface, other.inkSurface),
      onInk: l(onInk, other.onInk),
      income: l(income, other.income),
      expense: l(expense, other.expense),
      warning: l(warning, other.warning),
      savings: l(savings, other.savings),
      debt: l(debt, other.debt),
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
