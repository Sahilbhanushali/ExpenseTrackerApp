import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/widgets/animated_money_text.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/budget_progress_bar.dart';
import '../../../core/widgets/page_transitions.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/transaction_tile.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../expenses/expenses_controller.dart';
import '../../goals/goals_controller.dart';
import '../../goals/goals_screen.dart';
import '../../settings/budget_planner_screen.dart';
import '../../settings/settings_controller.dart';
import 'budget_vs_actual.dart';
import 'category_tiles.dart';
import 'trend_chart.dart';
import 'upcoming_bills.dart';

/// Everything that describes one month: spend vs. budget, the category
/// split, trend and recent activity. Watches expenses/settings/goals itself,
/// so an account edit elsewhere doesn't rebuild these charts.
class MonthSummarySection extends StatelessWidget {
  /// Totals for a past month, loaded on demand. Null means "show the live
  /// current-month figures from the controller".
  final MonthTotal? viewedTotals;
  final Map<String, int> viewedCategoryTotals;
  final List<MonthPoint> trend;
  final bool trendLoaded;
  final bool isCurrentMonth;
  final DateTime viewedMonth;
  final VoidCallback onSeeAllTransactions;
  final VoidCallback onOpenReports;

  const MonthSummarySection({
    super.key,
    required this.viewedTotals,
    required this.viewedCategoryTotals,
    required this.trend,
    required this.trendLoaded,
    required this.isCurrentMonth,
    required this.viewedMonth,
    required this.onSeeAllTransactions,
    required this.onOpenReports,
  });

  @override
  Widget build(BuildContext context) {
    final expenses = context.watch<ExpensesController>();
    final config = context.watch<SettingsController>().config;
    final totalSaved = context.select<GoalsController, int>(
      (g) => g.goals.fold<int>(0, (s, e) => s + e.saved),
    );
    final hasGoals = context.select<GoalsController, bool>(
      (g) => g.goals.isNotEmpty,
    );
    final currency = config.currency;

    final totals = isCurrentMonth
        ? expenses.monthTotal
        : (viewedTotals ?? const MonthTotal());
    final categoryTotals = isCurrentMonth
        ? expenses.categoryTotals
        : viewedCategoryTotals;
    // `recent` is oldest→newest; the dashboard shows the newest first.
    final recent = expenses.recent.reversed.take(5).toList();

    const gap = SizedBox(height: AppSpacing.lg);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SpendCard(
          totals: totals,
          budget: config.monthlyBudgetPaise,
          currency: currency,
          viewedMonth: viewedMonth,
          isCurrentMonth: isCurrentMonth,
        ),
        gap,
        SectionHeader(
          'Spending by category',
          action: categoryTotals.isEmpty ? null : 'Details',
          onAction: onOpenReports,
        ),
        if (categoryTotals.isEmpty)
          AppCard(
            child: EmptyState(
              icon: Icons.donut_large_rounded,
              message: isCurrentMonth
                  ? 'No spending logged this month yet.'
                  : 'No spending logged that month.',
            ),
          )
        else
          CategoryTiles(totals: categoryTotals, currency: currency),
        if (config.budgets.isNotEmpty) ...[
          gap,
          SectionHeader(
            'Budgets',
            action: 'Edit',
            onAction: () =>
                Navigator.of(context)
                    .push(FadeSlideRoute(page: const BudgetPlannerScreen())),
          ),
          AppCard(
            child: BudgetVsActual(
              budgets: config.budgets,
              actuals: categoryTotals,
              currency: currency,
            ),
          ),
        ],
        if (isCurrentMonth) const UpcomingBills(),
        if (trendLoaded && trend.any((p) => p.income > 0 || p.expense > 0)) ...[
          gap,
          const SectionHeader('Income vs expenses'),
          AppCard(
            child: TrendChart(points: trend, currency: currency),
          ),
        ],
        if (hasGoals) ...[
          gap,
          AppCard(
            onTap: () =>
                Navigator.of(context)
                    .push(FadeSlideRoute(page: const GoalsScreen())),
            child: Row(
              children: [
                Icon(Icons.flag_rounded, color: context.palette.savings),
                const SizedBox(width: AppSpacing.md - 4),
                Expanded(
                  child: Text(
                    'Saved toward goals',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                Text(
                  formatMoney(totalSaved, currency),
                  style: Theme.of(context).textTheme.moneyStyle(16),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.palette.textTertiary,
                ),
              ],
            ),
          ),
        ],
        gap,
        SectionHeader(
          'Recent transactions',
          action: recent.isEmpty ? null : 'See all',
          onAction: onSeeAllTransactions,
        ),
        if (recent.isEmpty)
          const AppCard(
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No transactions yet',
              message: 'Tap + to log your first expense or income.',
            ),
          )
        else
          TransactionGroup(
            children: [
              for (final txn in recent)
                TransactionTile(txn: txn, currency: currency, showDate: true),
            ],
          ),
      ],
    );
  }
}

