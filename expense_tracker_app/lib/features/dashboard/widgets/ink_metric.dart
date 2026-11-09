import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

/// Label + amount on the ink card, a third of the row wide.
class InkMetric extends StatelessWidget {
  final String label;
  final String value;
  const InkMetric({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final on = context.palette.onInk;
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: context.palette.onInkMuted),
          ),
          const SizedBox(height: AppSpacing.xxs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: text.moneyStyle(16, color: on)),
          ),
        ],
      ),
    );
  }
}
