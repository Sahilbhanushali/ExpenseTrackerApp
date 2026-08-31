import 'package:flutter/foundation.dart';

import '../../core/utils/notification_service.dart';
import '../../data/models/loan_payment.dart';
import '../../data/models/recurring_bill.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/recurring_repository.dart';
import '../../data/repositories/transaction_repository.dart';

/// Lend/borrow tracking — port of bot.py's lend_cmd/borrow_cmd/owed_cmd/
/// settle_cmd/repay_cmd/repayplan_cmd. Loans live in the txns table
/// (type lent/borrowed), same as the bot.
class LendingController extends ChangeNotifier {
  final TransactionRepository _txnRepo;
  final RecurringRepository _recurringRepo;
  final AccountRepository _accountRepo;

  LendingController({
    TransactionRepository? txnRepo,
    RecurringRepository? recurringRepo,
    AccountRepository? accountRepo,
  }) : _txnRepo = txnRepo ?? TransactionRepository(),
       _recurringRepo = recurringRepo ?? RecurringRepository(),
       _accountRepo = accountRepo ?? AccountRepository();

  List<Transaction> _outstanding = [];
  List<Transaction> get outstanding => _outstanding;

  Future<void> init() => refresh();

  Future<void> refresh() async {
    _outstanding = await _txnRepo.outstandingLoans();
    notifyListeners();
  }

  Future<void> lend(double amount, String person, String? note) =>
      _record(TxnType.lent, amount, person, note);
  Future<void> borrow(double amount, String person, String? note) =>
      _record(TxnType.borrowed, amount, person, note);

  Future<void> _record(
    TxnType type,
    double amount,
    String person,
    String? note,
  ) async {
    final account = await _accountRepo.defaultAccount();
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await _txnRepo.add(
      Transaction(
        date: date,
        category: 'lending',
        amount: amount,
        note: note,
        type: type,
        createdAt: now.toIso8601String(),
        counterparty: person,
        settled: 0,
        account: account,
      ),
    );
    await refresh();
  }

  Future<void> update(
    int id, {
    double? amount,
    String? person,
    String? note,
  }) async {
    await _txnRepo.update(id, amount: amount, note: note, counterparty: person);
    await refresh();
  }

  Future<void> remove(int id) async {
    await _txnRepo.deleteById(id);
    await refresh();
  }

  Future<void> settle(int id) async {
    await _txnRepo.settle(id);
    await refresh();
  }

  Future<RepayResult?> repay(int id, double amount) async {
    final result = await _txnRepo.repay(id, amount);
    await refresh();
    return result;
  }

  Future<List<LoanPayment>> paymentHistory(int loanId) =>
      _txnRepo.paymentsFor(loanId);

  /// The loan's original amount, reconstructed from its current outstanding
  /// balance plus everything logged against it so far — works retroactively
  /// even for loans that predate payment history being tracked.
  double originalAmount(Transaction loan, List<LoanPayment> payments) =>
      loan.amount + payments.fold(0.0, (s, p) => s + p.amount);

  /// Schedules automatic monthly repayments against a loan — creates a
  /// recurring row with loan_id set, same as bot.py's repayplan_cmd.
  Future<void> repayPlan(
    int loanId,
    double monthlyAmount, {
    int? months,
    int? dayOfMonth,
  }) async {
    final loan = _outstanding.firstWhere((r) => r.id == loanId);
    final day = dayOfMonth ?? DateTime.now().day;
    final id = await _recurringRepo.add(
      RecurringBill(
        amount: monthlyAmount,
        category: 'lending',
        note: 'repayment to ${loan.counterparty ?? 'them'}',
        dayOfMonth: day,
        installmentsRemaining: months,
        loanId: loanId,
      ),
    );
    await NotificationService.instance.scheduleRecurringReminder(
      billId: id,
      dayOfMonth: day,
      title: 'Repayment due',
      body: 'To ${loan.counterparty ?? 'them'}',
    );
  }
}
