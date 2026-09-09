import '../datasources/app_database.dart';
import '../models/pending_transaction.dart';

class PendingTransactionRepository {
  final AppDatabase _db;
  PendingTransactionRepository([AppDatabase? db])
    : _db = db ?? AppDatabase.instance;

  /// True when this payment has already been seen — either logged straight
  /// into the ledger, or already queued/handled here. Checked before every
  /// insert so a re-scan of the SMS inbox, or the same payment arriving via
  /// both SMS and a UPI-app notification, can't create a second row.
  Future<bool> isKnown(String externalRef) async {
    final db = await _db.database;
    final logged = await db.query(
      'txns',
      columns: ['id'],
      where: 'external_ref = ?',
      whereArgs: [externalRef],
      limit: 1,
    );
    if (logged.isNotEmpty) return true;

    final queued = await db.query(
      'pending_txns',
      columns: ['id'],
      where: 'external_ref = ?',
      whereArgs: [externalRef],
      limit: 1,
    );
    return queued.isNotEmpty;
  }

  /// Returns the new row id, or null when it was a duplicate.
  Future<int?> add(PendingTransaction pending) async {
    if (await isKnown(pending.externalRef)) return null;
    final db = await _db.database;
    final map = pending.toMap()..remove('id');
    return db.insert('pending_txns', map);
  }

  Future<List<PendingTransaction>> listPending() async {
    final db = await _db.database;
    final rows = await db.query(
      'pending_txns',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'occurred_at DESC, id DESC',
    );
    return rows.map(PendingTransaction.fromMap).toList();
  }

  Future<int> pendingCount() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) as c FROM pending_txns WHERE status = 'pending'",
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> setStatus(int id, String status) async {
    final db = await _db.database;
    await db.update(
      'pending_txns',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Wipes the queue outright, dedupe memory included.
  ///
  /// Used when the detection rules change: keeping dismissed rows would
  /// stop the re-scan from re-examining those same messages under the new
  /// rules, which is the whole point of re-scanning.
  Future<int> clearAll() async {
    final db = await _db.database;
    return db.delete('pending_txns');
  }

  /// Clears handled rows older than [keepDays] so the table doesn't grow
  /// without bound — recent ones stay as dedupe memory.
  Future<void> pruneHandled({int keepDays = 120}) async {
    final db = await _db.database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: keepDays))
        .toIso8601String();
    await db.delete(
      'pending_txns',
      where: "status != 'pending' AND created_at < ?",
      whereArgs: [cutoff],
    );
  }
}
