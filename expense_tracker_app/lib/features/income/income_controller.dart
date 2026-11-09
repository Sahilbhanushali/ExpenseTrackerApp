import 'package:flutter/foundation.dart';

import '../../data/models/transaction.dart';
import '../../data/repositories/income_repository.dart';
import '../expenses/expenses_controller.dart';

/// Expected income (not money yet) and received income by source.
class IncomeController extends ChangeNotifier {
  final IncomeRepository _repo;
  IncomeController([IncomeRepository? repo])
    : _repo = repo ?? IncomeRepository();

  ExpensesController? _expenses;

  List<ExpectedIncome> _expected = [];
  List<ExpectedIncome> get expected => _expected;
  List<ExpectedIncome> get pending =>
      _expected.where((e) => e.status == ExpectedStatus.pending).toList();

  /// Shown apart from received money, never added to it. In paise.
  int get pendingTotal => pending.fold(0, (s, e) => s + e.amountPaise);

  void attach(ExpensesController expenses) => _expenses = expenses;

  Future<void> init() => refresh();

  Future<void> refresh() async {
    _expected = await _repo.list();
    notifyListeners();
  }

  Future<Map<IncomeSource, int>> receivedBySource(DateTime from, DateTime to) =>
      _repo.receivedBySource(from, to);

  /// Throws [IncomeException] with a message for the user.
  Future<void> addExpected(ExpectedIncome e) async {
    await _repo.addExpected(e);
    await refresh();
  }

  /// Records the real amount as income; balances and totals update.
  Future<void> markReceived(
    ExpectedIncome e, {
    required int amountPaise,
    required DateTime date,
  }) async {
    await _repo.markReceived(e.id!, amountPaise: amountPaise, date: date);
    await refresh();
    await _expenses?.refresh();
  }

  Future<void> cancel(ExpectedIncome e) async {
    await _repo.cancel(e.id!);
    await refresh();
  }
}
