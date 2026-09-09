import '../datasources/app_database.dart';
import '../models/loan.dart';
import '../models/transaction.dart';

class LoanRepository {
  final AppDatabase _db;
  LoanRepository([AppDatabase? db]) : _db = db ?? AppDatabase.instance;

  Future<int> add(Loan loan) async {
    final db = await _db.database;
    final map = loan.toMap()..remove('id');
    return db.insert('loans', map);
  }

  Future<List<Loan>> list() async {
    final db = await _db.database;
    final rows = await db.query(
      'loans',
      where: 'active = 1',
      orderBy: 'start_date ASC',
    );
    return rows.map(Loan.fromMap).toList();
  }

  Future<bool> update(
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
    final db = await _db.database;
    final fields = <String, Object?>{};
    if (name != null) fields['name'] = name;
    if (principalPaise != null) fields['principal'] = principalPaise;
    if (interestPaise != null) fields['interest_amount'] = interestPaise;
    if (emiPaise != null) fields['emi_amount'] = emiPaise;
    if (tenureMonths != null) fields['tenure_months'] = tenureMonths;
    if (installmentsPaid != null) {
      fields['installments_paid'] = installmentsPaid;
    }
    if (startDate != null) fields['start_date'] = startDate.toIso8601String();
    if (note != null) fields['note'] = note;
    if (fields.isEmpty) return false;
    final count = await db.update(
      'loans',
      fields,
      where: 'id = ?',
      whereArgs: [id],
    );
    return count > 0;
  }

  Future<bool> remove(int id) async {
    final db = await _db.database;
    final count = await db.update(
      'loans',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    return count > 0;
  }

  /// Logs one EMI installment: the expense, the payment-history row and the
  /// loan's paid count all move together or not at all.
  ///
  /// Previously these were three separate writes from the controller, so a
  /// failure part-way through left the ledger and the loan disagreeing
  /// about how much had been paid.
  ///
  /// Returns true when that was the final installment.
  Future<bool> payInstallment(Loan loan, Transaction expense) async {
    final db = await _db.database;
    return db.transaction<bool>((txn) async {
      final rows = await txn.query(
        'loans',
        columns: ['installments_paid', 'tenure_months'],
        where: 'id = ?',
        whereArgs: [loan.id],
      );
      if (rows.isEmpty) return false;
      final paid = rows.first['installments_paid'] as int;
      final tenure = rows.first['tenure_months'] as int;
      final next = paid + 1;
      final finished = next >= tenure;

      await txn.insert(
        'txns',
        expense.copyWith(loanId: loan.id).toMap()..remove('id'),
      );
      await txn.insert('loan_payments', {
        'loan_id': loan.id,
        'owner_type': LoanPaymentOwner.emiLoan,
        'amount': expense.amountPaise,
        'date': expense.date,
        'note': loan.name,
        'created_at': DateTime.now().toIso8601String(),
      });
      await txn.update(
        'loans',
        {'installments_paid': next, 'active': finished ? 0 : 1},
        where: 'id = ?',
        whereArgs: [loan.id],
      );
      return finished;
    });
  }

  /// Records one EMI installment paid. Deactivates the loan once every
  /// installment across its tenure has been logged. Returns true if this
  /// was the final installment.
  Future<bool> markPaid(int id) async {
    final db = await _db.database;
    final rows = await db.query(
      'loans',
      columns: ['installments_paid', 'tenure_months'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return false;
    final paid = rows.first['installments_paid'] as int;
    final tenure = rows.first['tenure_months'] as int;
    final next = paid + 1;
    final finished = next >= tenure;
    await db.update(
      'loans',
      {'installments_paid': next, 'active': finished ? 0 : 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    return finished;
  }
}
