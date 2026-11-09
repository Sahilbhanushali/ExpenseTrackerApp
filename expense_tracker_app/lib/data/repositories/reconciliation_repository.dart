import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../../core/finance/salary_cycle.dart';
import '../datasources/app_database.dart';
import '../models/movement.dart';
import 'account_repository.dart';
import 'audit_log.dart';
import 'card_repository.dart';

/// One balance check against the bank. All paise.
class Reconciliation {
  final int id;
  final String ownerType;
  final int ownerId;
  final DateTime asOf;

  /// For an account: the balance. For a card: what's owed.
  final int appBalance;
  final int actualBalance;
  final int? adjustmentMovementId;
  final String? note;

  const Reconciliation({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.asOf,
    required this.appBalance,
    required this.actualBalance,
    this.adjustmentMovementId,
    this.note,
  });

  int get difference => actualBalance - appBalance;
  bool get matched => difference == 0 || adjustmentMovementId != null;
}

/// Checks the app's figures against the bank and, only when the user asks,
/// records the difference as a balance adjustment.
///
/// An adjustment is a movement between the account (or card) and the
/// outside world: it corrects the balance without ever counting as income
/// or spending, and it says so in the history. Every check is kept, matched
/// or not, as the audit trail.
class ReconciliationRepository {
  final AppDatabase _db;
  final AccountRepository _accounts;
  final CardRepository _cards;
  ReconciliationRepository([AppDatabase? db])
    : _db = db ?? AppDatabase.instance,
      _accounts = AccountRepository(db),
      _cards = CardRepository(db);

  static Reconciliation _from(Map<String, Object?> r) => Reconciliation(
    id: r['id'] as int,
    ownerType: r['owner_type'] as String,
    ownerId: r['owner_id'] as int,
    asOf: DateTime.parse(r['as_of'] as String),
    appBalance: r['app_balance'] as int,
    actualBalance: r['actual_balance'] as int,
    adjustmentMovementId: r['adjustment_movement_id'] as int?,
    note: r['note'] as String?,
  );

  Future<List<Reconciliation>> history(String ownerType, int ownerId) async {
    final db = await _db.database;
    final rows = await db.query(
      'reconciliations',
      where: 'owner_type = ? AND owner_id = ?',
      whereArgs: [ownerType, ownerId],
      orderBy: 'as_of DESC, id DESC',
    );
    return rows.map(_from).toList();
  }

  /// The latest check for every account and card: "owner_type:id" → check.
  Future<Map<String, Reconciliation>> latest() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT * FROM reconciliations r WHERE r.id = (SELECT r2.id FROM '
      'reconciliations r2 WHERE r2.owner_type = r.owner_type AND '
      'r2.owner_id = r.owner_id ORDER BY r2.as_of DESC, r2.id DESC LIMIT 1)',
    );
    return {for (final r in rows.map(_from)) '${r.ownerType}:${r.ownerId}': r};
  }

  /// Compares [account]'s balance at the end of [asOf] with the bank's
  /// [actualPaise]. With [adjust] and a difference, a dated adjustment
  /// brings the app in line; otherwise the check is only recorded.
  Future<Reconciliation> reconcileAccount(
    String account, {
    required DateTime asOf,
    required int actualPaise,
    bool adjust = false,
    String? note,
  }) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final acc = await txn.query(
        'accounts',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: [account],
      );
      if (acc.isEmpty) throw StateError('Unknown account');
      final id = acc.first['id'] as int;
      final app = (await _accounts.balanceAsOf(account, asOf, within: txn))!;
      final diff = actualPaise - app;
      int? movementId;
      if (adjust && diff != 0) {
        movementId = await _adjustment(
          txn,
          owner: PostingOwner.account,
          ownerId: id,
          // + raises the account's balance.
          amount: diff,
          date: asOf,
          note: note,
        );
      }
      return _record(
        txn,
        'account',
        id,
        asOf,
        app,
        actualPaise,
        movementId,
        note,
      );
    });
  }

  /// Compares what the app thinks is owed on [cardId] today with the
  /// card's own figure ([actualOwedPaise], from the bank app or statement).
  Future<Reconciliation> reconcileCard(
    int cardId, {
    required int actualOwedPaise,
    bool adjust = false,
    String? note,
    DateTime? today,
  }) async {
    final owed = (await _cards.outstanding())[cardId];
    if (owed == null) throw StateError('Unknown card');
    final asOf = dateOnly(today ?? DateTime.now());
    final db = await _db.database;
    return db.transaction((txn) async {
      final diff = actualOwedPaise - owed;
      int? movementId;
      if (adjust && diff != 0) {
        movementId = await _adjustment(
          txn,
          owner: PostingOwner.card,
          ownerId: cardId,
          // On a card a positive posting lowers what's owed.
          amount: -diff,
          date: asOf,
          note: note,
        );
      }
      return _record(
        txn,
        'card',
        cardId,
        asOf,
        owed,
        actualOwedPaise,
        movementId,
        note,
      );
    });
  }

  static Future<int> _adjustment(
    DatabaseExecutor txn, {
    required PostingOwner owner,
    required int ownerId,
    required int amount,
    required DateTime date,
    String? note,
  }) async {
    final now = DateTime.now().toIso8601String();
    final m = await txn.insert('movements', {
      'ref': AccountRepository.newRef('adjust'),
      'kind': MovementKind.adjustment.name,
      'date': isoDate(date),
      'amount': amount.abs(),
      'status': MovementStatus.completed.name,
      'note': note == null || note.trim().isEmpty
          ? 'Balance adjustment'
          : 'Balance adjustment · ${note.trim()}',
      'created_at': now,
      'completed_at': now,
      'link_type': 'reconciliation',
    });
    await txn.insert(
      'postings',
      Posting(
        movementId: m,
        ownerType: owner,
        ownerId: ownerId,
        amountPaise: amount,
      ).toMap(),
    );
    await txn.insert(
      'postings',
      Posting(
        movementId: m,
        ownerType: PostingOwner.external,
        amountPaise: -amount,
      ).toMap(),
    );
    return m;
  }

  static Future<Reconciliation> _record(
    DatabaseExecutor txn,
    String ownerType,
    int ownerId,
    DateTime asOf,
    int app,
    int actual,
    int? movementId,
    String? note,
  ) async {
    final row = {
      'owner_type': ownerType,
      'owner_id': ownerId,
      'as_of': isoDate(asOf),
      'app_balance': app,
      'actual_balance': actual,
      'difference': actual - app,
      'adjustment_movement_id': movementId,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    };
    final id = await txn.insert('reconciliations', row);
    if (movementId != null) {
      await txn.update(
        'movements',
        {'link_id': id},
        where: 'id = ?',
        whereArgs: [movementId],
      );
    }
    await writeAudit(
      txn,
      entity: 'reconciliation',
      entityId: id,
      action: movementId == null ? 'check' : 'adjust',
      after: row,
    );
    return Reconciliation(
      id: id,
      ownerType: ownerType,
      ownerId: ownerId,
      asOf: asOf,
      appBalance: app,
      actualBalance: actual,
      adjustmentMovementId: movementId,
      note: note,
    );
  }
}
