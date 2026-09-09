import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/widgets/budget_progress_bar.dart';

/// Per-category budget adherence for the viewed month — only shows
/// categories that actually have a budget set (via the budget planner).
class BudgetVsActual extends StatelessWidget {
  /// Both category → paise.
  final Map<String, int> budgets;
  final Map<String, int> actuals;
  final String currency;

  const BudgetVsActual({
    super.key,
    required this.budgets,
    required this.actuals,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final entries = budgets.entries.toList()
      ..sort((a, b) => (actuals[b.key] ?? 0).compareTo(actuals[a.key] ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in entries) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(e.key, style: Theme.of(context).textTheme.bodyMedium),
              Text(
                '${formatMoney(actuals[e.key] ?? 0, currency)} / ${formatMoney(e.value, currency)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          BudgetProgressBar(spent: actuals[e.key] ?? 0, budget: e.value),
          if (e != entries.last) const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

/// Income vs. expense per month, oldest to newest — answers "am I trending
/// up or down" at a glance instead of only showing the current month.
