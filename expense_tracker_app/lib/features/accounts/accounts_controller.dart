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
  AccountsController([AccountRepository? repo]) : _repo = repo ?? AccountRepository();

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

  bool nameTaken(String name) =>
      _accounts.any((a) => a.account.name.toLowerCase() == name.toLowerCase());

  Future<void> add(String name, double openingBalance) async {
    await _repo.add(name, openingBalance);
    if (_accounts.isEmpty) {
      await _repo.setDefault(name);
    }
    await refresh();
  }

  Future<void> setDefault(String name) async {
    await _repo.setDefault(name);
    await refresh();
  }

  Future<void> transfer(String from, String to, double amount, String? note) async {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await _repo.addTransfer(
      Transfer(fromAccount: from, toAccount: to, amount: amount, note: note, date: date, createdAt: now.toIso8601String()),
    );
    await refresh();
  }
}
