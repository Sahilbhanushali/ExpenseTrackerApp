import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/section_header.dart';
import '../dashboard/widgets/category_tiles.dart';
import '../dashboard/widgets/month_summary_section.dart';
import '../dashboard/widgets/upcoming_bills.dart';
import '../settings/settings_controller.dart';
import 'cycle_card.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CycleCard(summary: summary, currency: currency),
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
        if (summary.cycle.isOpen) const UpcomingBills(),
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
