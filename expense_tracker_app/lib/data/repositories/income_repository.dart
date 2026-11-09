import '../../core/finance/salary_cycle.dart';
import '../datasources/app_database.dart';
import '../models/transaction.dart';
import 'audit_log.dart';

enum ExpectedStatus { pending, received, cancelled }

/// Income you expect but haven't received. Shown separately and never part
/// of any balance until it's marked received, which records a real income
/// transaction.
class ExpectedIncome {
  final int? id;
  final IncomeSource source;
  final int amountPaise;
  final DateTime expectedDate;
  final String? account;
  final String? note;
  final ExpectedStatus status;
  final int? receivedTxnId;

  const ExpectedIncome({
    this.id,
    required this.source,
    required this.amountPaise,
    required this.expectedDate,
    this.account,
    this.note,
    this.status = ExpectedStatus.pending,
    this.receivedTxnId,
  });
}

class IncomeException implements Exception {
  final String message;
  const IncomeException(this.message);
  @override
  String toString() => message;
}

class IncomeRepository {
  final AppDatabase _db;
  IncomeRepository([AppDatabase? db]) : _db = db ?? AppDatabase.instance;

  static ExpectedIncome _from(Map<String, Object?> r) => ExpectedIncome(
    id: r['id'] as int,
    source: incomeSourceFrom(r['source'] as String) ?? IncomeSource.other,
    amountPaise: r['amount'] as int,
    expectedDate: DateTime.parse(r['expected_date'] as String),
    account: r['account'] as String?,
    note: r['note'] as String?,
    status: ExpectedStatus.values.byName(r['status'] as String),
    receivedTxnId: r['received_txn_id'] as int?,
  );

  /// Pending first by date; received/cancelled kept for history.
  Future<List<ExpectedIncome>> list({bool pendingOnly = false}) async {
    final db = await _db.database;
    final rows = await db.query(
      'expected_income',
      where: pendingOnly ? "status = 'pending'" : null,
      orderBy: "status = 'pending' DESC, expected_date ASC",
    );
    return rows.map(_from).toList();
  }

  Future<int> addExpected(ExpectedIncome e) async {
    if (e.amountPaise <= 0) {
      throw const IncomeException('Enter an amount greater than zero.');
    }
    final db = await _db.database;
    return db.transaction((txn) async {
      final row = {
        'source': e.source.name,
        'amount': e.amountPaise,
        'expected_date': isoDate(e.expectedDate),
        'account': e.account,
        'note': e.note,
        'status': ExpectedStatus.pending.name,
        'created_at': DateTime.now().toIso8601String(),
      };
      final id = await txn.insert('expected_income', row);
      await writeAudit(
        txn,
        entity: 'expected_income',
        entityId: id,
        action: 'create',
        after: row,
      );
      return id;
    });
  }

  /// Records what actually arrived — [amountPaise] may differ from what was
  /// expected — as an income transaction, and closes the expectation.
  Future<int> markReceived(
    int id, {
    required int amountPaise,
    required DateTime date,
    String? account,
  }) async {
    if (amountPaise <= 0) {
      throw const IncomeException('Enter the amount you received.');
    }
    final db = await _db.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'expected_income',
        where: "id = ? AND status = 'pending'",
        whereArgs: [id],
      );
      if (rows.isEmpty) {
        throw const IncomeException('That income was already handled.');
      }
      final e = _from(rows.first);
      final txnId = await txn.insert(
        'txns',
        Transaction(
          date: isoDate(date),
          category: e.source.name,
          amountPaise: amountPaise,
          note: e.note ?? incomeSourceLabel(e.source),
          type: TxnType.income,
          createdAt: DateTime.now().toIso8601String(),
          account: account ?? e.account,
          incomeSource: e.source,
        ).toMap()..remove('id'),
      );
      await txn.update(
        'expected_income',
        {'status': ExpectedStatus.received.name, 'received_txn_id': txnId},
        where: 'id = ?',
        whereArgs: [id],
      );
      await writeAudit(
        txn,
        entity: 'expected_income',
        entityId: id,
        action: 'received',
        before: {'amount': e.amountPaise},
        after: {'amount': amountPaise, 'txn_id': txnId},
      );
      return txnId;
    });
  }

  Future<void> cancel(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final n = await txn.update(
        'expected_income',
        {'status': ExpectedStatus.cancelled.name},
        where: "id = ? AND status = 'pending'",
        whereArgs: [id],
      );
      if (n > 0) {
        await writeAudit(
          txn,
          entity: 'expected_income',
          entityId: id,
          action: 'cancel',
        );
      }
    });
  }

  /// Received income in a date range by source. Rows saved before sources
  /// existed count as [IncomeSource.other]. In paise.
  Future<Map<IncomeSource, int>> receivedBySource(
    DateTime from,
    DateTime to,
  ) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      "SELECT income_source, SUM(amount) AS total FROM txns WHERE type = 'income' "
      'AND date >= ? AND date <= ? GROUP BY income_source',
      [isoDate(from), isoDate(to)],
    );
    final out = <IncomeSource, int>{};
    for (final r in rows) {
      final s =
          incomeSourceFrom(r['income_source'] as String?) ?? IncomeSource.other;
      out[s] = (out[s] ?? 0) + ((r['total'] as num?)?.round() ?? 0);
    }
    return out;
  }
}
