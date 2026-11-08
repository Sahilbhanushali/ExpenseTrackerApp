import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'press_scale.dart';

export 'state_views.dart';

/// The app's one card surface: solid fill, hairline border, a whisper of
/// shadow in light mode. Pass [onTap] for press feedback.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.color,
    this.radius = AppRadius.lg,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppShadows.card(Theme.of(context).brightness),
      ),
      child: child,
    );
    return onTap == null
        ? card
        : PressScale(onTap: onTap, scaleTo: 0.98, child: card);
  }
}
