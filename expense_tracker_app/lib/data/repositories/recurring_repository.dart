import '../datasources/app_database.dart';
import '../models/recurring_bill.dart';

/// Port of expense_bot/db.py's recurring-bill functions.
class RecurringRepository {
  final AppDatabase _db;
  RecurringRepository([AppDatabase? db]) : _db = db ?? AppDatabase.instance;

  Future<int> add(RecurringBill bill) async {
    final db = await _db.database;
    final map = bill.toMap()..remove('id');
    return db.insert('recurring', map);
  }

  Future<List<RecurringBill>> list() async {
    final db = await _db.database;
    final rows = await db.query(
      'recurring',
      where: 'active = 1',
      orderBy: 'day_of_month ASC',
    );
    return rows.map(RecurringBill.fromMap).toList();
  }

  Future<bool> update(
    int id, {
    double? amount,
    String? category,
    String? note,
    int? dayOfMonth,
  }) async {
    final db = await _db.database;
    final fields = <String, Object?>{};
    if (amount != null) fields['amount'] = amount;
    if (category != null) fields['category'] = category;
    if (note != null) fields['note'] = note;
    if (dayOfMonth != null) fields['day_of_month'] = dayOfMonth;
    if (fields.isEmpty) return false;
    final count = await db.update(
      'recurring',
      fields,
      where: 'id = ?',
      whereArgs: [id],
    );
    return count > 0;
  }

  Future<bool> remove(int id) async {
    final db = await _db.database;
    final rows = await db.query('recurring', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return false;
    await db.update(
      'recurring',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    return true;
  }

  /// Active entries whose day_of_month has arrived and haven't fired this month.
  Future<List<RecurringBill>> due(DateTime today) async {
    final db = await _db.database;
    final month = _monthKey(today);
    final rows = await db.query(
      'recurring',
      where: 'active = 1 AND day_of_month <= ? AND (last_run_month IS NULL OR last_run_month != ?)',
      whereArgs: [today.day, month],
    );
    return rows.map(RecurringBill.fromMap).toList();
  }

  /// Stamps a bill as fired for `month`. Decrements installments_remaining
  /// when set and deactivates once it hits 0. Returns true if this was the
  /// final installment.
  Future<bool> markRun(int id, String month) async {
    final db = await _db.database;
    final rows = await db.query(
      'recurring',
      columns: ['installments_remaining'],
      where: 'id = ?',
      whereArgs: [id],
    );
    final remaining = rows.isNotEmpty
        ? rows.first['installments_remaining'] as int?
        : null;

    if (remaining == null) {
      await db.update(
        'recurring',
        {'last_run_month': month},
        where: 'id = ?',
        whereArgs: [id],
      );
      return false;
    }

    final next = remaining - 1;
    final finished = next <= 0;
    await db.update(
      'recurring',
      {
        'last_run_month': month,
        'installments_remaining': next,
        'active': finished ? 0 : 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return finished;
  }

  String _monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
}