/// The month's focal card: spent vs budget on the ink surface, then
/// income / saved / savings rate underneath.
class _SpendCard extends StatelessWidget {
  final MonthTotal totals;
  final int budget;
  final String currency;
  final DateTime viewedMonth;
  final bool isCurrentMonth;

  const _SpendCard({
    required this.totals,
    required this.budget,
    required this.currency,
    required this.viewedMonth,
    required this.isCurrentMonth,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final on = p.onInk;
    final onMuted = on.withValues(alpha: 0.68);
    final spent = totals.expense;
    final remaining = budget - spent;
    final net = totals.income - spent;
    final rate = totals.income > 0 ? (net / totals.income * 100).round() : null;
    final status = budgetStatus(spent, budget);

    String? allowance;
    if (isCurrentMonth && budget > 0 && remaining > 0) {
      final now = DateTime.now();
      final lastDay = DateTime(now.year, now.month + 1, 0).day;
      final daysLeft = lastDay - now.day + 1;
      allowance =
          '${formatMoney(remaining ~/ daysLeft, currency)}/day for $daysLeft day${daysLeft == 1 ? '' : 's'}';
    }

    return Container(
      decoration: BoxDecoration(
        color: p.inkSurface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg - 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isCurrentMonth ? 'Spent this month' : 'Spent that month',
                  style: text.labelMedium?.copyWith(color: onMuted),
                ),
              ),
              if (budget > 0)
                _StatusPill(label: status.label, color: status.color(p)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMoneyText(
              amountPaise: spent,
              currency: currency,
              style: text.headlineMedium?.copyWith(color: on),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (budget > 0) ...[
            _InkProgress(spent: spent, budget: budget),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'of ${formatMoney(budget, currency)}',
                    style: text.bodySmall?.copyWith(color: onMuted),
                  ),
                ),
                Text(
                  remaining >= 0
                      ? '${formatMoney(remaining, currency)} left'
                      : '${formatMoney(remaining.abs(), currency)} over',
                  style: text.labelMedium?.copyWith(color: on),
                ),
              ],
            ),
            if (allowance != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(allowance, style: text.bodySmall?.copyWith(color: onMuted)),
            ],
          ] else
            Text(
              'Set a monthly budget to track your limit.',
              style: text.bodySmall?.copyWith(color: onMuted),
            ),
          const SizedBox(height: AppSpacing.md),
          Divider(color: on.withValues(alpha: 0.14)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _InkMetric(
                label: 'Income',
                value: formatMoneyCompact(totals.income, currency),
              ),
              _InkMetric(
                label: net >= 0 ? 'Saved' : 'Overspent',
                value: formatMoneyCompact(net.abs(), currency),
              ),
              _InkMetric(
                label: 'Savings rate',
                value: rate == null ? '—' : '$rate%',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InkProgress extends StatelessWidget {
  final int spent;
  final int budget;
  const _InkProgress({required this.spent, required this.budget});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final frac = (spent / budget).clamp(0.0, 1.0);
    final status = budgetStatus(spent, budget);
    final fill = status == BudgetStatus.ok ? p.onInk : status.color(p);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: frac),
      duration: AppDurations.of(context, AppDurations.slow),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: LinearProgressIndicator(
          value: v,
          minHeight: AppSizes.progressBar,
          backgroundColor: p.onInk.withValues(alpha: 0.16),
          valueColor: AlwaysStoppedAnimation(fill),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs + 1,
      ),
      decoration: BoxDecoration(
        color: p.onInk.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs + 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: p.onInk),
          ),
        ],
      ),
    );
  }
}

class _InkMetric extends StatelessWidget {
  final String label;
  final String value;
  const _InkMetric({required this.label, required this.value});

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
            style: text.bodySmall?.copyWith(color: on.withValues(alpha: 0.68)),
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
