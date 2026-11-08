import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/category_icon.dart';
import '../../../core/widgets/page_transitions.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/models/recurring_bill.dart';
import '../../recurring/recurring_controller.dart';
import '../../recurring/recurring_screen.dart';
import '../../settings/settings_controller.dart';

/// The next few recurring bills still to run this month. Read-only — bills
/// are logged from the Recurring screen, never from here.
class UpcomingBills extends StatelessWidget {
  const UpcomingBills({super.key});

  @override
  Widget build(BuildContext context) {
    final recurring = context.watch<RecurringController>();
    final currency = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final now = DateTime.now();
    final month =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final dueIds = recurring.due.map((b) => b.id).toSet();
    final upcoming =
        recurring.bills
            .where((b) => b.active && b.lastRunMonth != month)
            .toList()
          ..sort((a, b) => a.dayOfMonth.compareTo(b.dayOfMonth));
    if (upcoming.isEmpty) return const SizedBox.shrink();

    final p = context.palette;
    final text = Theme.of(context).textTheme;

    String whenLabel(RecurringBill b) {
      if (dueIds.contains(b.id) || b.dayOfMonth <= now.day) return 'Due now';
      final days = b.dayOfMonth - now.day;
      return days == 1 ? 'Tomorrow' : 'In $days days';
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            'Upcoming bills',
            action: 'Manage',
            onAction: () =>
                Navigator.of(context)
                    .push(FadeSlideRoute(page: const RecurringScreen())),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              children: [
                for (final b in upcoming.take(3))
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm - 2,
                    ),
                    child: Row(
                      children: [
                        CategoryIcon(category: b.category, size: 36),
                        const SizedBox(width: AppSpacing.md - 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                b.note?.isNotEmpty == true
                                    ? b.note!
                                    : b.category,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                whenLabel(b),
                                style: text.bodySmall?.copyWith(
                                  color: whenLabel(b) == 'Due now'
                                      ? p.warning
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${b.type == RecurringType.income ? '+' : ''}${formatMoney(b.amountPaise, currency)}',
                          style: text.moneyStyle(
                            15,
                            color: b.type == RecurringType.income
                                ? p.income
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
