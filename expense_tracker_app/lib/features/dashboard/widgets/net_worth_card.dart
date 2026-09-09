import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/widgets/animated_money_text.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_transitions.dart';
import '../../../core/widgets/press_scale.dart';
import '../../accounts/accounts_screen.dart';
import '../../lending/lending_screen.dart';

/// The single number that answers "what am I actually worth right now" —
/// account balances plus what's owed to you, minus what you owe. Tapping a
/// breakdown item jumps to the screen that explains it.
class NetWorthCard extends StatelessWidget {
  /// All in paise.
  final int netWorth;
  final int cashBalance;
  final int investments;
  final int emergencyFund;
  final int owedToYou;
  final int youOwe;
  final String currency;

  const NetWorthCard({
    super.key,
    required this.netWorth,
    required this.cashBalance,
    required this.investments,
    required this.emergencyFund,
    required this.owedToYou,
    required this.youOwe,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Net worth', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xs),
          AnimatedMoneyText(
            amountPaise: netWorth,
            currency: currency,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: PressScale(
                  onTap: () =>
                      Navigator.of(context)
                          .push(FadeSlideRoute(page: const AccountsScreen())),
                  child: _NetWorthBreakdownItem(
                    label: 'Cash & bank',
                    value: cashBalance,
                    currency: currency,
                  ),
                ),
              ),
              Expanded(
                child: PressScale(
                  onTap: () =>
                      Navigator.of(context)
                          .push(FadeSlideRoute(page: const AccountsScreen())),
                  child: _NetWorthBreakdownItem(
                    label: 'Investments',
                    value: investments,
                    currency: currency,
                  ),
                ),
              ),
              Expanded(
                child: PressScale(
                  onTap: () =>
                      Navigator.of(context)
                          .push(FadeSlideRoute(page: const AccountsScreen())),
                  child: _NetWorthBreakdownItem(
                    label: 'Emergency fund',
                    value: emergencyFund,
                    currency: currency,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: PressScale(
                  onTap: () =>
                      Navigator.of(context)
                          .push(FadeSlideRoute(page: const LendingScreen())),
                  child: _NetWorthBreakdownItem(
                    label: 'Owed to you',
                    value: owedToYou,
                    currency: currency,
                    color: AppColors.income,
                  ),
                ),
              ),
              Expanded(
                child: PressScale(
                  onTap: () =>
                      Navigator.of(context)
                          .push(FadeSlideRoute(page: const LendingScreen())),
                  child: _NetWorthBreakdownItem(
                    label: 'You owe',
                    value: youOwe,
                    currency: currency,
                    color: youOwe > 0 ? AppColors.expense : null,
                  ),
                ),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }
}

class _NetWorthBreakdownItem extends StatelessWidget {
  final String label;

  /// In paise.
  final int value;
  final String currency;
  final Color? color;

  const _NetWorthBreakdownItem({
    required this.label,
    required this.value,
    required this.currency,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          formatMoney(value, currency),
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}
