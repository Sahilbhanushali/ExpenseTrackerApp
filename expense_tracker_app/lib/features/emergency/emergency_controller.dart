import 'package:flutter/foundation.dart';

import '../../core/constants/categories.dart';
import '../../core/finance/wealth.dart';
import '../../data/models/account.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/allocation_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../accounts/accounts_controller.dart';
import '../budgets/budget_controller.dart';

/// The emergency fund: the balance of emergency accounts (counted once,
/// as the bank balance it is) against a target in months of essential
/// spending or a custom amount.
class EmergencyController extends ChangeNotifier {
  final AllocationRepository _settings;
  final TransactionRepository _txns;
  EmergencyController({
    AllocationRepository? settings,
    TransactionRepository? txnRepo,
  }) : _settings = settings ?? AllocationRepository(),
       _txns = txnRepo ?? TransactionRepository();

  AccountsController? _accounts;
  BudgetController? _budgets;

  void attach(AccountsController accounts, BudgetController budgets) {
    _accounts?.removeListener(refresh);
    _budgets?.removeListener(refresh);
    _accounts = accounts..addListener(refresh);
    _budgets = budgets..addListener(refresh);
  }

  AllocationSettings _config = const AllocationSettings();
  AllocationSettings get config => _config;

  EmergencyStatus? _status;
  EmergencyStatus? get status => _status;

  EssentialSource _source = EssentialSource.none;
  EssentialSource get essentialSource => _source;

  List<AccountBalance> get accounts => [
    for (final a in _accounts?.accounts ?? const <AccountBalance>[])
      if (a.account.status == AccountStatus.active &&
          (a.account.roles.contains(AccountRole.emergency) ||
              a.account.type == AccountType.emergencyFund))
        a,
  ];

  /// Average monthly spending on needs over the last three full months
  /// that had any spending. Categories: essential budgets' plus the usual
  /// needs (rent, bills, groceries, health, travel).
  Future<int> _averageEssentialSpending(DateTime today) async {
    final cats = {
      for (final e in kRecommendedAllocation.entries)
        if (e.value.$1 == 'needs') e.key,
      for (final b in _budgets?.budgets ?? const [])
        if (b.essential && b.category != null) b.category!,
    };
    var total = 0, months = 0;
    for (var i = 1; i <= 3; i++) {
      final from = DateTime(today.year, today.month - i, 1);
      final to = DateTime(today.year, today.month - i + 1, 0);
      final byCat = await _txns.categoryTotalsRange(from, to);
      if (byCat.values.every((v) => v <= 0)) continue;
      months++;
      total += cats.fold<int>(0, (s, c) => s + (byCat[c] ?? 0));
    }
    return months == 0 ? 0 : total ~/ months;
  }

  Future<void> refresh() async {
    final today = DateTime.now();
    _config = await _settings.settings();
    final e = essentialMonthly(
      override: _config.essentialMonthly,
      budgets: _budgets?.budgets ?? const [],
      averageEssentialSpending: await _averageEssentialSpending(today),
    );
    _source = e.source;
    _status = EmergencyStatus(
      current: accounts.fold(0, (s, a) => s + a.worth),
      target: emergencyTarget(
        months: _config.emergencyMonths,
        amount: _config.emergencyTarget,
        essentialMonthly: e.amount,
      ),
      essentialMonthly: e.amount,
      monthlyContribution: _config.emergencyMonthly,
    );
    notifyListeners();
  }

  /// Saves the target (months, or a custom amount when [months] is null),
  /// the per-period contribution and an optional essential override.
  /// Smart Money Allocation uses the same settings.
  Future<void> save({
    int? months,
    int? customTarget,
    int? monthlyContribution,
    int? essentialOverride,
  }) async {
    final c = await _settings.settings();
    await _settings.saveSettings(
      AllocationSettings(
        order: c.order,
        savingsPerCycle: c.savingsPerCycle,
        investPerCycle: c.investPerCycle,
        emergencyMonths: months,
        emergencyTarget: months == null ? customTarget : null,
        emergencyMonthly: monthlyContribution,
        essentialMonthly: essentialOverride,
      ),
    );
    await refresh();
  }

  /// Money that left emergency accounts — transfers out and spending —
  /// newest first, as (date, label, amount).
  Future<List<(String, String, int)>> withdrawals() async {
    final out = <(String, String, int)>[];
    for (final a in accounts) {
      final name = a.account.name;
      for (final t in await _accounts!.transfersFor(name)) {
        if (t.fromAccount == name) {
          out.add((t.date, 'To ${t.toAccount}', t.amountPaise));
        }
      }
      for (final t in await _txns.queryPage(
        account: name,
        type: TxnType.expense,
        limit: 50,
      )) {
        out.add((t.date, t.note ?? t.category, t.amountPaise));
      }
    }
    out.sort((a, b) => b.$1.compareTo(a.$1));
    return out;
  }

  @override
  void dispose() {
    _accounts?.removeListener(refresh);
    _budgets?.removeListener(refresh);
    super.dispose();
  }
}
