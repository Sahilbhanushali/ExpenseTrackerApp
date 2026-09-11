import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_transitions.dart';
import '../../../core/widgets/press_scale.dart';
import '../../../core/widgets/transaction_tile.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../expenses/expenses_controller.dart';
import '../../goals/goals_controller.dart';
import '../../goals/goals_screen.dart';
import '../../settings/settings_controller.dart';
import 'budget_vs_actual.dart';
import 'category_chart.dart';
import 'hero_card.dart';
import 'stat_card.dart';
import 'trend_chart.dart';

/// Everything that describes one month: spend vs. budget, the category
/// split, and recent activity. Watches expenses/settings/goals itself, so an
/// account edit elsewhere doesn't rebuild these charts.
class MonthSummarySection extends StatelessWidget {
  /// Totals for a past month, loaded on demand. Null means "show the live
  /// current-month figures from the controller".
  final MonthTotal? viewedTotals;
  final Map<String, int> viewedCategoryTotals;
  final List<MonthPoint> trend;
  final bool isCurrentMonth;

  const MonthSummarySection({
    super.key,
    required this.viewedTotals,
    required this.viewedCategoryTotals,
    required this.trend,
    required this.isCurrentMonth,
  });

  @override
  Widget build(BuildContext context) {
    final expenses = context.watch<ExpensesController>();
    final settings = context.watch<SettingsController>();
    final config = settings.config;
    final totalSaved = context.select<GoalsController, int>(
      (g) => g.goals.fold<int>(0, (s, e) => s + e.saved),
    );

    final totals = isCurrentMonth
        ? expenses.monthTotal
        : (viewedTotals ?? const MonthTotal());
    final categoryTotals = isCurrentMonth
        ? expenses.categoryTotals
        : viewedCategoryTotals;
    final budget = settings.config.monthlyBudgetPaise;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeroCard(
          spent: totals.expense,
          budget: budget,
          remaining: budget - totals.expense,
          currency: config.currency,
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Income this month',
                value: totals.income,
                currency: config.currency,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: PressScale(
                onTap: () =>
                    Navigator.of(context)
                        .push(FadeSlideRoute(page: const GoalsScreen())),
                child: StatCard(
                  label: 'Saved toward goals',
                  value: totalSaved,
                  currency: config.currency,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionTitle('Spending by category'),
        const SizedBox(height: AppSpacing.md),
        if (categoryTotals.isEmpty)
          AppCard(
            child: Text(
              isCurrentMonth
                  ? 'No spending logged this month yet.'
                  : 'No spending logged that month.',
            ),
          )
        else
          AppCard(
            child: CategoryChart(
              totals: categoryTotals,
              currency: config.currency,
            ),
          ),
        if (config.budgets.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _SectionTitle('Budget vs actual'),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: BudgetVsActual(
              budgets: config.budgets,
              actuals: categoryTotals,
              currency: config.currency,
            ),
          ),
        ],
        if (trend.any((p) => p.income > 0 || p.expense > 0)) ...[
          const SizedBox(height: AppSpacing.lg),
          _SectionTitle('Last 6 months'),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: TrendChart(points: trend, currency: config.currency),
          ),
        ],
        if (expenses.recent.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _SectionTitle('Recent transactions'),
          const SizedBox(height: AppSpacing.md),
          for (final txn in expenses.recent.take(5))
            TransactionTile(txn: txn, currency: config.currency),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleMedium);
}
