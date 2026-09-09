import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/calendar.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/transaction_tile.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/transaction_repository.dart';
import '../expenses/expenses_controller.dart';
import '../settings/settings_controller.dart';

enum _RangePreset { thisMonth, lastMonth, last3Months, thisYear, custom }

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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _range = _rangeFor(_RangePreset.thisMonth);
    _load();
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
      case _RangePreset.custom:
        return _range;
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final expenses = context.read<ExpensesController>();
    final totals = await expenses.totalsRange(_range.start, _range.end);
    final cats = await expenses.categoryTotalsRange(_range.start, _range.end);
    if (!mounted) return;
    setState(() {
      _totals = totals;
      _categoryTotals = cats;
      _loading = false;
    });
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
      MaterialPageRoute(
        builder: (_) => CategoryDrillDownScreen(
          category: category,
          from: _range.start,
          to: _range.end,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<SettingsController>().config.currency;
    final totals = _totals ?? const MonthTotal();
    final net = totals.income - totals.expense;
    final sortedCategories = _categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _PresetChip(
                    label: 'This month',
                    selected: _preset == _RangePreset.thisMonth,
                    onTap: () => _selectPreset(_RangePreset.thisMonth),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _PresetChip(
                    label: 'Last month',
                    selected: _preset == _RangePreset.lastMonth,
                    onTap: () => _selectPreset(_RangePreset.lastMonth),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _PresetChip(
                    label: 'Last 3 months',
                    selected: _preset == _RangePreset.last3Months,
                    onTap: () => _selectPreset(_RangePreset.last3Months),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _PresetChip(
                    label: 'This year',
                    selected: _preset == _RangePreset.thisYear,
                    onTap: () => _selectPreset(_RangePreset.thisYear),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _PresetChip(
                    label: 'Custom',
                    selected: _preset == _RangePreset.custom,
                    onTap: () => _selectPreset(_RangePreset.custom),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(_rangeLabel, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.md),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: _SummaryStat(
                        label: 'Income',
                        value: totals.income,
                        currency: currency,
                        color: AppColors.income,
                      ),
                    ),
                    Expanded(
                      child: _SummaryStat(
                        label: 'Expense',
                        value: totals.expense,
                        currency: currency,
                        color: AppColors.expense,
                      ),
                    ),
                    Expanded(
                      child: _SummaryStat(
                        label: 'Net',
                        value: net,
                        currency: currency,
                        color: net >= 0 ? AppColors.income : AppColors.expense,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'By category',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              if (sortedCategories.isEmpty)
                AppCard(child: Text('No spending in this range.'))
              else
                AppCard(
                  child: Column(
                    children: [
                      for (final e in sortedCategories) ...[
                        _CategoryRow(
                          category: e.key,
                          amountPaise: e.value,
                          total: totals.expense,
                          currency: currency,
                          onTap: () => _openCategory(e.key),
                        ),
                        if (e != sortedCategories.last)
                          const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;

  /// In paise.
  final int value;
  final String currency;
  final Color color;

  const _SummaryStat({
    required this.label,
    required this.value,
    required this.currency,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          formatMoney(value, currency),
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ],
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
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    category,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Text(
                  formatMoney(amountPaise, currency),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 6,
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : theme.cardTheme.color,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.primary : theme.dividerColor,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: selected ? Colors.white : null,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.category)),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
          ? const Center(child: Text('No transactions in this range.'))
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: rows.length,
              itemBuilder: (context, i) =>
                  TransactionTile(txn: rows[i], currency: currency),
            ),
    );
  }
}
