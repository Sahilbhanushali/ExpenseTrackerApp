import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A category's icon in a tinted rounded square — the one visual identity a
/// category has across rows, pickers and charts.
class CategoryIcon extends StatelessWidget {
  final String category;
  final double size;

  /// Overrides the category's own colour (e.g. lending rows).
  final Color? color;
  final IconData? icon;

  /// Solid fill with a white glyph instead of a soft tint.
  final bool solid;

  const CategoryIcon({
    super.key,
    required this.category,
    this.size = AppSizes.iconBadge,
    this.color,
    this.icon,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = CategoryStyle.of(category);
    final c = color ?? style.color;
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = c.withValues(alpha: dark ? 0.22 : 0.12);
    // Icons need 3:1 against what's actually behind them; bright category
    // colours (orange, amber, cyan) fall short on their own tint.
    final glyph = solid
        ? bestOn(c)
        : ensureContrast(c, Color.alphaBlend(tint, p.surface), min: 3);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: solid ? c : tint,
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        child: Icon(icon ?? style.icon, size: size * 0.5, color: glyph),
      ),
    );
  }
}
