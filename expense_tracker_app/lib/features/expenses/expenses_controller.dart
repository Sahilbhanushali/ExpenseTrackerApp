import 'package:flutter/foundation.dart';

import '../../core/utils/expense_parser.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/transaction_repository.dart';

TxnType _fromParsedType(ParsedTxnType t) => switch (t) {
  ParsedTxnType.expense => TxnType.expense,
  ParsedTxnType.income => TxnType.income,
  ParsedTxnType.lent => TxnType.lent,
  ParsedTxnType.borrowed => TxnType.borrowed,
  ParsedTxnType.repayment => throw StateError(
    'repayment must be routed through LendingController.repay, not addFromParsed',
  ),
  ParsedTxnType.emiPayment => throw StateError(
    'emiPayment must be routed through RecurringController.logDue, not addFromParsed',
  ),
  ParsedTxnType.emiCreate => throw StateError(
    'emiCreate must be routed through RecurringController.logEmi, not addFromParsed',
  ),
};

/// Core ledger — add/edit/undo/search transactions, month + category totals.
/// Wraps TransactionRepository the way bot.py's handle_message/_log_one_transaction do.
class ExpensesController extends ChangeNotifier {
  final TransactionRepository _txnRepo;
  final AccountRepository _accountRepo;
  ExpensesController({
    TransactionRepository? txnRepo,
    AccountRepository? accountRepo,
  }) : _txnRepo = txnRepo ?? TransactionRepository(),
       _accountRepo = accountRepo ?? AccountRepository();

  List<Transaction> _recent = [];
  List<Transaction> get recent => _recent;

  MonthTotal _monthTotal = const MonthTotal();
  MonthTotal get monthTotal => _monthTotal;

  Map<String, int> _categoryTotals = {};

  /// Category → paise.
  Map<String, int> get categoryTotals => _categoryTotals;

  String _currentMonth() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }

  Future<void> init() => refresh();

  Future<void> refresh() async {
    final month = _currentMonth();
    _recent = await _txnRepo.recent(limit: 10);
    _monthTotal = await _txnRepo.monthTotal(month);
    _categoryTotals = await _txnRepo.categoryTotals(month);
    notifyListeners();
  }

  Future<MonthTotal> monthTotalFor(String month) => _txnRepo.monthTotal(month);
  Future<Map<String, int>> categoryTotalsFor(String month) =>
      _txnRepo.categoryTotals(month);
  Future<List<Transaction>> allRows() => _txnRepo.allRows();
  Future<List<Transaction>> search(String term) => _txnRepo.search(term);
  Future<List<MonthPoint>> monthlyTrend(int months) =>
      _txnRepo.monthlyTrend(months);
  Future<List<Transaction>> queryPage({
    int limit = 50,
    int offset = 0,
    TxnType? type,
    String? category,
    DateTime? from,
    DateTime? to,
    String? searchTerm,
  }) => _txnRepo.queryPage(
    limit: limit,
    offset: offset,
    type: type,
    category: category,
    from: from,
    to: to,
    searchTerm: searchTerm,
  );
  Future<List<String>> distinctCategories() => _txnRepo.distinctCategories();
  Future<MonthTotal> totalsRange(DateTime from, DateTime to) =>
      _txnRepo.totalsRange(from, to);
  Future<Map<String, int>> categoryTotalsRange(DateTime from, DateTime to) =>
      _txnRepo.categoryTotalsRange(from, to);
  Future<RecurringCandidate?> detectRecurring(String category, String? note) =>
      _txnRepo.detectRecurring(category, note);

  Future<Transaction> addManual({
    required int amountPaise,
    required String category,
    String? note,
    required TxnType type,
    String? date,
    String? counterparty,
  }) async {
    final account = await _accountRepo.defaultAccount();
    final txn = Transaction(
      date: date ?? _isoToday(),
      category: category,
      amountPaise: amountPaise,
      note: note,
      type: type,
      createdAt: DateTime.now().toIso8601String(),
      counterparty: counterparty,
      settled: type == TxnType.lent || type == TxnType.borrowed ? 0 : null,
      account: account,
    );
    final id = await _txnRepo.add(txn);
    await refresh();
    return txn.copyWith(id: id);
  }

  Future<Transaction> addFromParsed(ParsedTransaction parsed) async {
    return addManual(
      amountPaise: parsed.amountPaise!,
      category: parsed.category,
      note: parsed.note.isEmpty ? null : parsed.note,
      type: _fromParsedType(parsed.type),
      date: parsed.date,
      counterparty: parsed.counterparty,
    );
  }

  Future<Transaction?> undoLast() async {
    final row = await _txnRepo.undoLast();
    await refresh();
    return row;
  }

  Future<Transaction?> edit(
    int id, {
    int? amountPaise,
    String? category,
    String? note,
    String? date,
  }) async {
    final updated = await _txnRepo.update(
      id,
      amountPaise: amountPaise,
      category: category,
      note: note,
      date: date,
    );
    await refresh();
    return updated;
  }

  Future<void> deleteById(int id) async {
    await _txnRepo.deleteById(id);
    await refresh();
  }

  String _isoToday() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
