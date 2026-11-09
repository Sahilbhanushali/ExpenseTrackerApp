import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/widgets/animated_money_text.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_transitions.dart';
import '../../lending/lending_screen.dart';
import '../../allocation/allocation_screen.dart';
import '../../cards/cards_screen.dart';
import '../../emergency/emergency_screen.dart';
import '../../goals/goals_screen.dart';
import '../../investments/investments_screen.dart';
import '../dashboard_controller.dart';
import 'overview_cards.dart';
import '../../loans/loans_screen.dart';
import '../../settings/settings_controller.dart';

/// Net worth headline; actual vs reserved vs available; and what net worth
/// is made of. Reads the dashboard's derived position only.
class NetWorthSection extends StatefulWidget {
  const NetWorthSection({super.key});

  @override
  State<NetWorthSection> createState() => _NetWorthSectionState();
}

class _NetWorthSectionState extends State<NetWorthSection> {
  bool _hidden = false;

  void _open(Widget page) =>
      Navigator.of(context).push(FadeSlideRoute(page: page));

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<DashboardController>().position;
    final currency = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final netWorth = pos.netWorth.total;

    String fmt(int v) => _hidden ? '$currency••••' : formatMoney(v, currency);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Net worth', style: text.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AnimatedMoneyText(
                  amountPaise: netWorth,
                  currency: currency,
                  masked: _hidden,
                  style: text.displaySmall,
                ),
              ),
            ),
            IconButton(
              tooltip: _hidden ? 'Show amounts' : 'Hide amounts',
              onPressed: () => setState(() => _hidden = !_hidden),
              icon: Icon(
                _hidden
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: p.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          onTap: () => _open(const AllocationScreen()),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  FigureColumn(
                    label: 'In bank & cash',
                    value: fmt(pos.inAccounts),
                  ),
                  FigureColumn(label: 'Reserved', value: fmt(pos.reserved)),
                  FigureColumn(
                    label: 'Available',
                    value: fmt(pos.available),
                    color: pos.available < 0 ? p.expense : p.income,
                    end: true,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                pos.onHold > 0
                    ? 'Available = bank & cash − ${fmt(pos.onHold)} on hold − reserved'
                    : 'Available = bank & cash − reserved for bills and plans',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          // Grows with the user's text size so labels never clip.
          height: MediaQuery.textScalerOf(context).scale(40) + 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              if (pos.savings > 0)
                _AssetChip(
                  icon: Icons.savings_outlined,
                  label: 'Savings',
                  value: fmt(pos.savings),
                  color: p.savings,
                  onTap: () => _open(const GoalsScreen()),
                ),
              _AssetChip(
                icon: Icons.shield_outlined,
                label: 'Emergency fund',
                value: fmt(pos.emergency),
                color: p.income,
                onTap: () => _open(const EmergencyScreen()),
              ),
              _AssetChip(
                icon: Icons.trending_up_rounded,
                label: 'Investments',
                value: fmt(pos.investments),
                color: p.debt,
                onTap: () => _open(const InvestmentsScreen()),
              ),
              _AssetChip(
                icon: Icons.call_received_rounded,
                label: 'Owed to you',
                value: fmt(pos.receivables),
                color: p.income,
                onTap: () => _open(const LendingScreen()),
              ),
              _AssetChip(
                icon: Icons.call_made_rounded,
                label: 'You owe',
                value: fmt(pos.borrowed),
                color: pos.borrowed > 0 ? p.expense : p.textSecondary,
                onTap: () => _open(const LendingScreen()),
              ),
              if (pos.cards > 0)
                _AssetChip(
                  icon: Icons.credit_card_rounded,
                  label: 'Credit cards',
                  value: fmt(pos.cards),
                  color: p.expense,
                  onTap: () => _open(const CardsScreen()),
                ),
              if (pos.loans > 0)
                _AssetChip(
                  icon: Icons.account_balance_outlined,
                  label: 'Loans & EMI',
                  value: fmt(pos.loans),
                  color: p.expense,
                  onTap: () => _open(const LoansScreen()),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AssetChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  const _AssetChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: p.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md - 4,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(icon, size: AppIconSize.md, color: color),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: text.bodySmall),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(value, style: text.moneyStyle(15)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
