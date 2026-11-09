import 'package:flutter/material.dart';

import '../../core/constants/calendar.dart';
import '../../core/finance/salary_cycle.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/animated_money_text.dart';
import '../dashboard/widgets/ink_metric.dart';
import 'cycle_controller.dart';

String shortDate(DateTime d) => '${d.day} ${kMonthNamesShort[d.month - 1]}';

/// "10 Nov – 11 Dec", or "10 Nov – today" for the open cycle.
String cycleLabel(CycleRange c) =>
    '${shortDate(c.start)} – ${c.end == null ? 'today' : shortDate(c.end!)}';

/// The salary cycle's focal card: what came in, what went out, and how long
/// it has to last.
class CycleCard extends StatelessWidget {
  final CycleSummary summary;
  final String currency;

  const CycleCard({super.key, required this.summary, required this.currency});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final on = p.onInk;
    final muted = p.onInkMuted;
    final c = summary.cycle;
    final left = summary.leftFromIncome;
    final standing = summary.standing;
    final noSalary =
        c.record.salaryTxnId == null && c.record.untrackedSalaryPaise == null;

    return Container(
      decoration: BoxDecoration(
        color: p.inkSurface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg - 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            standing == null
                ? 'Salary cycle · ${cycleLabel(c)}'
                : 'Salary cycle · ${cycleLabel(c)} · day ${standing.dayNumber}',
            style: text.labelMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            left >= 0
                ? 'Left from this cycle’s income'
                : 'Spent more than this cycle’s income',
            style: text.bodySmall?.copyWith(color: muted),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMoneyText(
              amountPaise: left.abs(),
              currency: currency,
              style: text.headlineMedium?.copyWith(color: on),
            ),
          ),
          if (standing != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              standing.salaryLate
                  ? 'Next salary is later than expected. Record it when it '
                        'arrives.'
                  : 'Next salary expected ${shortDate(standing.window.earliest)}'
                        '–${shortDate(standing.window.latest)} · must last up '
                        'to ${standing.daysToLast} more '
                        'day${standing.daysToLast == 1 ? '' : 's'}',
              style: text.bodySmall?.copyWith(
                color: standing.salaryLate ? p.inkWarning : muted,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Divider(color: on.withValues(alpha: 0.14)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              InkMetric(
                label: noSalary ? 'Salary (none yet)' : 'Salary',
                value: formatMoneyCompact(summary.income.salary, currency),
              ),
              InkMetric(
                label: 'Other income',
                value: formatMoneyCompact(summary.income.additional, currency),
              ),
              InkMetric(
                label: 'Spent',
                value: formatMoneyCompact(summary.spent, currency),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Before upcoming bills, EMIs and card dues.',
            style: text.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}
