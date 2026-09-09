import '../datasources/app_database.dart';
import '../models/loan_payment.dart';
import '../models/transaction.dart';

class MonthTotal {
  /// Both in paise.
  final int expense;
  final int income;
  const MonthTotal({this.expense = 0, this.income = 0});
}

class MonthPoint {
  final String month; // yyyy-MM
  /// Both in paise.
  final int income;
  final int expense;
  const MonthPoint({required this.month, this.income = 0, this.expense = 0});
}

class RecurringCandidate {
  final String category;
  final String? note;

  /// In paise.
  final int avgAmountPaise;
  final int dayOfMonth;
  const RecurringCandidate({
    required this.category,
    this.note,
    required this.avgAmountPaise,
    required this.dayOfMonth,
  });
}

class RepayResult {
  final Transaction row;

  /// Both in paise.
  final int applied;
  final int overpaid;
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
    await deleteById(row.id!);
    return row;
  }

  /// Deletes a transaction and rolls back whatever it was linked to.
  ///
  /// An EMI installment doesn't just add an expense — it also advances the
  /// loan's paid count and writes a payment-history row. Deleting only the
  /// expense used to leave the loan permanently one installment ahead of
  /// what was actually paid, so all three are undone together, atomically.
  /// Deletes every transaction that came from automatic detection rather
  /// than from the user, e.g. everything SMS import wrote.
  ///
  /// Scoped by `source` so hand-entered rows are never touched, and loans
  /// are left alone — an auto-detected row never carries a loan_id, so
  /// there is no installment count to roll back the way [deleteById] does.
  Future<int> deleteBySource(String source) async {
    final db = await _db.database;
    return db.delete(
      'txns',
      where: 'source = ? AND loan_id IS NULL',
      whereArgs: [source],
    );
  }

  Future<void> deleteById(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query('txns', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) return;
      final row = Transaction.fromMap(rows.first);

      await txn.delete('txns', where: 'id = ?', whereArgs: [id]);

      final loanId = row.loanId;
      if (loanId == null) return;

      await txn.rawUpdate(
        'UPDATE loans SET installments_paid = MAX(installments_paid - 1, 0), '
        'active = 1 WHERE id = ?',
        [loanId],
      );
      await txn.delete(
        'loan_payments',
        where: 'owner_type = ? AND loan_id = ? AND amount = ? AND date = ?',
        whereArgs: [
          LoanPaymentOwner.emiLoan,
          loanId,
          row.amountPaise,
          row.date,
        ],
      );
    });
  }

  Future<Transaction?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('txns', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Transaction.fromMap(rows.first);
  }

  Future<Transaction?> update(
    int id, {
    int? amountPaise,
    String? category,
    String? note,
    String? counterparty,
    String? date,
  }) async {
    final db = await _db.database;
    final fields = <String, Object?>{};
    if (amountPaise != null) fields['amount'] = amountPaise;
    if (category != null) fields['category'] = category;
    if (note != null) fields['note'] = note;
    if (counterparty != null) fields['counterparty'] = counterparty;
    if (date != null) fields['date'] = date;
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

  /// Paginated, filterable, newest-first — powers the transactions screen's
  /// infinite-scroll list instead of loading the whole table at once.
  Future<List<Transaction>> queryPage({
    int limit = 50,
    int offset = 0,
    TxnType? type,
    String? category,
    DateTime? from,
    DateTime? to,
    String? searchTerm,
  }) async {
    final db = await _db.database;
    final where = <String>[];
    final args = <Object?>[];

    if (type != null) {
      where.add('type = ?');
      args.add(type.name);
    }
    if (category != null) {
      where.add('category = ?');
      args.add(category);
    }
    if (from != null) {
      where.add('date >= ?');
      args.add(_isoDate(from));
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(_isoDate(to));
    }
    if (searchTerm != null && searchTerm.trim().isNotEmpty) {
      where.add('(note LIKE ? OR category LIKE ?)');
      final like = '%${searchTerm.trim()}%';
      args.addAll([like, like]);
    }

    final rows = await db.query(
      'txns',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(Transaction.fromMap).toList();
  }

  Future<List<String>> distinctCategories() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT category FROM txns ORDER BY category ASC',
    );
    return rows.map((r) => r['category'] as String).toList();
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
    int expense = 0, income = 0;
    for (final r in rows) {
      final total = (r['total'] as num?)?.round() ?? 0;
      if (r['type'] == 'expense') expense = total;
      if (r['type'] == 'income') income = total;
    }
    return MonthTotal(expense: expense, income: income);
  }

  /// All-time spare cash: income − expense − outstanding lent money.
  /// Deliberately excludes outstanding borrowed money — that cash is owed,
  /// not saved. Port of db.py's available_savings().
  /// In paise.
  Future<int> availableSavings() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      "SELECT type, SUM(amount) as total FROM txns GROUP BY type",
    );
    int income = 0, expense = 0, lent = 0;
    for (final r in rows) {
      final total = (r['total'] as num?)?.round() ?? 0;
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
    final income = <String, int>{};
    final expense = <String, int>{};
    for (final r in rows) {
      final month = r['month'] as String;
      final total = (r['total'] as num?)?.round() ?? 0;
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

  /// Category → paise.
  Future<Map<String, int>> categoryTotals(String month) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      "SELECT category, SUM(amount) as total FROM txns WHERE date LIKE ? AND type = 'expense' GROUP BY category",
      ['$month%'],
    );
    return {
      for (final r in rows)
        r['category'] as String: (r['total'] as num?)?.round() ?? 0,
    };
  }

  /// Income/expense totals between two dates (inclusive) — powers custom
  /// date-range reports, unlike [monthTotal] which is locked to one month.
  Future<MonthTotal> totalsRange(DateTime from, DateTime to) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      "SELECT type, SUM(amount) as total FROM txns WHERE date >= ? AND date <= ? GROUP BY type",
      [_isoDate(from), _isoDate(to)],
    );
    int expense = 0, income = 0;
    for (final r in rows) {
      final total = (r['total'] as num?)?.round() ?? 0;
      if (r['type'] == 'expense') expense = total;
      if (r['type'] == 'income') income = total;
    }
    return MonthTotal(expense: expense, income: income);
  }

  /// Category → paise.
  Future<Map<String, int>> categoryTotalsRange(
    DateTime from,
    DateTime to,
  ) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      "SELECT category, SUM(amount) as total FROM txns WHERE date >= ? AND date <= ? AND type = 'expense' GROUP BY category",
      [_isoDate(from), _isoDate(to)],
    );
    return {
      for (final r in rows)
        r['category'] as String: (r['total'] as num?)?.round() ?? 0,
    };
  }

  /// Heuristic: the same category+note expense logged in 3+ of the last 4
  /// months, with amounts within 15% of each other, looks like a recurring
  /// bill (subscription, rent, etc.) the user hasn't set up a reminder for.
  Future<RecurringCandidate?> detectRecurring(
    String category,
    String? note,
  ) async {
    final db = await _db.database;
    final now = DateTime.now();
    final since = DateTime(now.year, now.month - 3, 1);
    final rows = await db.query(
      'txns',
      where: note == null
          ? "type = 'expense' AND category = ? AND note IS NULL AND date >= ?"
          : "type = 'expense' AND category = ? AND note = ? AND date >= ?",
      whereArgs: note == null
          ? [category, _isoDate(since)]
          : [category, note, _isoDate(since)],
      orderBy: 'date ASC',
    );
    if (rows.length < 3) return null;

    final txns = rows.map(Transaction.fromMap).toList();
    final months = txns.map((t) => t.date.substring(0, 7)).toSet();
    if (months.length < 3) return null;

    final amounts = txns.map((t) => t.amountPaise).toList();
    final avgPaise = amounts.reduce((a, b) => a + b) ~/ amounts.length;
    if (avgPaise <= 0) return null;
    final maxDeviation = amounts
        .map((a) => (a - avgPaise).abs() / avgPaise)
        .reduce((a, b) => a > b ? a : b);
    if (maxDeviation > 0.15) return null;

    final days = txns.map((t) => int.parse(t.date.substring(8, 10))).toList()
      ..sort();
    return RecurringCandidate(
      category: category,
      note: note,
      avgAmountPaise: avgPaise,
      dayOfMonth: days[days.length ~/ 2],
    );
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

  Future<RepayResult?> repay(int id, int repayPaise) async {
    final db = await _db.database;
    final rows = await db.query(
      'txns',
      where: "id = ? AND type IN ('lent', 'borrowed')",
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    final row = Transaction.fromMap(rows.first);
    if (row.isSettled) return null;

    final outstanding = row.amountPaise;
    final applied = repayPaise < outstanding ? repayPaise : outstanding;
    final overpaid = (repayPaise - outstanding) > 0
        ? (repayPaise - outstanding)
        : 0;
    final newAmount = outstanding - applied;
    final settled = newAmount <= 0 ? 1 : 0;

    await db.update(
      'txns',
      {'amount': newAmount, 'settled': settled},
      where: 'id = ?',
      whereArgs: [id],
    );
    await db.insert('loan_payments', {
      'loan_id': id,
      'owner_type': LoanPaymentOwner.personLoan,
      'amount': applied,
      'date': _isoDate(DateTime.now()),
      'note': null,
      'created_at': DateTime.now().toIso8601String(),
    });
    final updated = await getById(id);
    return RepayResult(row: updated!, applied: applied, overpaid: overpaid);
  }

  /// History of individual installments logged against a loan, newest first
  /// — [repay] writes one row here every time it's called, so this survives
  /// even though the loan's own `amount` column just holds the live balance.
  Future<List<LoanPayment>> paymentsFor(
    int loanId, {
    String ownerType = LoanPaymentOwner.personLoan,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'loan_payments',
      // owner_type is essential, not optional: person-loan ids come from
      // `txns` and EMI ids from `loans`, so the same number means two
      // different loans depending on which table it came from.
      where: 'owner_type = ? AND loan_id = ?',
      whereArgs: [ownerType, loanId],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(LoanPayment.fromMap).toList();
  }
}
