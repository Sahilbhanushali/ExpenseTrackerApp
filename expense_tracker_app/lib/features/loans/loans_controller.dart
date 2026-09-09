import 'package:flutter/foundation.dart';

import '../../data/datasources/app_database.dart';
import '../../data/models/loan.dart';
import '../../data/models/loan_payment.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/loan_repository.dart';
import '../../data/repositories/transaction_repository.dart';

/// Interest-bearing installment loans (bank loans, card EMIs). Separate from
/// [RecurringController], which only handles flat no-interest installments.
class LoansController extends ChangeNotifier {
  final LoanRepository _loanRepo;
  final TransactionRepository _txnRepo;
  final AccountRepository _accountRepo;

  LoansController({
    LoanRepository? loanRepo,
    TransactionRepository? txnRepo,
    AccountRepository? accountRepo,
  }) : _loanRepo = loanRepo ?? LoanRepository(),
       _txnRepo = txnRepo ?? TransactionRepository(),
       _accountRepo = accountRepo ?? AccountRepository();

  List<Loan> _loans = [];
  List<Loan> get loans => _loans;

  Future<void> init() => refresh();

  Future<void> refresh() async {
    _loans = await _loanRepo.list();
    notifyListeners();
  }

  Future<void> addLoan({
    required String name,
    required int principalPaise,
    required int interestPaise,
    required int emiPaise,
    required int tenureMonths,
    required DateTime startDate,
    String? note,
  }) async {
    final account = await _accountRepo.defaultAccount();
    await _loanRepo.add(
      Loan(
        name: name,
        principalPaise: principalPaise,
        interestPaise: interestPaise,
        emiPaise: emiPaise,
        tenureMonths: tenureMonths,
        startDate: startDate,
        note: note,
        account: account,
      ),
    );
    await refresh();
  }

  Future<void> update(
    int id, {
    String? name,
    int? principalPaise,
    int? interestPaise,
    int? emiPaise,
    int? tenureMonths,
    int? installmentsPaid,
    DateTime? startDate,
    String? note,
  }) async {
    await _loanRepo.update(
      id,
      name: name,
      principalPaise: principalPaise,
      interestPaise: interestPaise,
      emiPaise: emiPaise,
      tenureMonths: tenureMonths,
      installmentsPaid: installmentsPaid,
      startDate: startDate,
      note: note,
    );
    await refresh();
  }

  Future<void> remove(int id) async {
    await _loanRepo.remove(id);
    await refresh();
  }

  /// Logs one EMI installment as an expense transaction and advances the
  /// loan's paid count.
  Future<bool> payInstallment(Loan loan) async {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    // One atomic write: expense + payment history + paid count.
    final finished = await _loanRepo.payInstallment(
      loan,
      Transaction(
        date: date,
        category: 'EMI',
        amountPaise: loan.emiPaise,
        note: loan.name,
        type: TxnType.expense,
        createdAt: now.toIso8601String(),
        account: loan.account,
      ),
    );
    await refresh();
    return finished;
  }

  /// Installments logged against this loan, newest first.
  Future<List<LoanPayment>> paymentsFor(Loan loan) =>
      _txnRepo.paymentsFor(loan.id!, ownerType: LoanPaymentOwner.emiLoan);
}
