import '../../core/finance/allocation.dart';
import '../datasources/app_database.dart';
import '../models/account.dart';
import '../models/movement.dart';
import 'account_repository.dart';
import 'audit_log.dart';

class AllocationSettings {
  final List<AllocBucket> order;

  /// All paise; null means "not set" (that bucket asks for nothing).
  final int? emergencyTarget;
  final int? emergencyMonthly;
  final int? savingsPerCycle;
  final int? investPerCycle;

  /// Emergency target as months of essential spending (3, 6, 9, 12…);
  /// when set it replaces [emergencyTarget].
  final int? emergencyMonths;

  /// Essential spending per month entered by hand, overriding budgets and
  /// past spending.
  final int? essentialMonthly;

  const AllocationSettings({
    this.emergencyMonths,
    this.essentialMonthly,
    this.order = kDefaultAllocationOrder,
    this.emergencyTarget,
    this.emergencyMonthly,
    this.savingsPerCycle,
    this.investPerCycle,
  });
}

enum DecisionStatus { reserved, transferred, skipped }

/// A decision the user made about one need in one period. All paise.
class AllocationDecision {
  final int id;
  final String scope;
  final String key;
  final AllocBucket bucket;
  final String label;
  final int amount;
  final String? destination;
  final String? source;
  final DecisionStatus status;

  /// The planned (or completed) transfer, when money had to move.
  final int? movementId;

  const AllocationDecision({
    required this.id,
    required this.scope,
    required this.key,
    required this.bucket,
    required this.label,
    required this.amount,
    required this.status,
    this.destination,
    this.source,
    this.movementId,
  });
}

class AllocationException implements Exception {
  final String message;
  const AllocationException(this.message);
  @override
  String toString() => message;
}

/// Allocation settings and the user's decisions. Approving never moves
/// money: at most it records a *planned* transfer, which only counts once
/// marked done at the bank (rule 14).
class AllocationRepository {
  final AppDatabase _db;
  final AccountRepository _accounts;
  AllocationRepository([AppDatabase? db])
    : _db = db ?? AppDatabase.instance,
      _accounts = AccountRepository(db);

  Future<AllocationSettings> settings() async {
    final db = await _db.database;
    final r = await db.query('allocation_settings', where: 'id = 1');
    if (r.isEmpty) return const AllocationSettings();
    final names = (r.first['priority_order'] as String).split(',');
    final order = [
      for (final n in names)
        ...AllocBucket.values.where(
          (b) => b.name == n && b != AllocBucket.buffer,
        ),
    ];
    return AllocationSettings(
      order: order.isEmpty ? kDefaultAllocationOrder : order,
      emergencyTarget: r.first['emergency_target'] as int?,
      emergencyMonthly: r.first['emergency_monthly'] as int?,
      savingsPerCycle: r.first['savings_per_cycle'] as int?,
      investPerCycle: r.first['invest_per_cycle'] as int?,
      emergencyMonths: r.first['emergency_months'] as int?,
      essentialMonthly: r.first['essential_monthly'] as int?,
    );
  }

