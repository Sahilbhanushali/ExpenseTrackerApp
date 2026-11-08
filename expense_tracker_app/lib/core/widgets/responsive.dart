import 'package:flutter/widgets.dart';

import '../theme/app_spacing.dart';

/// Content never grows wider than this — on tablets and landscape the page
/// centres instead of stretching cards edge to edge.
const double kMaxContentWidth = 720;

/// Horizontal padding that keeps content at most [kMaxContentWidth] wide,
/// and at least the standard page gutter.
double pageGutter(double width) {
  final extra = (width - kMaxContentWidth) / 2;
  return extra > AppSpacing.page ? extra : AppSpacing.page;
}

/// Builds [builder] with the page gutter for the current width.
class ResponsivePage extends StatelessWidget {
  final Widget Function(BuildContext context, double gutter) builder;
  const ResponsivePage({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => builder(context, pageGutter(c.maxWidth)),
    );
  }
}
