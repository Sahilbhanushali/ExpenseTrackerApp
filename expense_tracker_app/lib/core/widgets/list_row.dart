import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A themed replacement for stock `ListTile`/`SwitchListTile`: icon in a
/// tinted rounded badge, title/subtitle, flexible trailing widget.
class ListRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final TextStyle? titleStyle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const ListRow({
    super.key,
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.titleStyle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final color = iconColor ?? p.textPrimary;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final badge = iconColor == null
        ? p.surfaceAlt
        : color.withValues(alpha: dark ? 0.22 : 0.12);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizes.minTouch),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Container(
              width: AppSizes.iconBadge,
              height: AppSizes.iconBadge,
              decoration: BoxDecoration(
                color: badge,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                icon,
                size: AppIconSize.md,
                // Bright accent colours fall below 3:1 on their own tint.
                color: ensureContrast(
                  color,
                  Color.alphaBlend(badge, p.surface),
                  min: 3,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md - 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style:
                        titleStyle ??
                        text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(subtitle!, style: text.bodySmall),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: row,
    );
  }
}

/// A trailing chevron for navigational rows.
class RowChevron extends StatelessWidget {
  const RowChevron({super.key});

  @override
  Widget build(BuildContext context) => Icon(
    Icons.chevron_right_rounded,
    color: context.palette.textTertiary,
    size: AppIconSize.lg,
  );
}