  Future<void> saveSettings(AllocationSettings s) async {
    for (final v in [
      s.emergencyTarget,
      s.emergencyMonthly,
      s.savingsPerCycle,
      s.investPerCycle,
      s.emergencyMonths,
      s.essentialMonthly,
    ]) {
      if (v != null && v < 0) {
        throw const AllocationException("Amounts can't be negative.");
      }
    }
    final row = {
      'id': 1,
      'priority_order': s.order.map((b) => b.name).join(','),
      'emergency_target': s.emergencyTarget,
      'emergency_monthly': s.emergencyMonthly,
      'savings_per_cycle': s.savingsPerCycle,
      'invest_per_cycle': s.investPerCycle,
      'emergency_months': s.emergencyMonths,
      'essential_monthly': s.essentialMonthly,
    };
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete('allocation_settings', where: 'id = 1');
      await txn.insert('allocation_settings', row);
      await writeAudit(
        txn,
        entity: 'allocation_settings',
        entityId: 1,
        action: 'save',
        after: row,
      );
    });
  }

  static AllocationDecision _from(Map<String, Object?> r) => AllocationDecision(
    id: r['id'] as int,
    scope: r['scope'] as String,
    key: r['need_key'] as String,
    bucket: AllocBucket.values.byName(r['bucket'] as String),
    label: r['label'] as String,
    amount: r['amount'] as int,
    destination: r['destination'] as String?,
    source: r['source'] as String?,
    status: DecisionStatus.values.byName(r['status'] as String),
    movementId: r['movement_id'] as int?,
  );

  Future<List<AllocationDecision>> decisions(String scope) async {
    final db = await _db.database;
    final rows = await db.query(
      'allocation_decisions',
      where: 'scope = ?',
      whereArgs: [scope],
      orderBy: 'id',
    );
    return rows.map(_from).toList();
  }

  /// Sets money aside for [need]. When [moveFrom] is given (money has to go
  /// to a different account), a planned transfer is recorded with it — it
  /// changes no balance until it's marked done.
  Future<void> reserve(
    String scope,
    AllocationNeed need, {
    required int amount,
    String? destination,
    String? moveFrom,
    int? transferPaise,
  }) async {
    if (amount <= 0) {
      throw const AllocationException('Enter an amount greater than zero.');
    }
    final move = transferPaise ?? amount;
    if (moveFrom != null && (move <= 0 || move > amount)) moveFrom = null;
    if (moveFrom != null && destination == null) {
      throw const AllocationException('Pick where the money should go.');
    }
    if (moveFrom != null && moveFrom == destination) moveFrom = null;
    final db = await _db.database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'allocation_decisions',
        where: 'scope = ? AND need_key = ?',
        whereArgs: [scope, need.key],
      );
      if (existing.isNotEmpty && existing.first['status'] != 'skipped') {
        throw const AllocationException(
          'That’s already reserved. Release it to change it.',
        );
      }
      await txn.delete(
        'allocation_decisions',
        where: 'scope = ? AND need_key = ?',
        whereArgs: [scope, need.key],
      );
      int? movementId;
      final now = DateTime.now();
      final day =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      if (moveFrom != null) {
        movementId = await _accounts.addTransfer(
          Transfer(
            fromAccount: moveFrom,
            toAccount: destination!,
            amountPaise: move,
            note: 'Allocation · ${need.label}',
            date: day,
            createdAt: now.toIso8601String(),
            status: MovementStatus.planned,
          ),
          within: txn,
          // Money moved for a goal counts toward that goal.
          link: need.key.startsWith('goal:')
              ? (type: 'goal', id: int.parse(need.key.substring(5)))
              : null,
        );
      }
      final row = {
        'scope': scope,
        'need_key': need.key,
        'bucket': need.bucket.name,
        'label': need.label,
        'amount': amount,
        'destination': destination,
        'source': moveFrom,
        'status': DecisionStatus.reserved.name,
        'movement_id': movementId,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
      final id = await txn.insert('allocation_decisions', row);
      await writeAudit(
        txn,
        entity: 'allocation',
        entityId: id,
        action: 'reserve',
        after: row,
      );
    });
  }

  /// Not funding [need] this period. It isn't proposed again until undone.
  Future<void> skip(String scope, AllocationNeed need) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'allocation_decisions',
        where: 'scope = ? AND need_key = ?',
        whereArgs: [scope, need.key],
      );
      if (existing.isNotEmpty) {
        throw const AllocationException('Release the reservation first.');
      }
      final now = DateTime.now().toIso8601String();
      final row = {
        'scope': scope,
        'need_key': need.key,
        'bucket': need.bucket.name,
        'label': need.label,
        'amount': 0,
        'status': DecisionStatus.skipped.name,
        'created_at': now,
        'updated_at': now,
      };
      final id = await txn.insert('allocation_decisions', row);
      await writeAudit(
        txn,
        entity: 'allocation',
        entityId: id,
        action: 'skip',
        after: row,
      );
    });
  }

  /// The planned transfer happened at the bank: it now counts, and the
  /// money has left spendable cash for its destination.
  Future<void> markTransferred(int decisionId) async {
    final db = await _db.database;
    final r = await db.query(
      'allocation_decisions',
      where: 'id = ?',
      whereArgs: [decisionId],
    );
    if (r.isEmpty) return;
    final d = _from(r.first);
    if (d.movementId == null || d.status != DecisionStatus.reserved) {
      throw const AllocationException('There’s no transfer waiting for this.');
    }
    await _accounts.setTransferStatus(d.movementId!, MovementStatus.completed);
    await db.transaction((txn) async {
      await txn.update(
        'allocation_decisions',
        {
          'status': DecisionStatus.transferred.name,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [decisionId],
      );
      await writeAudit(
        txn,
        entity: 'allocation',
        entityId: decisionId,
        action: 'transferred',
      );
    });
  }

  /// Undoes a reservation or a skip. A transfer that hasn't happened yet is
  /// cancelled; one already done stays done (cancel it from the account
  /// history if it was a mistake).
  Future<void> release(int decisionId) async {
    final db = await _db.database;
    final r = await db.query(
      'allocation_decisions',
      where: 'id = ?',
      whereArgs: [decisionId],
    );
    if (r.isEmpty) return;
    final d = _from(r.first);
    if (d.status == DecisionStatus.transferred) {
      throw const AllocationException(
        'That money has already moved. Cancel the transfer from the account’s history instead.',
      );
    }
    if (d.movementId != null) {
      await _accounts.setTransferStatus(
        d.movementId!,
        MovementStatus.cancelled,
      );
    }
    await db.transaction((txn) async {
      await txn.delete(
        'allocation_decisions',
        where: 'id = ?',
        whereArgs: [decisionId],
      );
      await writeAudit(
        txn,
        entity: 'allocation',
        entityId: decisionId,
        action: 'release',
        before: r.first,
      );
    });
  }
}
