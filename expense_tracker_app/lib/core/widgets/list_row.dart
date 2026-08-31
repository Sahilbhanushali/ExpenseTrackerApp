import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'press_scale.dart';

/// A themed replacement for stock `ListTile`/`SwitchListTile` — an icon in a
/// soft circular backdrop, title/subtitle, and a flexible trailing widget,
/// with tap feedback via [PressScale] when [onTap] is set.
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
    final color = iconColor ?? Theme.of(context).colorScheme.primary;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: titleStyle ?? Theme.of(context).textTheme.bodyLarge,
                ),
                if (subtitle != null)
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
    return onTap == null ? row : PressScale(onTap: onTap, child: row);
  }
}
