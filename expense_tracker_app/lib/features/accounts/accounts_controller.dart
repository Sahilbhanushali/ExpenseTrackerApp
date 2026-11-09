import 'package:flutter/foundation.dart';

import '../../data/models/account.dart';
import '../../data/models/movement.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/reconciliation_repository.dart';

class AccountBalance {
  final MoneyAccount account;

  /// In paise.
  final int balance;
  const AccountBalance({required this.account, required this.balance});
}

/// Money pots + transfers — port of bot.py's account_cmd/transfer_cmd.
class AccountsController extends ChangeNotifier {
  final AccountRepository _repo;
  final ReconciliationRepository _recon;
  AccountsController([AccountRepository? repo, ReconciliationRepository? recon])
    : _repo = repo ?? AccountRepository(),
      _recon = recon ?? ReconciliationRepository();

  List<Transfer> _planned = [];

  /// Approved but not yet done at the bank — they don't count yet
  /// (rule 14).
  List<Transfer> get planned => _planned;

  Map<String, Reconciliation> _checks = {};

  /// The latest bank check for an account, if any.
  Reconciliation? lastCheck(MoneyAccount a) => _checks['account:${a.id}'];

  List<AccountBalance> _accounts = [];
  List<AccountBalance> get accounts => _accounts;

  int _unassignedCount = 0;

  /// Transactions not linked to any account, so missing from every balance.
  int get unassignedCount => _unassignedCount;

  Future<void> init() => refresh();

  Future<void> refresh() async {
    // One batched balance query for every account, instead of four queries
    // per account — this runs after every write in the app.
    final list = await _repo.list();
    final balances = await _repo.allBalances();
    _unassignedCount = await _repo.unassignedTxnCount();
    _planned = await _repo.plannedTransfers();
    _checks = await _recon.latest();
    _accounts = [
      for (final a in list)
        AccountBalance(
          account: a,
          balance: balances[a.name] ?? a.openingBalancePaise,
        ),
    ];
    notifyListeners();
  }

  /// Accounts that can receive new money — closed ones keep their history
  /// but leave every picker.
  List<AccountBalance> get active =>
      _accounts.where((a) => a.account.status == AccountStatus.active).toList();

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
    String? bankName,
    String? last4,
    Set<AccountRole>? roles,
    BankType? bankType,
    int holdPaise = 0,
  }) async {
    await _repo.add(
      name,
      openingBalancePaise,
      type: type,
      currentValuePaise: currentValuePaise,
      bankName: bankName,
      last4: last4,
      roles: roles,
      bankType: bankType,
      holdPaise: holdPaise,
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
    String? bankName,
    String? last4,
    Set<AccountRole>? roles,
    AccountStatus? status,
    BankType? bankType,
    int? holdPaise,
  }) async {
    await _repo.update(
      id,
      name: name,
      openingBalancePaise: openingBalancePaise,
      type: type,
      currentValue: currentValue,
      bankName: bankName,
      last4: last4,
      roles: roles,
      status: status,
      bankType: bankType,
      holdPaise: holdPaise,
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

  static Transfer _newTransfer(
    String from,
    String to,
    int amountPaise,
    String? note,
  ) {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return Transfer(
      fromAccount: from,
      toAccount: to,
      amountPaise: amountPaise,
      note: note,
      date: date,
      createdAt: now.toIso8601String(),
    );
  }

  Future<void> transfer(
    String from,
    String to,
    int amountPaise,
    String? note,
  ) async {
    await _repo.addTransfer(_newTransfer(from, to, amountPaise, note));
    await refresh();
  }

  /// Records a transfer that hasn't happened at the bank yet. It changes
  /// no balance until [completeTransfer].
  Future<void> planTransfer(
    String from,
    String to,
    int amountPaise,
    String? note,
  ) async {
    final t = _newTransfer(from, to, amountPaise, note);
    await _repo.addTransfer(
      Transfer(
        fromAccount: t.fromAccount,
        toAccount: t.toAccount,
        amountPaise: t.amountPaise,
        note: t.note,
        date: t.date,
        createdAt: t.createdAt,
        status: MovementStatus.planned,
      ),
    );
    await refresh();
  }

  Future<void> completeTransfer(int movementId) async {
    await _repo.setTransferStatus(movementId, MovementStatus.completed);
    await refresh();
  }

  /// Cancels a transfer or card payment: it stays on record (and in the
  /// audit log) but stops affecting balances. Throws [StateError] for loan
  /// movements, which are undone from the loan.
  Future<void> cancelMovement(int movementId) async {
    await _repo.setTransferStatus(movementId, MovementStatus.cancelled);
    await refresh();
  }

  Future<int?> balanceAsOf(String account, DateTime date) =>
      _repo.balanceAsOf(account, date);

  Future<List<Reconciliation>> checks(MoneyAccount a) =>
      _recon.history('account', a.id!);

  Future<Reconciliation> reconcile(
    String account, {
    required DateTime asOf,
    required int actualPaise,
    bool adjust = false,
    String? note,
  }) async {
    final r = await _recon.reconcileAccount(
      account,
      asOf: asOf,
      actualPaise: actualPaise,
      adjust: adjust,
      note: note,
    );
    await refresh();
    return r;
  }

  /// Several transfers recorded together or not at all.
  Future<void> transferAll(
    List<({String from, String to, int amountPaise, String? note})> moves,
  ) async {
    await _repo.addTransfers([
      for (final m in moves) _newTransfer(m.from, m.to, m.amountPaise, m.note),
    ]);
    await refresh();
  }

  /// Total of active, spendable accounts (no savings/emergency/investment
  /// role). In paise.
  int get spendableTotal => _accounts
      .where((a) => a.account.isSpendable)
      .fold(0, (s, a) => s + a.balance);
}
