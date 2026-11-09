import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/calendar.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/animated_money_text.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_chip.dart';
import '../../core/widgets/budget_progress_bar.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/widgets/page_transitions.dart';
import '../../core/widgets/responsive.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/transaction_tile.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/transaction_repository.dart';
import '../dashboard/widgets/budget_vs_actual.dart';
import '../dashboard/widgets/trend_chart.dart';
import '../expenses/expenses_controller.dart';
import '../settings/settings_controller.dart';
import '../budgets/budget_controller.dart';
import '../cycles/cycle_controller.dart';
import '../dashboard/widgets/overview_cards.dart';
import 'category_chart.dart';
import 'spending_line_chart.dart';

enum _RangePreset {
  thisMonth,
  lastMonth,
  thisCycle,
  lastCycle,
  last3Months,
  thisYear,
  custom,
}

/// Ranges longer than this chart one point per month instead of per day.
const _maxDailyPoints = 62;

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _RangePreset _preset = _RangePreset.thisMonth;
  late DateTimeRange _range;
  MonthTotal? _totals;
  Map<String, int> _categoryTotals = {};
  List<SpendPoint> _series = [];
  List<MonthPoint> _trend = [];
  bool _loading = true;
  bool _failed = false;
  late final ExpensesController _expenses;

  @override
  void initState() {
    super.initState();
    _expenses = context.read<ExpensesController>();
    _range = _rangeFor(_RangePreset.thisMonth);
    // Stays mounted as a tab, so follow ledger changes made elsewhere.
    _expenses.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _expenses.removeListener(_load);
    super.dispose();
  }

  DateTimeRange _rangeFor(_RangePreset preset) {
    final now = DateTime.now();
    switch (preset) {
      case _RangePreset.thisMonth:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case _RangePreset.lastMonth:
        final firstOfThisMonth = DateTime(now.year, now.month, 1);
        final lastMonthEnd = firstOfThisMonth.subtract(const Duration(days: 1));
        return DateTimeRange(
          start: DateTime(lastMonthEnd.year, lastMonthEnd.month, 1),
          end: lastMonthEnd,
        );
      case _RangePreset.last3Months:
        return DateTimeRange(
          start: DateTime(now.year, now.month - 2, 1),
          end: now,
        );
      case _RangePreset.thisYear:
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
      case _RangePreset.thisCycle || _RangePreset.lastCycle:
        // Same transactions, a salary-to-salary date range.
        final cycles = context.read<CycleController>().cycles;
        final i = cycles.length - (preset == _RangePreset.thisCycle ? 1 : 2);
        if (i < 0) return _rangeFor(_RangePreset.thisMonth);
        final c = cycles[i];
        return DateTimeRange(start: c.start, end: c.queryEnd(now));
      case _RangePreset.custom:
        return _range;
    }
  }

  /// Where the comparable earlier stretch starts: the previous month or
  /// cycle; null compares with the same number of days just before.
  DateTime? get _previousStart {
    switch (_preset) {
      case _RangePreset.thisMonth || _RangePreset.lastMonth:
        return DateTime(_range.start.year, _range.start.month - 1);
      case _RangePreset.thisCycle || _RangePreset.lastCycle:
        final cycles = context.read<CycleController>().cycles;
        final i = cycles.indexWhere(
          (c) => c.start.isAtSameMomentAs(_range.start),
        );
        return i > 0 ? cycles[i - 1].start : null;
      default:
        return null;
    }
  }

  bool get _monthly =>
      _range.end.difference(_range.start).inDays + 1 > _maxDailyPoints;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final results = await Future.wait([
        _expenses.totalsRange(_range.start, _range.end),
        _expenses.categoryTotalsRange(_range.start, _range.end),
        _expenses.expenseSeries(_range.start, _range.end, monthly: _monthly),
        _expenses.monthlyTrend(6),
      ]);
      if (!mounted) return;
      setState(() {
        _totals = results[0] as MonthTotal;
        _categoryTotals = results[1] as Map<String, int>;
        _series = _fillSeries(results[2] as Map<String, int>);
        _trend = results[3] as List<MonthPoint>;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Reports load failed: ${e.runtimeType}');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// Zero-fills every day (or month) in range so gaps read as "no spend".
  List<SpendPoint> _fillSeries(Map<String, int> buckets) {
    String two(int n) => n.toString().padLeft(2, '0');
    final points = <SpendPoint>[];
    final start = _range.start;
    final end = _range.end;
    if (_monthly) {
      var m = DateTime(start.year, start.month);
      while (!m.isAfter(DateTime(end.year, end.month))) {
        final key = '${m.year}-${two(m.month)}';
        final name = kMonthNamesShort[m.month - 1];
        points.add(SpendPoint(name, '$name ${m.year}', buckets[key] ?? 0));
        m = DateTime(m.year, m.month + 1);
      }
    } else {
      var d = DateTime(start.year, start.month, start.day);
      final last = DateTime(end.year, end.month, end.day);
      while (!d.isAfter(last)) {
        final key = '${d.year}-${two(d.month)}-${two(d.day)}';
        final mon = kMonthNamesShort[d.month - 1];
        points.add(
          SpendPoint(
            '${d.day} $mon',
            '${d.day} $mon ${d.year}',
            buckets[key] ?? 0,
          ),
        );
        d = DateTime(d.year, d.month, d.day + 1);
      }
    }
    return points;
  }

  Future<void> _selectPreset(_RangePreset preset) async {
    if (preset == _RangePreset.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: now,
        initialDateRange: _range,
      );
      if (picked == null) return;
      setState(() {
        _preset = preset;
        _range = DateTimeRange(
          start: picked.start,
          end: DateTime(
            picked.end.year,
            picked.end.month,
            picked.end.day,
            23,
            59,
            59,
          ),
        );
      });
    } else {
      setState(() {
        _preset = preset;
        _range = _rangeFor(preset);
      });
    }
    _load();
  }

  String get _rangeLabel {
    String fmt(DateTime d) =>
        '${d.day} ${kMonthNamesShort[d.month - 1]} ${d.year}';
    return '${fmt(_range.start)} – ${fmt(_range.end)}';
  }

  void _openCategory(String category) {
    Navigator.of(context).push(
      FadeSlideRoute(
        page: CategoryDrillDownScreen(
          category: category,
          from: _range.start,
          to: _range.end,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<SettingsController>().config;
    final currency = config.currency;
    final budgets = context.watch<BudgetController>();
    final cycleCount = context.select<CycleController, int>(
      (c) => c.cycles.length,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ResponsivePage(
        builder: (context, gutter) => RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.navClearance),
            children: [
              ChipRow(
                children: [
                  for (final (preset, label) in [
                    (_RangePreset.thisMonth, 'This month'),
                    (_RangePreset.lastMonth, 'Last month'),
                    if (cycleCount > 0) (_RangePreset.thisCycle, 'This cycle'),
                    if (cycleCount > 1) (_RangePreset.lastCycle, 'Last cycle'),
                    (_RangePreset.last3Months, '3 months'),
                    (_RangePreset.thisYear, 'This year'),
                    (_RangePreset.custom, 'Custom'),
                  ])
                    AppChoiceChip(
                      label: label,
                      icon: preset == _RangePreset.custom
                          ? Icons.date_range_rounded
                          : null,
                      selected: _preset == preset,
                      onTap: () => _selectPreset(preset),
                    ),
                ],
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  AppSpacing.sm + 2,
                  gutter,
                  0,
                ),
                child: Text(
                  _rangeLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(gutter, AppSpacing.md, gutter, 0),
                child: AnimatedSwitcher(
                  duration: AppDurations.of(context, AppDurations.base),
                  child: _loading && _totals == null
                      ? const _ReportsSkeleton()
                      : _failed
                      ? ErrorState(
                          message: "Couldn't load this report.",
                          onRetry: _load,
                        )
                      : _buildContent(
                          budgets.monthCategoryCaps,
                          budgets.monthOverall,
                          currency,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    Map<String, int> budgets,
    int monthlyBudget,
    String currency,
  ) {
    final totals = _totals ?? const MonthTotal();
    final net = totals.income - totals.expense;
    final days = _range.end.difference(_range.start).inDays + 1;
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final sortedCategories =
        _categoryTotals.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final rate = totals.income > 0 ? (net / totals.income * 100).round() : null;
    final isThisMonth = _preset == _RangePreset.thisMonth;
    const gap = SizedBox(height: AppSpacing.lg);

    return Column(
      key: ValueKey('$_preset$_rangeLabel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg - 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Net cash flow', style: text.labelMedium),
              const SizedBox(height: AppSpacing.xs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AnimatedMoneyText(
                  amountPaise: net,
                  currency: currency,
                  style: text.headlineMedium?.copyWith(
                    color: net >= 0 ? p.income : p.expense,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  _Metric(
                    label: 'Income',
                    value: formatMoneyCompact(totals.income, currency),
                    color: p.income,
                    icon: Icons.south_west_rounded,
                  ),
                  _Metric(
                    label: 'Expenses',
                    value: formatMoneyCompact(totals.expense, currency),
                    color: p.expense,
                    icon: Icons.north_east_rounded,
                  ),
                  _Metric(
                    label: 'Savings rate',
                    value: rate == null ? '—' : '$rate%',
                    color: p.savings,
                    icon: Icons.savings_outlined,
                  ),
                ],
              ),
            ],
          ),
        ),
        InsightsSection(
          from: _range.start,
          to: _range.end,
          previousStart: _previousStart,
          period: switch (_preset) {
            _RangePreset.thisMonth || _RangePreset.lastMonth => 'month',
            _RangePreset.thisCycle || _RangePreset.lastCycle => 'cycle',
            _ => 'period',
          },
          showEmpty: true,
        ),
        gap,
        SectionHeader(_monthly ? 'Monthly spending' : 'Daily spending'),
        AppCard(
          child: totals.expense == 0
              ? const EmptyState(
                  icon: Icons.show_chart_rounded,
                  message: 'No spending in this range.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Avg ${formatMoney(totals.expense ~/ days, currency)} per day',
                      style: text.labelMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SpendingLineChart(points: _series, currency: currency),
                  ],
                ),
        ),
        gap,
        const SectionHeader('By category'),
        if (sortedCategories.isEmpty)
          const AppCard(
            child: EmptyState(
              icon: Icons.donut_large_rounded,
              message: 'No spending in this range.',
            ),
          )
        else
          AppCard(
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, c) => CategoryChart(
                    totals: _categoryTotals,
                    currency: currency,
                    size: c.maxWidth.clamp(160.0, 240.0),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                for (var i = 0; i < sortedCategories.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.xs),
                  _CategoryRow(
                    category: sortedCategories[i].key,
                    amountPaise: sortedCategories[i].value,
                    total: totals.expense,
                    currency: currency,
                    onTap: () => _openCategory(sortedCategories[i].key),
                  ),
                ],
              ],
            ),
          ),
        if (isThisMonth && (monthlyBudget > 0 || budgets.isNotEmpty)) ...[
          gap,
          const SectionHeader('Budget utilization'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (monthlyBudget > 0) ...[
                  Row(
                    children: [
                      Expanded(child: Text('Overall', style: text.titleSmall)),
                      Text(
                        '${formatMoney(totals.expense, currency)} / ${formatMoney(monthlyBudget, currency)}',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  BudgetProgressBar(
                    spent: totals.expense,
                    budget: monthlyBudget,
                  ),
                  if (budgets.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    const Divider(),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ],
                if (budgets.isNotEmpty)
                  BudgetVsActual(
                    budgets: budgets,
                    actuals: _categoryTotals,
                    currency: currency,
                  ),
              ],
            ),
          ),
        ],
        if (_trend.any((p) => p.income > 0 || p.expense > 0)) ...[
          gap,
          const SectionHeader('Last 6 months'),
          AppCard(
            child: TrendChart(points: _trend, currency: currency),
          ),
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _Metric({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  label,
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: text.moneyStyle(16)),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final String category;

  /// Both in paise.
  final int amountPaise;
  final int total;
  final String currency;
  final VoidCallback onTap;

  const _CategoryRow({
    required this.category,
    required this.amountPaise,
    required this.total,
    required this.currency,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final frac = total > 0 ? (amountPaise / total).clamp(0.0, 1.0) : 0.0;
    final color = AppColors.categoryColor(category);
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label:
          '$category, ${formatMoney(amountPaise, currency)}, ${(frac * 100).round()} percent. Open transactions',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm - 2),
          child: Row(
            children: [
              CategoryIcon(category: category, size: 36),
              const SizedBox(width: AppSpacing.md - 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            category,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          formatMoney(amountPaise, currency),
                          style: text.moneyStyle(14),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs + 2),
                    Row(
                      children: [
                        Expanded(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: frac),
                            duration: AppDurations.of(
                              context,
                              AppDurations.slow,
                            ),
                            curve: Curves.easeOutCubic,
                            builder: (context, v, _) => ClipRRect(
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                              child: LinearProgressIndicator(
                                value: v,
                                minHeight: 6,
                                backgroundColor: p.surfaceAlt,
                                valueColor: AlwaysStoppedAnimation(color),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${(frac * 100).round()}%',
                            textAlign: TextAlign.end,
                            style: text.labelSmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.chevron_right_rounded, color: p.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportsSkeleton extends StatelessWidget {
  const _ReportsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SkeletonBox(height: 140, radius: AppRadius.lg),
        SizedBox(height: AppSpacing.lg),
        SkeletonBox(height: 240, radius: AppRadius.lg),
        SizedBox(height: AppSpacing.lg),
        SkeletonBox(height: 280, radius: AppRadius.lg),
      ],
    );
  }
}

/// Every transaction in one category within a date range — the "tap a
/// category to see what's in it" drill-down.
class CategoryDrillDownScreen extends StatefulWidget {
  final String category;
  final DateTime from;
  final DateTime to;

  const CategoryDrillDownScreen({
    super.key,
    required this.category,
    required this.from,
    required this.to,
  });

  @override
  State<CategoryDrillDownScreen> createState() =>
      _CategoryDrillDownScreenState();
}

class _CategoryDrillDownScreenState extends State<CategoryDrillDownScreen> {
  List<Transaction>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await context.read<ExpensesController>().queryPage(
      limit: 1000,
      category: widget.category,
      from: widget.from,
      to: widget.to,
      type: TxnType.expense,
    );
    if (mounted) setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<SettingsController>().config.currency;
    final rows = _rows;
    final total = rows?.fold<int>(0, (s, t) => s + t.amountPaise) ?? 0;
    final text = Theme.of(context).textTheme;
    final color = CategoryStyle.of(widget.category).color;
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(title: Text(widget.category)),
      body: ResponsivePage(
        builder: (context, gutter) => rows == null
            ? Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: const SkeletonList(),
              )
            : rows.isEmpty
            ? const EmptyState(
                icon: Icons.receipt_long_outlined,
                message: 'No transactions in this range.',
              )
            : ListView.builder(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  AppSpacing.sm,
                  gutter,
                  AppSpacing.xl,
                ),
                itemCount: rows.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                      padding: const EdgeInsets.all(AppSpacing.lg - 4),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          color.withValues(
                            alpha:
                                Theme.of(context).brightness == Brightness.dark
                                ? 0.2
                                : 0.1,
                          ),
                          palette.surface,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                      ),
                      child: Row(
                        children: [
                          CategoryIcon(
                            category: widget.category,
                            size: 48,
                            solid: true,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${rows.length} transaction${rows.length == 1 ? '' : 's'}',
                                  style: text.labelMedium,
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    formatMoney(total, currency),
                                    style: text.moneyStyle(28),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final first = i == 1;
                  final last = i == rows.length;
                  final p = context.palette;
                  return Container(
                    decoration: BoxDecoration(
                      color: p.surface,
                      border: Border(
                        left: BorderSide(color: p.border),
                        right: BorderSide(color: p.border),
                        top: first
                            ? BorderSide(color: p.border)
                            : BorderSide.none,
                        bottom: last
                            ? BorderSide(color: p.border)
                            : BorderSide.none,
                      ),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(first ? AppRadius.lg : 0),
                        bottom: Radius.circular(last ? AppRadius.lg : 0),
                      ),
                    ),
                    child: TransactionTile(
                      txn: rows[i - 1],
                      currency: currency,
                      showDate: true,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
