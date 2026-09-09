import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/calendar.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/press_scale.dart';
import '../../data/repositories/transaction_repository.dart';
import '../expenses/expenses_controller.dart';
import 'widgets/month_summary_section.dart';
import 'widgets/net_worth_section.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late DateTime _viewedMonth;
  MonthTotal? _viewedTotals;
  Map<String, int> _viewedCategoryTotals = {};
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
                    label: Text(kMonthNames[i].substring(0, 3)),
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
    final now = DateTime.now();
    final todayLabel =
        '${kWeekdayNames[now.weekday - 1]}, ${now.day} '
        '${kMonthNames[now.month - 1]} ${now.year}';

    // Deliberately watches nothing: each section below subscribes to just
    // the controllers it reads, so one write doesn't repaint the whole page.
    return RefreshIndicator(
      onRefresh: () async {
        await context.read<ExpensesController>().refresh();
        await _loadViewedMonth();
        await _loadTrend();
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          MediaQuery.of(context).padding.top + AppSpacing.md,
          AppSpacing.lg,
          // Clears the floating "+" button — AppSpacing.xxl (48) left the
          // last list row (Budget vs actual) sitting right under the FAB.
          120,
        ),
        children: [
          Text(_greeting(), style: Theme.of(context).textTheme.bodyMedium),
          Text('Spendo', style: Theme.of(context).textTheme.headlineSmall),
          Text(todayLabel, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.lg),
          const NetWorthSection(),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: _MonthPill(month: _viewedMonth, onTap: _pickMonth),
          ),
          const SizedBox(height: AppSpacing.md),
          MonthSummarySection(
            viewedTotals: _viewedTotals,
            viewedCategoryTotals: _viewedCategoryTotals,
            trend: _trend,
            isCurrentMonth: _isCurrentMonth,
          ),
        ],
      ),
    );
  }
}

/// The tappable "September 2026" chip that opens the month picker.
class _MonthPill extends StatelessWidget {
  final DateTime month;
  final VoidCallback onTap;

  const _MonthPill({required this.month, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
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
              '${kMonthNames[month.month - 1]} ${month.year}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }
}
