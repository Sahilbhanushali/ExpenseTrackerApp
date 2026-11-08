import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// Tabular figures keep amounts from jittering as animated totals tick.
const List<FontFeature> kTabularFigures = [FontFeature.tabularFigures()];

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light, AppPalette.light);
  static ThemeData dark() => _build(Brightness.dark, AppPalette.dark);

  static ThemeData _build(Brightness brightness, AppPalette p) {
    final isDark = brightness == Brightness.dark;
    final accent = isDark ? AppColors.blueLight : AppColors.blue;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.blue,
          brightness: brightness,
        ).copyWith(
          primary: accent,
          onPrimary: isDark ? AppColors.ink : Colors.white,
          primaryContainer: accent.withValues(alpha: 0.14),
          onPrimaryContainer: p.textPrimary,
          secondary: p.inkSurface,
          onSecondary: p.onInk,
          secondaryContainer: p.surfaceAlt,
          onSecondaryContainer: p.textPrimary,
          error: p.expense,
          surface: p.surface,
          onSurface: p.textPrimary,
          onSurfaceVariant: p.textSecondary,
          surfaceContainerLowest: p.surface,
          surfaceContainerLow: p.surface,
          surfaceContainer: p.surface,
          surfaceContainerHigh: p.surfaceAlt,
          surfaceContainerHighest: p.surfaceAlt,
          outline: p.textTertiary,
          outlineVariant: p.border,
          surfaceTint: Colors.transparent,
        );

    final base = ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      useMaterial3: true,
    );
    final text = _textTheme(base.textTheme, p);
    final radiusMd = BorderRadius.circular(AppRadius.md);

    return base.copyWith(
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      textTheme: text,
      dividerColor: p.border,
      extensions: [p],
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.textPrimary, size: AppIconSize.lg),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: p.border),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: AppSpacing.page,
        titleTextStyle: text.titleLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceAlt,
        hintStyle: text.bodyMedium?.copyWith(color: p.textTertiary),
        labelStyle: text.bodyMedium?.copyWith(color: p.textSecondary),
        floatingLabelStyle: text.bodyMedium?.copyWith(color: accent),
        prefixIconColor: p.textSecondary,
        suffixIconColor: p.textSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: p.surfaceAlt),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: p.expense),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: p.expense, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _primaryButton(p, text),
      ),
      filledButtonTheme: FilledButtonThemeData(style: _primaryButton(p, text)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          minimumSize: const Size(64, AppSizes.buttonHeight),
          side: BorderSide(color: p.border),
          textStyle: text.labelLarge,
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: text.labelLarge,
          minimumSize: const Size(48, AppSizes.minTouch),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.inkSurface,
        foregroundColor: p.onInk,
        elevation: 2,
        highlightElevation: 4,
        shape: const StadiumBorder(),
        extendedTextStyle: text.labelLarge,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(text.labelMedium),
          visualDensity: VisualDensity.compact,
          side: WidgetStatePropertyAll(BorderSide(color: p.border)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.inkSurface : p.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.onInk : p.textPrimary,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.onInk : p.textPrimary,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.inkSurface,
        checkmarkColor: p.onInk,
        side: BorderSide(color: p.border),
        shape: const StadiumBorder(),
        labelStyle: text.labelMedium?.copyWith(color: p.textPrimary),
        secondaryLabelStyle: text.labelMedium?.copyWith(color: p.onInk),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : null,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.transparent : null,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: p.surfaceAlt,
        circularTrackColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surface,
        dragHandleColor: p.border,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.inkSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: p.onInk),
        actionTextColor: isDark ? AppColors.blue : AppColors.blueLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: p.border),
        ),
        textStyle: text.bodyMedium,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.inkSurface,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        textStyle: text.labelMedium?.copyWith(color: p.onInk),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ButtonStyle _primaryButton(AppPalette p, TextTheme text) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? p.surfaceAlt : p.inkSurface,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? p.textTertiary : p.onInk,
      ),
      minimumSize: const WidgetStatePropertyAll(
        Size(64, AppSizes.buttonHeight),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      ),
      textStyle: WidgetStatePropertyAll(text.labelLarge),
      elevation: const WidgetStatePropertyAll(0),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
    );
  }

  /// Plus Jakarta Sans for headings and money, Inter for running text.
  static TextTheme _textTheme(TextTheme base, AppPalette p) {
    final body = GoogleFonts.interTextTheme(base);
    TextStyle display(double size, FontWeight w, double tracking) =>
        GoogleFonts.plusJakartaSans(
          fontSize: size,
          fontWeight: w,
          letterSpacing: tracking,
          color: p.textPrimary,
          height: 1.15,
          fontFeatures: kTabularFigures,
        );
    return body.copyWith(
      displaySmall: display(34, FontWeight.w800, -1.0),
      headlineMedium: display(28, FontWeight.w800, -0.8),
      headlineSmall: display(24, FontWeight.w700, -0.5),
      titleLarge: display(20, FontWeight.w700, -0.3),
      titleMedium: display(16, FontWeight.w700, -0.1),
      titleSmall: body.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: p.textPrimary,
      ),
      bodyLarge: body.bodyLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: p.textPrimary,
      ),
      bodyMedium: body.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: p.textPrimary,
      ),
      bodySmall: body.bodySmall?.copyWith(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        color: p.textSecondary,
      ),
      labelLarge: body.labelLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      labelMedium: body.labelMedium?.copyWith(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: p.textSecondary,
        letterSpacing: 0,
      ),
      labelSmall: body.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: p.textTertiary,
        letterSpacing: 0.2,
      ),
    );
  }
}

/// Text style for a money figure at a given size — derived from the theme's
/// display face (Plus Jakarta Sans) with tabular figures.
extension MoneyText on TextTheme {
  TextStyle moneyStyle(double size, {Color? color, FontWeight? weight}) =>
      (headlineSmall ?? const TextStyle()).copyWith(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w700,
        letterSpacing: size >= 24 ? -0.8 : -0.2,
        color: color,
        height: 1.1,
        fontFeatures: kTabularFigures,
      );
}
