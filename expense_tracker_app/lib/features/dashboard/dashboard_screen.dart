import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/animated_money_text.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/budget_progress_bar.dart';
import '../../core/widgets/page_transitions.dart';
import '../../core/widgets/press_scale.dart';
import '../../data/models/account.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/transaction_repository.dart';
import '../accounts/accounts_controller.dart';
import '../accounts/accounts_screen.dart';
import '../expenses/expenses_controller.dart';
import '../goals/goals_controller.dart';
import '../goals/goals_screen.dart';
import '../lending/lending_controller.dart';
import '../lending/lending_screen.dart';
import '../settings/settings_controller.dart';

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late DateTime _viewedMonth;
  MonthTotal? _viewedTotals;
  Map<String, double> _viewedCategoryTotals = {};
  List<MonthPoint> _trend = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _viewedMonth = DateTime(now.year, now.month);
    _loadTrend();
  }

  Future<void> _loadTrend() async {
    final trend = await context.read<ExpensesController>().monthlyTrend(6);
    if (mounted) setState(() => _trend = trend);
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _viewedMonth.year == now.year && _viewedMonth.month == now.month;
  }

  String get _monthKey =>
      '${_viewedMonth.year.toString().padLeft(4, '0')}-${_viewedMonth.month.toString().padLeft(2, '0')}';

  Future<void> _loadViewedMonth() async {
    if (_isCurrentMonth) {
      setState(() {
        _viewedTotals = null;
        _viewedCategoryTotals = {};
      });
      return;
    }
    final expenses = context.read<ExpensesController>();
    final totals = await expenses.monthTotalFor(_monthKey);
    final cats = await expenses.categoryTotalsFor(_monthKey);
    if (!mounted) return;
    setState(() {
      _viewedTotals = totals;
      _viewedCategoryTotals = cats;
    });
  }

  Future<void> _pickMonth() async {
    var year = _viewedMonth.year;
    var month = _viewedMonth.month;

    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Jump to month'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setDialogState(() => year -= 1),
                  ),
                  Text('$year', style: Theme.of(context).textTheme.titleLarge),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setDialogState(() => year += 1),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                alignment: WrapAlignment.center,
                children: List.generate(12, (i) {
                  final m = i + 1;
                  final selected = m == month;
                  return ChoiceChip(
                    label: Text(_monthNames[i].substring(0, 3)),
                    selected: selected,
                    onSelected: (_) => setDialogState(() => month = m),
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                final now = DateTime.now();
                Navigator.pop(context, DateTime(now.year, now.month));
              },
              child: const Text('This month'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, DateTime(year, month)),
              child: const Text('Go'),
            ),
          ],
        ),
      ),
    );

    if (picked == null) return;
    setState(() => _viewedMonth = DateTime(picked.year, picked.month));
    _loadViewedMonth();
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final expenses = context.watch<ExpensesController>();
    final settings = context.watch<SettingsController>();
    final goals = context.watch<GoalsController>();
    final accounts = context.watch<AccountsController>();
    final lending = context.watch<LendingController>();
    final config = settings.config;

    final cashBalance = accounts.totalFor(AccountType.cash);
    final investments = accounts.totalFor(AccountType.investment);
    final emergencyFund = accounts.totalFor(AccountType.emergencyFund);
    final owedToYou = lending.outstanding
        .where((t) => t.type == TxnType.lent)
        .fold<double>(0, (s, t) => s + t.amount);
    final youOwe = lending.outstanding
        .where((t) => t.type == TxnType.borrowed)
        .fold<double>(0, (s, t) => s + t.amount);
    final netWorth =
        cashBalance + investments + emergencyFund + owedToYou - youOwe;

    final totals = _isCurrentMonth
        ? expenses.monthTotal
        : (_viewedTotals ?? const MonthTotal());
    final categoryTotals = _isCurrentMonth
        ? expenses.categoryTotals
        : _viewedCategoryTotals;
    final budget = settings.effectiveBudget(totals.income);
    final remaining = budget - totals.expense;
    final monthLabel =
        '${_monthNames[_viewedMonth.month - 1]} ${_viewedMonth.year}';
    final totalSaved = goals.goals.fold<double>(0, (s, g) => s + g.saved);
    final now = DateTime.now();
    final todayLabel =
        '${_weekdayNames[now.weekday - 1]}, ${now.day} ${_monthNames[now.month - 1]} ${now.year}';

    return RefreshIndicator(
      onRefresh: () async {
        await expenses.refresh();
        await _loadViewedMonth();
        await _loadTrend();
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          MediaQuery.of(context).padding.top + AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          Text(_greeting(), style: Theme.of(context).textTheme.bodyMedium),
          Text('Spendo', style: Theme.of(context).textTheme.headlineSmall),
          Text(todayLabel, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.lg),
          _NetWorthCard(
            netWorth: netWorth,
            cashBalance: cashBalance,
            investments: investments,
            emergencyFund: emergencyFund,
            owedToYou: owedToYou,
            youOwe: youOwe,
            currency: config.currency,
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: PressScale(
              onTap: _pickMonth,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_month_outlined, size: 18),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      monthLabel,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(Icons.expand_more, size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _HeroCard(
            spent: totals.expense,
            budget: budget,
            remaining: remaining,
            currency: config.currency,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _StatCard(
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
                  child: _StatCard(
                    label: 'Saved toward goals',
                    value: totalSaved,
                    currency: config.currency,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Spending by category',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          if (categoryTotals.isEmpty)
            AppCard(
              child: Text(
                _isCurrentMonth
                    ? 'No spending logged this month yet.'
                    : 'No spending logged that month.',
              ),
            )
          else
            AppCard(
              child: _CategoryChart(
                totals: categoryTotals,
                currency: config.currency,
              ),
            ),
          if (config.budgets.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Budget vs actual',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: _BudgetVsActual(
                budgets: config.budgets,
                actuals: categoryTotals,
                currency: config.currency,
              ),
            ),
          ],
          if (_trend.any((p) => p.income > 0 || p.expense > 0)) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Last 6 months',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: _TrendChart(points: _trend, currency: config.currency),
            ),
          ],
          if (expenses.recent.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Recent transactions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            ...expenses.recent
                .take(5)
                .map(
                  (txn) =>
                      _TransactionTile(txn: txn, currency: config.currency),
                ),
          ],
        ],
      ),
    );
  }
}

