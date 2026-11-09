import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/calendar.dart';
import '../../../core/finance/calendar_events.dart';
import '../../../core/finance/dashboard.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/budget_progress_bar.dart';
import '../../../core/widgets/page_transitions.dart';
import '../../../core/widgets/section_header.dart';
import '../../allocation/allocation_controller.dart';
import '../../allocation/allocation_screen.dart';
import '../../calendar/calendar_screen.dart';
import '../../cards/cards_screen.dart';
import '../../cycles/cycle_card.dart';
import '../../emergency/emergency_controller.dart';
import '../../emergency/emergency_screen.dart';
import '../../expenses/expenses_controller.dart';
import '../../goals/goals_controller.dart';
import '../../goals/goals_screen.dart';
import '../../investments/investments_screen.dart';
import '../../loans/loans_screen.dart';
import '../../../data/repositories/net_worth_repository.dart';
import '../../settings/settings_controller.dart';
import '../dashboard_controller.dart';

void _open(BuildContext context, Widget page) =>
    Navigator.of(context).push(FadeSlideRoute(page: page));

/// Label over a figure that shrinks to fit rather than overflow.
class FigureColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool end;
  const FigureColumn({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.end = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: end
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: text.moneyStyle(15, color: color)),
          ),
        ],
      ),
    );
  }
}

