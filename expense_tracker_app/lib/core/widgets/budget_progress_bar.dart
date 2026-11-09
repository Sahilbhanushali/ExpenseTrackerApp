import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// How close a budget is to its limit — drives colour *and* a text label, so
/// the state never relies on colour alone.
enum BudgetStatus { ok, warning, over }

BudgetStatus budgetStatus(int spent, int budget) {
  if (budget <= 0) return BudgetStatus.ok;
  if (spent > budget) return BudgetStatus.over;
  if (spent / budget > 0.8) return BudgetStatus.warning;
  return BudgetStatus.ok;
}

extension BudgetStatusStyle on BudgetStatus {
  Color color(AppPalette p) => switch (this) {
    BudgetStatus.ok => p.savings,
    BudgetStatus.warning => p.warning,
    BudgetStatus.over => p.expense,
  };

  /// The same status drawn on the dark ink surface.
  Color inkColor(AppPalette p) => switch (this) {
    BudgetStatus.ok => p.inkAccent,
    BudgetStatus.warning => p.inkWarning,
    BudgetStatus.over => p.inkExpense,
  };
  String get label => switch (this) {
    BudgetStatus.ok => 'On track',
    BudgetStatus.warning => 'Near limit',
    BudgetStatus.over => 'Over budget',
  };
}

/// Animated budget bar. Grows from empty on first build and eases between
/// values afterwards.
class BudgetProgressBar extends StatelessWidget {
  /// Both in paise.
  final int spent;
  final int budget;
  final double height;

  /// Overrides the status colour (e.g. a category's own colour).
  final Color? color;

  const BudgetProgressBar({
    super.key,
    required this.spent,
    required this.budget,
    this.height = AppSizes.progressBar,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (budget <= 0) {
      return Text(
        'No budget set',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final p = context.palette;
    final frac = (spent / budget).clamp(0.0, 1.0);
    final status = budgetStatus(spent, budget);
    final c = status == BudgetStatus.ok
        ? (color ?? status.color(p))
        : status.color(p);

    return Semantics(
      value: '${(spent / budget * 100).round()} percent used, ${status.label}',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: frac),
        duration: AppDurations.of(context, AppDurations.slow),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: v,
            minHeight: height,
            backgroundColor: p.surfaceAlt,
            valueColor: AlwaysStoppedAnimation(c),
          ),
        ),
      ),
    );
  }
}
