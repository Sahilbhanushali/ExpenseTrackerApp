import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/section_header.dart';
import '../dashboard/widgets/category_tiles.dart';
import '../dashboard/widgets/month_summary_section.dart';
import '../dashboard/widgets/overview_cards.dart';
import '../calendar/calendar_screen.dart';
import '../settings/settings_controller.dart';
import 'cycle_card.dart';
import 'cycle_closing_screen.dart';
import 'cycle_controller.dart';

/// The dashboard's salary-cycle view: same building blocks as the month
/// view, over the cycle's dates.
class CycleSummarySection extends StatelessWidget {
  final CycleSummary summary;
  final VoidCallback onSeeAllTransactions;
  final VoidCallback onOpenReports;

  const CycleSummarySection({
    super.key,
    required this.summary,
    required this.onSeeAllTransactions,
    required this.onOpenReports,
  });

  @override
  Widget build(BuildContext context) {
    final currency = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    const gap = SizedBox(height: AppSpacing.lg);
    final cycles = context.watch<CycleController>();
    final toClose = cycles.needsClosing;
    final c = summary.cycle;
    final isCurrent = cycles.cycles.lastOrNull?.record.id == c.record.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in toClose)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: CloseCyclePrompt(cycle: c),
          ),
        CycleCard(summary: summary, currency: currency),
        if (isCurrent) const CyclePlanCard(),
        InsightsSection(
          from: c.start,
          to: c.queryEnd(DateTime.now()),
          previousStart: cycles.previousOf(c)?.start,
          period: 'cycle',
          limit: 3,
        ),
        gap,
        SectionHeader(
          'Spending by category',
          action: summary.categories.isEmpty ? null : 'Details',
          onAction: onOpenReports,
        ),
        if (summary.categories.isEmpty)
          const AppCard(
            child: EmptyState(
              icon: Icons.donut_large_rounded,
              message: 'No spending logged in this cycle.',
            ),
          )
        else
          CategoryTiles(totals: summary.categories, currency: currency),
        if (summary.cycle.isOpen) const ComingUp(),
        if (isCurrent) const FinanceOverview(),
        gap,
        RecentTransactions(onSeeAll: onSeeAllTransactions),
      ],
    );
  }
}

/// Shown in cycle view before any cycle exists.
class CycleSetupPrompt extends StatelessWidget {
  final VoidCallback onSetUp;
  const CycleSetupPrompt({super.key, required this.onSetUp});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Track salary to salary', style: text.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Record the salary you received and the app follows each pay '
            'cycle from that date until the next salary.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(onPressed: onSetUp, child: const Text('Record salary')),
        ],
      ),
    );
  }
}