/// The single number that answers "what am I actually worth right now" —
/// account balances plus what's owed to you, minus what you owe. Tapping a
/// breakdown item jumps to the screen that explains it.
class _NetWorthCard extends StatelessWidget {
  final double netWorth;
  final double cashBalance;
  final double investments;
  final double emergencyFund;
  final double owedToYou;
  final double youOwe;
  final String currency;

  const _NetWorthCard({
    required this.netWorth,
    required this.cashBalance,
    required this.investments,
    required this.emergencyFund,
    required this.owedToYou,
    required this.youOwe,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Net worth', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xs),
          AnimatedMoneyText(
            amount: netWorth,
            currency: currency,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: PressScale(
                  onTap: () =>
                      Navigator.of(context)
                          .push(FadeSlideRoute(page: const AccountsScreen())),
                  child: _NetWorthBreakdownItem(
                    label: 'Cash & bank',
                    value: cashBalance,
                    currency: currency,
                  ),
                ),
              ),
              Expanded(
                child: PressScale(
                  onTap: () =>
                      Navigator.of(context)
                          .push(FadeSlideRoute(page: const AccountsScreen())),
                  child: _NetWorthBreakdownItem(
                    label: 'Investments',
                    value: investments,
                    currency: currency,
                  ),
                ),
              ),
              Expanded(
                child: PressScale(
                  onTap: () =>
                      Navigator.of(context)
                          .push(FadeSlideRoute(page: const AccountsScreen())),
                  child: _NetWorthBreakdownItem(
                    label: 'Emergency fund',
                    value: emergencyFund,
                    currency: currency,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: PressScale(
                  onTap: () =>
                      Navigator.of(context)
                          .push(FadeSlideRoute(page: const LendingScreen())),
                  child: _NetWorthBreakdownItem(
                    label: 'Owed to you',
                    value: owedToYou,
                    currency: currency,
                    color: AppColors.income,
                  ),
                ),
              ),
              Expanded(
                child: PressScale(
                  onTap: () =>
                      Navigator.of(context)
                          .push(FadeSlideRoute(page: const LendingScreen())),
                  child: _NetWorthBreakdownItem(
                    label: 'You owe',
                    value: youOwe,
                    currency: currency,
                    color: youOwe > 0 ? AppColors.expense : null,
                  ),
                ),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }
}

class _NetWorthBreakdownItem extends StatelessWidget {
  final String label;
  final double value;
  final String currency;
  final Color? color;

  const _NetWorthBreakdownItem({
    required this.label,
    required this.value,
    required this.currency,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          formatMoney(value, currency),
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final double spent;
  final double budget;
  final double remaining;
  final String currency;

  const _HeroCard({
    required this.spent,
    required this.budget,
    required this.remaining,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl), // bigger padding
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadius.xl), // larger radius
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.4),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Spent this month',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AnimatedMoneyText(
            amount: spent,
            currency: currency,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48, // chunkier
              fontWeight: FontWeight.w900,
              letterSpacing: -1.5,
            ),
          ).animate().fadeIn().scaleXY(
            begin: 0.9,
            end: 1.0,
            duration: 300.ms,
            curve: Curves.easeOutBack,
          ),
          const SizedBox(height: AppSpacing.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child:
                LinearProgressIndicator(
                  value: budget > 0 ? (spent / budget).clamp(0.0, 1.0) : 0,
                  minHeight: 12,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ).animate().slideX(
                  begin: -1,
                  duration: 500.ms,
                  curve: Curves.easeOutCubic,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Budget ${formatMoney(budget, currency)}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                remaining >= 0
                    ? '${formatMoney(remaining, currency)} left'
                    : '${formatMoney(remaining.abs(), currency)} over',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final double? value;
  final String currency;
  const _StatCard({
    required this.label,
    required this.value,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              value == null
                  ? Text('—', style: Theme.of(context).textTheme.titleMedium)
                  : AnimatedMoneyText(
                      amount: value!,
                      currency: currency,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryDark,
                      ),
                    ),
            ],
          ),
        )
        .animate()
        .slideY(begin: 0.5, duration: 400.ms, curve: Curves.easeOutBack)
        .fadeIn();
  }
}

class _TransactionTile extends StatelessWidget {
  final Transaction txn;
  final String currency;

  const _TransactionTile({required this.txn, required this.currency});

  @override
  Widget build(BuildContext context) {
    final isExpense = txn.type == TxnType.expense || txn.type == TxnType.lent;
    final color = AppColors.categoryColor(txn.category);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 4,
        ),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.category, color: color),
        ),
        title: Text(
          txn.note?.isNotEmpty == true ? txn.note! : txn.category,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          txn.category.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        trailing: Text(
          '${isExpense ? '-' : '+'}${formatMoney(txn.amount, currency)}',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: isExpense ? AppColors.textPrimary : AppColors.income,
          ),
        ),
      ),
    ).animate().fadeIn().slideX(begin: 0.1);
  }
}

