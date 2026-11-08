import 'package:flutter/material.dart';

class AppSpacing {
  AppSpacing._();
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Horizontal page gutter.
  static const double page = 20;

  /// Bottom inset for tab screens so the last row scrolls clear of the
  /// floating nav bar.
  static const double navClearance = 112;
}

class AppRadius {
  AppRadius._();
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 28;
  static const double pill = 999;
}

class AppIconSize {
  AppIconSize._();
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 32;
}

/// Fixed control dimensions — deliberate design constraints, not layout
/// assumptions about the screen.
class AppSizes {
  AppSizes._();
  static const double buttonHeight = 48;
  static const double inputHeight = 52;
  static const double minTouch = 48;
  static const double iconBadge = 40;
  static const double navBarHeight = 64;
  static const double progressBar = 8;
}

class AppDurations {
  AppDurations._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 360);
  static const Duration counter = Duration(milliseconds: 600);
  static const Duration chart = Duration(milliseconds: 450);

  /// Honours the OS "remove animations" accessibility setting.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;
}

class AppShadows {
  AppShadows._();

  /// Barely-there lift for cards on light mode; dark mode relies on borders.
  static List<BoxShadow> card(Brightness b) => b == Brightness.dark
      ? const []
      : const [
          BoxShadow(
            color: Color(0x0A0E1A33),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ];

  static const List<BoxShadow> floating = [
    BoxShadow(color: Color(0x2E0E1A33), blurRadius: 24, offset: Offset(0, 10)),
  ];
}
