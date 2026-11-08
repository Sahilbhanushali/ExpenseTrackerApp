import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/widgets/animated_money_text.dart';
import '../../../core/widgets/page_transitions.dart';
import '../../../data/models/account.dart';
import '../../../data/models/transaction.dart';
import '../../accounts/accounts_controller.dart';
import '../../accounts/accounts_screen.dart';
import '../../expenses/add_transaction_sheet.dart';
import '../../lending/lending_controller.dart';
import '../../lending/lending_screen.dart';
import '../../settings/budget_planner_screen.dart';
import '../../settings/settings_controller.dart';

/// Net worth headline, quick actions and the asset/debt breakdown. Owns its
/// own subscriptions to accounts + lending, so moving money between
/// accounts repaints this block alone.
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
    final accounts = context.watch<AccountsController>();
    final lending = context.watch<LendingController>();
    final currency = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final p = context.palette;
    final text = Theme.of(context).textTheme;

    final cash = accounts.totalFor(AccountType.cash);
    final investments = accounts.totalFor(AccountType.investment);
    final emergencyFund = accounts.totalFor(AccountType.emergencyFund);
    final owedToYou = lending.outstanding
        .where((t) => t.type == TxnType.lent)
        .fold<int>(0, (s, t) => s + t.amountPaise);
    final youOwe = lending.outstanding
        .where((t) => t.type == TxnType.borrowed)
        .fold<int>(0, (s, t) => s + t.amountPaise);
    final netWorth = cash + investments + emergencyFund + owedToYou - youOwe;

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
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            _QuickAction(
              icon: Icons.add_rounded,
              label: 'Add',
              onTap: () => showAddTransactionSheet(context),
            ),
            _QuickAction(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Accounts',
              onTap: () => _open(const AccountsScreen()),
            ),
            _QuickAction(
              icon: Icons.handshake_outlined,
              label: 'Owed',
              onTap: () => _open(const LendingScreen()),
            ),
            _QuickAction(
              icon: Icons.pie_chart_outline_rounded,
              label: 'Budget',
              onTap: () => _open(const BudgetPlannerScreen()),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          // Grows with the user's text size so labels never clip.
          height: MediaQuery.textScalerOf(context).scale(40) + 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              _AssetChip(
                icon: Icons.account_balance_rounded,
                label: 'Cash & bank',
                value: fmt(cash),
                color: p.savings,
                onTap: () => _open(const AccountsScreen()),
              ),
              _AssetChip(
                icon: Icons.trending_up_rounded,
                label: 'Investments',
                value: fmt(investments),
                color: p.debt,
                onTap: () => _open(const AccountsScreen()),
              ),
              _AssetChip(
                icon: Icons.shield_outlined,
                label: 'Emergency fund',
                value: fmt(emergencyFund),
                color: p.income,
                onTap: () => _open(const AccountsScreen()),
              ),
              _AssetChip(
                icon: Icons.call_received_rounded,
                label: 'Owed to you',
                value: fmt(owedToYou),
                color: p.income,
                onTap: () => _open(const LendingScreen()),
              ),
              _AssetChip(
                icon: Icons.call_made_rounded,
                label: 'You owe',
                value: fmt(youOwe),
                color: youOwe > 0 ? p.expense : p.textSecondary,
                onTap: () => _open(const LendingScreen()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                Container(
                  height: 52,
                  constraints: const BoxConstraints(maxWidth: 72),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: p.border),
                  ),
                  child: Center(child: Icon(icon, color: p.textPrimary)),
                ),
                const SizedBox(height: AppSpacing.sm - 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: p.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
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
