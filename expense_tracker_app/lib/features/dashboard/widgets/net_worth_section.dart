import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/account.dart';
import '../../../data/models/transaction.dart';
import '../../accounts/accounts_controller.dart';
import '../../lending/lending_controller.dart';
import '../../settings/settings_controller.dart';
import 'net_worth_card.dart';

/// Owns its own subscriptions to accounts + lending, so moving money between
/// accounts repaints this card alone instead of the entire dashboard —
/// charts, lists and all — the way it did when one `build` watched five
/// controllers at once.
class NetWorthSection extends StatelessWidget {
  const NetWorthSection({super.key});

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountsController>();
    final lending = context.watch<LendingController>();
    final currency = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );

    final cash = accounts.totalFor(AccountType.cash);
    final investments = accounts.totalFor(AccountType.investment);
    final emergencyFund = accounts.totalFor(AccountType.emergencyFund);
    final owedToYou = lending.outstanding
        .where((t) => t.type == TxnType.lent)
        .fold<int>(0, (s, t) => s + t.amountPaise);
    final youOwe = lending.outstanding
        .where((t) => t.type == TxnType.borrowed)
        .fold<int>(0, (s, t) => s + t.amountPaise);

    return NetWorthCard(
      netWorth: cash + investments + emergencyFund + owedToYou - youOwe,
      cashBalance: cash,
      investments: investments,
      emergencyFund: emergencyFund,
      owedToYou: owedToYou,
      youOwe: youOwe,
      currency: currency,
    );
  }
}
