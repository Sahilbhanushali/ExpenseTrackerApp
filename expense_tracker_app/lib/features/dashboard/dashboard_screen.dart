import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/calendar.dart';
import '../../core/finance/salary_cycle.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/responsive.dart';
import '../../data/repositories/transaction_repository.dart';
import '../cycles/cycle_card.dart';
import '../cycles/cycle_controller.dart';
import '../cycles/cycle_summary_section.dart';
import '../cycles/salary_sheets.dart';
import '../expenses/expenses_controller.dart';
import '../settings/settings_controller.dart';
import 'widgets/month_summary_section.dart';
import 'widgets/net_worth_section.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback onSeeAllTransactions;
  final VoidCallback onOpenReports;

  const DashboardScreen({
    super.key,
    required this.onSeeAllTransactions,
    required this.onOpenReports,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late DateTime _viewedMonth;
  MonthTotal? _viewedTotals;
  Map<String, int> _viewedCategoryTotals = {};
  List<MonthPoint> _trend = [];
  bool _trendLoaded = false;
  late final ExpensesController _expenses;

  /// A past cycle being looked at; null shows the current one live.
  CycleSummary? _pastCycle;

  void _showCycle(CycleRange? c, CycleController cycles) async {
    if (c == null) return;
    if (c.record.id == cycles.cycles.last.record.id) {
      setState(() => _pastCycle = null);
      return;
    }
    final summary = await cycles.summaryFor(c);
    if (mounted) setState(() => _pastCycle = summary);
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _viewedMonth = DateTime(now.year, now.month);
    _expenses = context.read<ExpensesController>();
    // Keeps the 6-month chart in step with adds/edits made anywhere.
    _expenses.addListener(_loadTrend);
    _loadTrend();
  }

  @override
  void dispose() {
    _expenses.removeListener(_loadTrend);
    super.dispose();
  }

  Future<void> _loadTrend() async {
    final trend = await _expenses.monthlyTrend(6);
    if (mounted) {
      setState(() {
        _trend = trend;
        _trendLoaded = true;
      });
    }
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
    final totals = await _expenses.monthTotalFor(_monthKey);
    final cats = await _expenses.categoryTotalsFor(_monthKey);
    if (!mounted) return;
    setState(() {
      _viewedTotals = totals;
      _viewedCategoryTotals = cats;
    });
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_viewedMonth.year, _viewedMonth.month + delta);
    final now = DateTime.now();
    if (next.isAfter(DateTime(now.year, now.month))) return;
    setState(() => _viewedMonth = next);
    _loadViewedMonth();
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
                    tooltip: 'Previous year',
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () => setDialogState(() => year -= 1),
                  ),
                  Text('$year', style: Theme.of(context).textTheme.titleLarge),
                  IconButton(
                    tooltip: 'Next year',
                    icon: const Icon(Icons.chevron_right_rounded),
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
                  return ChoiceChip(
                    label: Text(kMonthNamesShort[i]),
                    selected: m == month,
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
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final todayLabel =
        '${kWeekdayNames[now.weekday - 1]}, ${now.day} ${kMonthNames[now.month - 1]}';

    final cycleView = context.select<SettingsController, bool>(
      (s) => s.config.periodView == 'cycle',
    );
    final cycles = context.watch<CycleController>();
    // A past cycle that has since been removed falls back to the current.
    final past = _pastCycle;
    final shownCycle =
        past != null &&
            cycles.cycles.any((c) => c.record.id == past.cycle.record.id)
        ? past
        : cycles.current;

    // Sections subscribe only to the controllers they read, so one write
    // doesn't repaint the whole page.
    return ResponsivePage(
      builder: (context, gutter) => RefreshIndicator(
        onRefresh: () async {
          await _expenses.refresh();
          await _loadViewedMonth();
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            gutter,
            MediaQuery.paddingOf(context).top + AppSpacing.md,
            gutter,
            AppSpacing.navClearance,
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(todayLabel, style: text.bodySmall),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(_greeting(), style: text.titleLarge),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const NetWorthSection(),
            const SizedBox(height: AppSpacing.lg),
            _PeriodToggle(
              cycleView: cycleView,
              onChanged: (cycle) => context
                  .read<SettingsController>()
                  .setPeriodView(cycle ? 'cycle' : 'month'),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (!cycleView) ...[
              _MonthSwitcher(
                month: _viewedMonth,
                canGoForward: !_isCurrentMonth,
                onPrev: () => _shiftMonth(-1),
                onNext: () => _shiftMonth(1),
                onPick: _pickMonth,
              ),
              const SizedBox(height: AppSpacing.md),
              MonthSummarySection(
                viewedTotals: _viewedTotals,
                viewedCategoryTotals: _viewedCategoryTotals,
                trend: _trend,
                trendLoaded: _trendLoaded,
                isCurrentMonth: _isCurrentMonth,
                viewedMonth: _viewedMonth,
                onSeeAllTransactions: widget.onSeeAllTransactions,
                onOpenReports: widget.onOpenReports,
              ),
            ] else if (shownCycle == null)
              CycleSetupPrompt(onSetUp: () => showRecordSalarySheet(context))
            else ...[
              _CycleSwitcher(
                label: cycleLabel(shownCycle.cycle),
                previous: cycles.previousOf(shownCycle.cycle),
                next: cycles.nextOf(shownCycle.cycle),
                onShow: (c) => _showCycle(c, cycles),
              ),
              const SizedBox(height: AppSpacing.md),
              CycleSummarySection(
                summary: shownCycle,
                onSeeAllTransactions: widget.onSeeAllTransactions,
                onOpenReports: widget.onOpenReports,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "‹  September 2026  ›" — arrows step a month, the label opens a picker.
class _MonthSwitcher extends StatelessWidget {
  final DateTime month;
  final bool canGoForward;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;

  const _MonthSwitcher({
    required this.month,
    required this.canGoForward,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: onPick,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.sm,
                  horizontal: AppSpacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        '${kMonthNames[month.month - 1]} ${month.year}',
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: AppIconSize.md,
                      color: p.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Previous month',
          onPressed: onPrev,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: canGoForward ? onNext : null,
          icon: const Icon(Icons.arrow_forward_rounded),
        ),
      ],
    );
  }
}

/// Calendar month or salary cycle. Both views read the same transactions,
/// matched by date; nothing is copied between them.
class _PeriodToggle extends StatelessWidget {
  final bool cycleView;
  final ValueChanged<bool> onChanged;
  const _PeriodToggle({required this.cycleView, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
          value: false,
          icon: Icon(Icons.calendar_month_rounded),
          label: Text('Month'),
        ),
        ButtonSegment(
          value: true,
          icon: Icon(Icons.payments_outlined),
          label: Text('Salary cycle'),
        ),
      ],
      selected: {cycleView},
      showSelectedIcon: false,
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _CycleSwitcher extends StatelessWidget {
  final String label;
  final CycleRange? previous;
  final CycleRange? next;
  final ValueChanged<CycleRange?> onShow;

  const _CycleSwitcher({
    required this.label,
    required this.previous,
    required this.next,
    required this.onShow,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Previous cycle',
          onPressed: previous == null ? null : () => onShow(previous),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        IconButton(
          tooltip: 'Next cycle',
          onPressed: next == null ? null : () => onShow(next),
          icon: const Icon(Icons.arrow_forward_rounded),
        ),
      ],
    );
  }
}
