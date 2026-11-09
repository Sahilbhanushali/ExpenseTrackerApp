import 'package:flutter/foundation.dart';

import '../../core/finance/loans.dart';
import '../../data/models/loan.dart';
import '../../data/datasources/app_database.dart';
import '../../data/models/loan_payment.dart';
import '../../data/repositories/loan_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../expenses/expenses_controller.dart';

/// Loans and EMIs with their schedules. Every write refreshes the ledger
/// too, since payments move account balances and log interest.
class LoansController extends ChangeNotifier {
  final LoanRepository _repo;
  final TransactionRepository _txnRepo;
  LoansController({LoanRepository? loanRepo, TransactionRepository? txnRepo})
    : _repo = loanRepo ?? LoanRepository(),
      _txnRepo = txnRepo ?? TransactionRepository();

  ExpensesController? _expenses;
  void attach(ExpensesController expenses) => _expenses = expenses;

  List<LoanStanding> _loans = [];

  /// Newest first, closed ones included.
  List<LoanStanding> get loans => _loans;
  List<LoanStanding> get active => _loans.where((l) => !l.closed).toList();

  /// Principal still owed across active loans — the liability in net
  /// worth. In paise.
  int get outstanding => active.fold(0, (s, l) => s + l.outstandingPrincipal);

  Future<void> init() => refresh();

  Future<void> refresh() async {
    _loans = await _repo.standings();
    notifyListeners();
  }

  Future<void> _changed() async {
    await refresh();
    await _expenses?.refresh();
  }

  /// Throws [LoanException] with a message for the user.
  Future<void> add(Loan loan, {String purchaseCategory = 'other'}) async {
    await _repo.add(loan, purchaseCategory: purchaseCategory);
    await _changed();
  }

  Future<LoanPaymentResult> payInstallment(
    LoanStanding l, {
    int? amountPaise,
    required String account,
    DateTime? date,
  }) async {
    final r = await _repo.payInstallment(
      l.loan.id!,
      amountPaise: amountPaise,
      date: date ?? DateTime.now(),
      account: account,
    );
    await _changed();
    return r;
  }

  Future<void> prepay(
    LoanStanding l, {
    required int amountPaise,
    required String account,
    PrepayMode mode = PrepayMode.reduceTenure,
  }) async {
    await _repo.prepay(
      l.loan.id!,
      amountPaise: amountPaise,
      date: DateTime.now(),
      account: account,
      mode: mode,
    );
    await _changed();
  }

  Future<void> foreclose(
    LoanStanding l, {
    required String account,
    int chargesPaise = 0,
  }) async {
    await _repo.foreclose(
      l.loan.id!,
      date: DateTime.now(),
      account: account,
      chargesPaise: chargesPaise,
    );
    await _changed();
  }

  Future<void> correct(LoanStanding l, int outstanding, {String? note}) async {
    await _repo.correctOutstanding(l.loan.id!, outstanding, note: note);
    await _changed();
  }

  Future<bool> undoLastPayment(LoanStanding l) async {
    final undone = await _repo.undoLastPayment(l.loan.id!);
    if (undone) await _changed();
    return undone;
  }

  Future<void> remove(LoanStanding l) async {
    await _repo.remove(l.loan.id!);
    await refresh();
  }

  /// Installments paid on this loan, newest first.
  Future<List<LoanPayment>> paymentsFor(LoanStanding l) =>
      _txnRepo.paymentsFor(l.loan.id!, ownerType: LoanPaymentOwner.emiLoan);
}
