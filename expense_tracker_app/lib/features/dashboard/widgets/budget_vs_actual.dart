import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/widgets/budget_progress_bar.dart';
import '../../../core/widgets/category_icon.dart';

/// Per-category budget adherence — only categories that actually have a
/// budget set (via the budget planner).
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
    final text = Theme.of(context).textTheme;
    final p = context.palette;

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          Builder(
            builder: (context) {
              final e = entries[i];
              final spent = actuals[e.key] ?? 0;
              final status = budgetStatus(spent, e.value);
              final left = e.value - spent;
              return Row(
                children: [
                  CategoryIcon(category: e.key, size: 36),
                  const SizedBox(width: AppSpacing.md - 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.key,
                                style: text.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${formatMoney(spent, currency)} / ${formatMoney(e.value, currency)}',
                              style: text.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm - 2),
                        BudgetProgressBar(
                          spent: spent,
                          budget: e.value,
                          color: AppColors.categoryColor(e.key),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          left >= 0
                              ? '${formatMoney(left, currency)} left · ${status.label}'
                              : '${formatMoney(-left, currency)} over budget',
                          style: text.labelSmall?.copyWith(
                            color: status == BudgetStatus.ok
                                ? p.textTertiary
                                : status.color(p),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}
