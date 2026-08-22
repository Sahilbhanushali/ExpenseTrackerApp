import 'package:flutter/foundation.dart';

import '../../data/models/account.dart';
import '../../data/repositories/account_repository.dart';

class AccountBalance {
  final MoneyAccount account;
  final double balance;
  const AccountBalance({required this.account, required this.balance});
}

/// Money pots + transfers — port of bot.py's account_cmd/transfer_cmd.
class AccountsController extends ChangeNotifier {
  final AccountRepository _repo;
  AccountsController([AccountRepository? repo])
    : _repo = repo ?? AccountRepository();

  List<AccountBalance> _accounts = [];
  List<AccountBalance> get accounts => _accounts;

  Future<void> init() => refresh();

  Future<void> refresh() async {
    final list = await _repo.list();
    final withBalances = <AccountBalance>[];
    for (final a in list) {
      final balance = await _repo.balance(a.name) ?? a.openingBalance;
      withBalances.add(AccountBalance(account: a, balance: balance));
    }
    _accounts = withBalances;
    notifyListeners();
  }

  bool nameTaken(String name, {int? excludeId}) => _accounts.any(
    (a) =>
        a.account.id != excludeId &&
        a.account.name.toLowerCase() == name.toLowerCase(),
  );

  Future<void> add(
    String name,
    double openingBalance, {
    AccountType type = AccountType.cash,
    double? currentValue,
  }) async {
    await _repo.add(
      name,
      openingBalance,
      type: type,
      currentValue: currentValue,
    );
    if (_accounts.isEmpty) {
      await _repo.setDefault(name);
    }
    await refresh();
  }

  Future<void> update(
    int id, {
    String? name,
    double? openingBalance,
    AccountType? type,
    Object? currentValue = unsetCurrentValue,
  }) async {
    await _repo.update(
      id,
      name: name,
      openingBalance: openingBalance,
      type: type,
      currentValue: currentValue,
    );
    await refresh();
  }

  /// Sum of balances for accounts of one type — the Dashboard's net worth
  /// breakdown (cash vs. investments vs. emergency fund) instead of one
  /// undifferentiated "Accounts" figure. Investment/emergency-fund accounts
  /// use their marked-up currentValue when set, so gains/losses actually
  /// move net worth instead of only ever reflecting contributions.
  double totalFor(AccountType type) => _accounts
      .where((a) => a.account.type == type)
      .fold(0, (s, a) => s + (a.account.currentValue ?? a.balance));

  Future<void> remove(int id) async {
    await _repo.remove(id);
    await refresh();
  }

  Future<void> setDefault(String name) async {
    await _repo.setDefault(name);
    await refresh();
  }

  Future<void> transfer(
    String from,
    String to,
    double amount,
    String? note,
  ) async {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await _repo.addTransfer(
      Transfer(
        fromAccount: from,
        toAccount: to,
        amount: amount,
        note: note,
        date: date,
        createdAt: now.toIso8601String(),
      ),
    );
    await refresh();
  }
}
