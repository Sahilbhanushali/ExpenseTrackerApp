import '../datasources/app_database.dart';
import '../models/loan.dart';

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
    double? principal,
    double? interestAmount,
    double? emiAmount,
    int? tenureMonths,
    String? note,
  }) async {
    final db = await _db.database;
    final fields = <String, Object?>{};
    if (name != null) fields['name'] = name;
    if (principal != null) fields['principal'] = principal;
    if (interestAmount != null) fields['interest_amount'] = interestAmount;
    if (emiAmount != null) fields['emi_amount'] = emiAmount;
    if (tenureMonths != null) fields['tenure_months'] = tenureMonths;
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
