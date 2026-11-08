import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Pill-shaped single-choice chip used for filters and range presets.
class AppChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  /// Shows a trailing clear "x" when selected.
  final VoidCallback? onClear;

  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = selected ? p.onInk : p.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: AppDurations.of(context, AppDurations.fast),
            constraints: const BoxConstraints(minHeight: 36),
            padding: EdgeInsets.only(
              left: AppSpacing.md - 2,
              right: selected && onClear != null
                  ? AppSpacing.xs
                  : AppSpacing.md - 2,
            ),
            decoration: BoxDecoration(
              color: selected ? p.inkSurface : p.surface,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: selected ? p.inkSurface : p.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: AppIconSize.sm, color: fg),
                  const SizedBox(width: AppSpacing.xs + 2),
                ],
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: fg),
                ),
                if (selected && onClear != null)
                  IconButton(
                    onPressed: onClear,
                    tooltip: 'Clear',
                    visualDensity: VisualDensity.compact,
                    iconSize: AppIconSize.sm,
                    color: fg,
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontally scrolling row of chips with consistent gutters.
class ChipRow extends StatelessWidget {
  final List<Widget> children;
  const ChipRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            children[i],
          ],
        ],
      ),
    );
  }
}
