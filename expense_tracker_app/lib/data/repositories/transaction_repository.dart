import '../datasources/app_database.dart';
import '../models/transaction.dart';

class MonthTotal {
  final double expense;
  final double income;
  const MonthTotal({this.expense = 0, this.income = 0});
}

class MonthPoint {
  final String month; // yyyy-MM
  final double income;
  final double expense;
  const MonthPoint({required this.month, this.income = 0, this.expense = 0});
}

class RepayResult {
  final Transaction row;
  final double applied;
  final double overpaid;
  const RepayResult({
    required this.row,
    required this.applied,
    required this.overpaid,
  });
}

/// Port of expense_bot/db.py's transaction-related functions.
class TransactionRepository {
  final AppDatabase _db;
  TransactionRepository([AppDatabase? db]) : _db = db ?? AppDatabase.instance;

  Future<int> add(Transaction txn) async {
    final db = await _db.database;
    return db.insert('txns', txn.toMap()..remove('id'));
  }

  Future<Transaction?> undoLast() async {
    final db = await _db.database;
    final rows = await db.query('txns', orderBy: 'id DESC', limit: 1);
    if (rows.isEmpty) return null;
    final row = Transaction.fromMap(rows.first);
    await db.delete('txns', where: 'id = ?', whereArgs: [row.id]);
    return row;
  }

  Future<void> deleteById(int id) async {
    final db = await _db.database;
    await db.delete('txns', where: 'id = ?', whereArgs: [id]);
  }

  Future<Transaction?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('txns', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Transaction.fromMap(rows.first);
  }

  Future<Transaction?> update(
    int id, {
    double? amount,
    String? category,
    String? note,
    String? counterparty,
  }) async {
    final db = await _db.database;
    final fields = <String, Object?>{};
    if (amount != null) fields['amount'] = amount;
    if (category != null) fields['category'] = category;
    if (note != null) fields['note'] = note;
    if (counterparty != null) fields['counterparty'] = counterparty;
    if (fields.isNotEmpty) {
      await db.update('txns', fields, where: 'id = ?', whereArgs: [id]);
    }
    return getById(id);
  }

  Future<List<Transaction>> allRows() async {
    final db = await _db.database;
    final rows = await db.query('txns', orderBy: 'date ASC, id ASC');
    return rows.map(Transaction.fromMap).toList();
  }

  Future<List<Transaction>> recent({int limit = 10}) async {
    final db = await _db.database;
    final rows = await db.query('txns', orderBy: 'id DESC', limit: limit);
    return rows.map(Transaction.fromMap).toList().reversed.toList();
  }

  Future<MonthTotal> monthTotal(String month) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      "SELECT type, SUM(amount) as total FROM txns WHERE date LIKE ? GROUP BY type",
      ['$month%'],
    );
    double expense = 0, income = 0;
    for (final r in rows) {
      final total = (r['total'] as num?)?.toDouble() ?? 0;
      if (r['type'] == 'expense') expense = total;
      if (r['type'] == 'income') income = total;
    }
    return MonthTotal(expense: expense, income: income);
  }

  /// All-time spare cash: income − expense − outstanding lent money.
  /// Deliberately excludes outstanding borrowed money — that cash is owed,
  /// not saved. Port of db.py's available_savings().
  Future<double> availableSavings() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      "SELECT type, SUM(amount) as total FROM txns GROUP BY type",
    );
    double income = 0, expense = 0, lent = 0;
    for (final r in rows) {
      final total = (r['total'] as num?)?.toDouble() ?? 0;
      if (r['type'] == 'income') income = total;
      if (r['type'] == 'expense') expense = total;
      if (r['type'] == 'lent') lent = total;
    }
    return income - expense - lent;
  }

  /// Income/expense totals for each of the last [months] months (oldest
  /// first, including the current month) — powers the dashboard trend chart.
  Future<List<MonthPoint>> monthlyTrend(int months) async {
    final now = DateTime.now();
    final keys = List.generate(months, (i) {
      final d = DateTime(now.year, now.month - (months - 1 - i));
      return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
    });
    final db = await _db.database;
    final rows = await db.rawQuery(
      "SELECT substr(date, 1, 7) as month, type, SUM(amount) as total FROM txns "
      "WHERE substr(date, 1, 7) >= ? GROUP BY month, type",
      [keys.first],
    );
    final income = <String, double>{};
    final expense = <String, double>{};
    for (final r in rows) {
      final month = r['month'] as String;
      final total = (r['total'] as num?)?.toDouble() ?? 0;
      if (r['type'] == 'income') income[month] = total;
      if (r['type'] == 'expense') expense[month] = total;
    }
    return keys
        .map(
          (k) => MonthPoint(
            month: k,
            income: income[k] ?? 0,
            expense: expense[k] ?? 0,
          ),
        )
        .toList();
  }

  Future<Map<String, double>> categoryTotals(String month) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      "SELECT category, SUM(amount) as total FROM txns WHERE date LIKE ? AND type = 'expense' GROUP BY category",
      ['$month%'],
    );
    return {
      for (final r in rows)
        r['category'] as String: (r['total'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<List<Transaction>> search(String term) async {
    final all = await allRows();
    final lower = term.toLowerCase();
    return all
        .where(
          (r) =>
              (r.note ?? '').toLowerCase().contains(lower) ||
              r.category.toLowerCase().contains(lower),
        )
        .toList();
  }

  Future<List<Transaction>> outstandingLoans() async {
    final db = await _db.database;
    final rows = await db.query(
      'txns',
      where:
          "type IN ('lent', 'borrowed') AND (settled IS NULL OR settled = 0)",
      orderBy: 'date ASC, id ASC',
    );
    return rows.map(Transaction.fromMap).toList();
  }

  Future<Transaction?> settle(int id) async {
    final db = await _db.database;
    final rows = await db.query(
      'txns',
      where: "id = ? AND type IN ('lent', 'borrowed')",
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    await db.update('txns', {'settled': 1}, where: 'id = ?', whereArgs: [id]);
    return getById(id);
  }

  Future<RepayResult?> repay(int id, double repayAmount) async {
    final db = await _db.database;
    final rows = await db.query(
      'txns',
      where: "id = ? AND type IN ('lent', 'borrowed')",
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    final row = Transaction.fromMap(rows.first);
    if (row.isSettled) return null;

    final outstanding = row.amount;
    final applied = repayAmount < outstanding ? repayAmount : outstanding;
    final overpaid = (repayAmount - outstanding) > 0
        ? (repayAmount - outstanding)
        : 0.0;
    final newAmount = outstanding - applied;
    final settled = newAmount <= 0 ? 1 : 0;

    await db.update(
      'txns',
      {'amount': newAmount, 'settled': settled},
      where: 'id = ?',
      whereArgs: [id],
    );
    final updated = await getById(id);
    return RepayResult(row: updated!, applied: applied, overpaid: overpaid);
  }
}