class _CategoryChart extends StatefulWidget {
  final Map<String, double> totals;
  final String currency;
  const _CategoryChart({required this.totals, required this.currency});

  @override
  State<_CategoryChart> createState() => _CategoryChartState();
}

class _CategoryChartState extends State<_CategoryChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final entries = widget.totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (sum, e) => sum + e.value);
    final touchedIndex = _touchedIndex;
    final highlighted =
        touchedIndex != null &&
            touchedIndex >= 0 &&
            touchedIndex < entries.length
        ? entries[touchedIndex]
        : null;

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 4,
                  centerSpaceRadius: 55,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      if (!event.isInterestedForInteractions ||
                          response?.touchedSection == null) {
                        setState(() => _touchedIndex = null);
                        return;
                      }
                      setState(
                        () => _touchedIndex =
                            response!.touchedSection!.touchedSectionIndex,
                      );
                    },
                  ),
                  sections: List.generate(entries.length, (i) {
                    final e = entries[i];
                    final pct = total > 0 ? e.value / total * 100 : 0.0;
                    final isTouched = i == _touchedIndex;
                    return PieChartSectionData(
                      value: e.value,
                      color: AppColors.categoryColor(e.key),
                      title: '${pct.round()}%',
                      radius: isTouched ? 65 : 55,
                      titleStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    );
                  }),
                ),
              ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: highlighted != null
                    ? Column(
                        key: ValueKey(highlighted.key),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            highlighted.key,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            formatMoney(highlighted.value, widget.currency),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      )
                    : Column(
                        key: const ValueKey('total'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Total',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            formatMoney(total, widget.currency),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ...entries.map(
          (e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.categoryColor(e.key),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(e.key)),
                Text(formatMoney(e.value, widget.currency)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Per-category budget adherence for the viewed month — only shows
/// categories that actually have a budget set (via the budget planner).
class _BudgetVsActual extends StatelessWidget {
  final Map<String, double> budgets;
  final Map<String, double> actuals;
  final String currency;

  const _BudgetVsActual({
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
class _TrendChart extends StatelessWidget {
  final List<MonthPoint> points;
  final String currency;

  const _TrendChart({required this.points, required this.currency});

  @override
  Widget build(BuildContext context) {
    final maxVal = points.fold<double>(
      0,
      (m, p) => [m, p.income, p.expense].reduce((a, b) => a > b ? a : b),
    );
    final ceiling = maxVal <= 0 ? 1.0 : maxVal * 1.15;

    return Column(
      children: [
        SizedBox(
          height: 160,
          child: BarChart(
            BarChartData(
              maxY: ceiling,
              alignment: BarChartAlignment.spaceAround,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= points.length) return const SizedBox();
                      final parts = points[i].month.split('-');
                      final label = _monthNames[int.parse(parts[1]) - 1]
                          .substring(0, 3);
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                      BarTooltipItem(
                        formatMoney(rod.toY, currency),
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                ),
              ),
              barGroups: List.generate(points.length, (i) {
                final p = points[i];
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: p.income,
                      color: AppColors.income,
                      width: 8,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    BarChartRodData(
                      toY: p.expense,
                      color: AppColors.expense,
                      width: 8,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendDot(color: AppColors.income, label: 'Income'),
            const SizedBox(width: AppSpacing.md),
            _LegendDot(color: AppColors.expense, label: 'Expense'),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
