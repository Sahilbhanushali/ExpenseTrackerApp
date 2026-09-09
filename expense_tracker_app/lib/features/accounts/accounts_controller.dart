import 'package:flutter/foundation.dart';

import '../../data/models/account.dart';
import '../../data/repositories/account_repository.dart';

class AccountBalance {
  final MoneyAccount account;

  /// In paise.
  final int balance;
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
    // One batched balance query for every account, instead of four queries
    // per account — this runs after every write in the app.
    final list = await _repo.list();
    final balances = await _repo.allBalances();
    _accounts = [
      for (final a in list)
        AccountBalance(
          account: a,
          balance: balances[a.name] ?? a.openingBalancePaise,
        ),
    ];
    notifyListeners();
  }

  bool nameTaken(String name, {int? excludeId}) => _accounts.any(
    (a) =>
        a.account.id != excludeId &&
        a.account.name.toLowerCase() == name.toLowerCase(),
  );

  Future<void> add(
    String name,
    int openingBalancePaise, {
    AccountType type = AccountType.cash,
    int? currentValuePaise,
  }) async {
    await _repo.add(
      name,
      openingBalancePaise,
      type: type,
      currentValuePaise: currentValuePaise,
    );
    if (_accounts.isEmpty) {
      await _repo.setDefault(name);
    }
    await refresh();
  }

  Future<void> update(
    int id, {
    String? name,
    int? openingBalancePaise,
    AccountType? type,
    Object? currentValue = unsetCurrentValue,
  }) async {
    await _repo.update(
      id,
      name: name,
      openingBalancePaise: openingBalancePaise,
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
  /// In paise.
  int totalFor(AccountType type) => _accounts
      .where((a) => a.account.type == type)
      .fold(0, (s, a) => s + (a.account.currentValuePaise ?? a.balance));

  /// Number of transactions/transfers that would be orphaned by deleting
  /// this account — the UI uses it to ask where they should go.
  Future<int> linkedRecordCount(String name) => _repo.linkedRecordCount(name);

  /// Returns false when the account still has history and no [reassignTo]
  /// was given, rather than silently orphaning it.
  Future<bool> remove(int id, {String? reassignTo}) async {
    final removed = await _repo.remove(id, reassignTo: reassignTo);
    if (removed) await refresh();
    return removed;
  }

  Future<void> setDefault(String name) async {
    await _repo.setDefault(name);
    await refresh();
  }

  Future<void> transfer(
    String from,
    String to,
    int amountPaise,
    String? note,
  ) async {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await _repo.addTransfer(
      Transfer(
        fromAccount: from,
        toAccount: to,
        amountPaise: amountPaise,
        note: note,
        date: date,
        createdAt: now.toIso8601String(),
      ),
    );
    await refresh();
  }
}
