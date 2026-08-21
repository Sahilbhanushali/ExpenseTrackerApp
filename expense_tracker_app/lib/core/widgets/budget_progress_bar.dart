import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Visual port of bot.py's progress_bar() text bar.
class BudgetProgressBar extends StatelessWidget {
  final double spent;
  final double budget;

  const BudgetProgressBar({super.key, required this.spent, required this.budget});

  @override
  Widget build(BuildContext context) {
    if (budget <= 0) {
      return Text('No budget set', style: Theme.of(context).textTheme.bodySmall);
    }
    final frac = (spent / budget).clamp(0.0, 1.0);
    final over = spent > budget;
    final color = over ? AppColors.expense : (frac > 0.8 ? AppColors.warning : AppColors.primary);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: LinearProgressIndicator(
        value: frac,
        minHeight: 10,
        backgroundColor: color.withValues(alpha: 0.15),
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}