/// Allocated · unallocated now · due before payday, for the open cycle.
class CyclePlanCard extends StatelessWidget {
  const CyclePlanCard({super.key});

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DashboardController>();
    if (!d.ready) return const SizedBox.shrink();
    final cur = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final plan = d.cyclePlan();
    final p = context.palette;
    String fmt(int v) => formatMoney(v, cur);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: AppCard(
        onTap: () => _open(context, const AllocationScreen()),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                FigureColumn(label: 'Allocated', value: fmt(plan.allocated)),
                FigureColumn(
                  label: 'Unallocated now',
                  value: fmt(plan.unallocated),
                  color: plan.unallocated < 0 ? p.expense : null,
                ),
                FigureColumn(
                  label: 'Due before payday',
                  value: fmt(plan.dueBeforePayday),
                  color: plan.dueBeforePayday > 0 ? p.warning : null,
                  end: true,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              plan.dueBeforePayday > plan.unallocated + plan.allocated
                  ? 'Dues ahead are more than the money planned and free. '
                        'Open Smart allocation.'
                  : 'Allocated money is set aside, not spent. Tap to plan.',
              style: _text(context).bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

TextTheme _text(BuildContext context) => Theme.of(context).textTheme;

/// Debt and wealth at a glance — each card hides itself when empty.
class FinanceOverview extends StatelessWidget {
  const FinanceOverview({super.key});

  @override
  Widget build(BuildContext context) {
    final ready = context.select<DashboardController, bool>((d) => d.ready);
    if (!ready) return const SizedBox.shrink();
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [DebtOverviewCard(), WealthOverviewCard()],
    );
  }
}

class DebtOverviewCard extends StatelessWidget {
  const DebtOverviewCard({super.key});

  @override
  Widget build(BuildContext context) {
    final debt = context.watch<DashboardController>().debt;
    if (debt.isEmpty) return const SizedBox.shrink();
    final cur = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final p = context.palette;
    String fmt(int v) => formatMoney(v, cur);
    String next(FinEvent? e, String label) => e == null
        ? ''
        : '$label ${shortDate(e.date)}${e.amount == null ? '' : ' · ${fmt(e.amount!)}'}';

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            'Debt',
            action: 'Calendar',
            onAction: () => _open(context, const CalendarScreen()),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (debt.overdue.isNotEmpty)
                  _Row(
                    icon: Icons.error_outline_rounded,
                    color: p.expense,
                    title:
                        '${debt.overdue.length} overdue · ${fmt(debt.overdueTotal)}',
                    subtitle: debt.overdue.map((e) => e.title).join(', '),
                    onTap: () => _open(context, const CalendarScreen()),
                  ),
                if (debt.cards > 0 || debt.nextCardDue != null)
                  _Row(
                    icon: Icons.credit_card_rounded,
                    color: p.warning,
                    title: 'Credit cards',
                    value: fmt(debt.cards),
                    subtitle: [
                      next(debt.nextCardDue, 'Due'),
                      next(debt.nextStatement, 'Statement'),
                    ].where((s) => s.isNotEmpty).join(' · '),
                    onTap: () => _open(context, const CardsScreen()),
                  ),
                if (debt.loans > 0 || debt.nextEmi != null)
                  _Row(
                    icon: Icons.account_balance_rounded,
                    color: p.debt,
                    title: 'Loans & EMI',
                    value: fmt(debt.loans),
                    subtitle: next(debt.nextEmi, 'Next EMI'),
                    onTap: () => _open(context, const LoansScreen()),
                  ),
                if (debt.borrowed > 0)
                  _Row(
                    icon: Icons.call_made_rounded,
                    color: p.expense,
                    title: 'You owe people',
                    value: fmt(debt.borrowed),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WealthOverviewCard extends StatelessWidget {
  const WealthOverviewCard({super.key});

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DashboardController>();
    final emergency = context.watch<EmergencyController>().status;
    final goals = context.watch<GoalsController>().active;
    final planned = context.select<AllocationController, int>(
      (c) => c.config.investPerCycle ?? 0,
    );
    final cur = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final p = context.palette;
    final t = _text(context);
    String fmt(int v) => formatMoney(v, cur);
    final pos = d.position;
    final longGoals = goals
        .where((g) => g.goal.horizon.name == 'long')
        .fold(0, (s, g) => s + (g.goal.monthlyContributionPaise ?? 0));
    final saved = goals.fold(0, (s, g) => s + g.saved);
    final target = goals.fold(0, (s, g) => s + g.goal.targetPaise);
    final hasEmergency = emergency != null && emergency.target > 0;
    if (!hasEmergency &&
        goals.isEmpty &&
        pos.investments == 0 &&
        d.trend.length < 2) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Wealth'),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasEmergency)
                  _Row(
                    icon: Icons.shield_outlined,
                    color: p.income,
                    title: 'Emergency fund · ${emergency.percent}%',
                    value: fmt(emergency.current),
                    subtitle: emergency.coverageMonths == null
                        ? 'of ${fmt(emergency.target)}'
                        : 'of ${fmt(emergency.target)} · covers '
                              '${emergency.coverageMonths!.toStringAsFixed(1)} months',
                    progress: (emergency.current, emergency.target),
                    onTap: () => _open(context, const EmergencyScreen()),
                  ),
                if (goals.isNotEmpty)
                  _Row(
                    icon: Icons.flag_rounded,
                    color: p.savings,
                    title:
                        '${goals.length} goal${goals.length == 1 ? '' : 's'}',
                    value: fmt(saved),
                    subtitle: 'saved of ${fmt(target)}',
                    progress: (saved, target),
                    onTap: () => _open(context, const GoalsScreen()),
                  ),
                if (pos.investments > 0 || planned + longGoals > 0)
                  _Row(
                    icon: Icons.trending_up_rounded,
                    color: p.debt,
                    title: 'Investments',
                    value: fmt(pos.investments),
                    subtitle: planned + longGoals > 0
                        ? 'Planned ${fmt(planned + longGoals)} a month'
                        : 'Your recorded values',
                    onTap: () => _open(context, const InvestmentsScreen()),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: d.trend.length < 2
                      ? Text(
                          'Net worth trend builds month by month from now.',
                          style: t.bodySmall,
                        )
                      : _NetWorthTrend(points: d.trend, currency: cur),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NetWorthTrend extends StatelessWidget {
  final List<NetWorthPoint> points;
  final String currency;
  const _NetWorthTrend({required this.points, required this.currency});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = _text(context);
    final values = [for (final x in points) x.netWorth];
    final change = values.last - values.first;
    final m = int.parse(points.first.month.substring(5));
    final first =
        '${kMonthNamesShort[m - 1]} ${points.first.month.substring(0, 4)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Net worth ${change >= 0 ? 'up' : 'down'} '
          '${formatMoney(change.abs(), currency)} since $first',
          style: t.labelMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: AppSpacing.xxl + AppSpacing.md,
          child: Semantics(
            label: 'Net worth trend over ${values.length} months',
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (final (i, v) in values.indexed)
                        FlSpot(i.toDouble(), v / 100),
                    ],
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: change >= 0 ? p.income : p.expense,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? value;
  final String subtitle;
  final (int, int)? progress;
  final VoidCallback? onTap;

  const _Row({
    required this.icon,
    required this.color,
    required this.title,
    this.value,
    this.subtitle = '',
    this.progress,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = _text(context);
    final pr = progress;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: AppIconSize.md, color: color),
            const SizedBox(width: AppSpacing.md - 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, style: t.titleSmall)),
                      if (value != null) Text(value!, style: t.moneyStyle(14)),
                    ],
                  ),
                  if (subtitle.isNotEmpty) Text(subtitle, style: t.bodySmall),
                  if (pr != null && pr.$2 > 0) ...[
                    const SizedBox(height: AppSpacing.xs),
                    BudgetProgressBar(
                      spent: pr.$1.clamp(0, pr.$2),
                      budget: pr.$2,
                      color: color,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plain-language insights for a period, most urgent first.
class InsightsSection extends StatefulWidget {
  final DateTime from;
  final DateTime to;
  final DateTime? previousStart;

  /// "month", "cycle" or "period".
  final String period;
  final int? limit;

  /// Show a line when there's nothing to say (Reports); Home hides.
  final bool showEmpty;

  const InsightsSection({
    super.key,
    required this.from,
    required this.to,
    this.previousStart,
    required this.period,
    this.limit,
    this.showEmpty = false,
  });

  @override
  State<InsightsSection> createState() => _InsightsSectionState();
}

class _InsightsSectionState extends State<InsightsSection> {
  List<Insight>? _insights;
  late final ExpensesController _expenses;
  late final DashboardController _dashboard;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _expenses = context.read<ExpensesController>()..addListener(_load);
    _dashboard = context.read<DashboardController>();
    _load();
  }

  @override
  void didUpdateWidget(InsightsSection old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from ||
        old.to != widget.to ||
        old.previousStart != widget.previousStart) {
      _load();
    }
  }

  @override
  void dispose() {
    _expenses.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!_dashboard.ready) return;
    final token = ++_token;
    try {
      final list = await _dashboard.insights(
        from: widget.from,
        to: widget.to,
        previousStart: widget.previousStart,
        period: widget.period,
      );
      if (mounted && token == _token) setState(() => _insights = list);
    } catch (e) {
      debugPrint('Insights failed: ${e.runtimeType}');
      if (mounted && token == _token) setState(() => _insights = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _insights;
    if (all == null || (all.isEmpty && !widget.showEmpty)) {
      return const SizedBox.shrink();
    }
    final shown = widget.limit == null ? all : all.take(widget.limit!);
    final p = context.palette;
    final t = _text(context);
    (IconData, Color) look(InsightTone tone) => switch (tone) {
      InsightTone.alert => (Icons.error_outline_rounded, p.expense),
      InsightTone.warning => (Icons.warning_amber_rounded, p.warning),
      InsightTone.info => (Icons.lightbulb_outline_rounded, p.savings),
      InsightTone.good => (Icons.check_circle_outline_rounded, p.income),
    };
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Insights'),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: all.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Text(
                      'Nothing stands out for this ${widget.period} yet.',
                      style: t.bodyMedium,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final i in shown)
                        _Row(
                          icon: look(i.tone).$1,
                          color: look(i.tone).$2,
                          title: i.title,
                          subtitle: i.detail,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
