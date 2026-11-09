import '../../core/finance/salary_cycle.dart';
import '../datasources/app_database.dart';
import '../models/account.dart';
import '../models/goal.dart';
import '../models/movement.dart';
import 'account_repository.dart';
import 'audit_log.dart';

class GoalException implements Exception {
  final String message;
  const GoalException(this.message);
  @override
  String toString() => message;
}

/// Savings goals. Progress = starting amount + completed contributions −
/// withdrawals, where contributions and withdrawals are transfers tagged
/// with the goal (link `goal` / `goal_out`). Saving is never spending
/// (rule 5), so nothing here writes an expense.
class GoalRepository {
  final AppDatabase _db;
  final AccountRepository _accounts;
  GoalRepository([AppDatabase? db])
    : _db = db ?? AppDatabase.instance,
      _accounts = AccountRepository(db);

  Future<List<Goal>> list() async {
    final db = await _db.database;
    final rows = await db.query('goals', orderBy: 'priority ASC, id ASC');
    return rows.map(Goal.fromMap).toList();
  }

  static String? _validate(Goal g) {
    if (g.name.trim().isEmpty) return 'Give the goal a name.';
    if (g.targetPaise <= 0) return 'Enter a target greater than zero.';
    if (g.startingPaise < 0 || (g.monthlyContributionPaise ?? 0) < 0) {
      return "Amounts can't be negative.";
    }
    if (g.priority < 1 || g.priority > 3) return 'Pick a priority.';
    return null;
  }

  Future<int> save(Goal g) async {
    final error = _validate(g);
    if (error != null) throw GoalException(error);
    final db = await _db.database;
    return db.transaction((txn) async {
      final row = g.toMap()..remove('id');
      if (g.id == null) {
        final id = await txn.insert('goals', row);
        await writeAudit(
          txn,
          entity: 'goal',
          entityId: id,
          action: 'create',
          after: row,
        );
        return id;
      }
      final before = await txn.query(
        'goals',
        where: 'id = ?',
        whereArgs: [g.id],
      );
      row.remove('created_at');
      await txn.update('goals', row, where: 'id = ?', whereArgs: [g.id]);
      await writeAudit(
        txn,
        entity: 'goal',
        entityId: g.id,
        action: 'update',
        before: before.firstOrNull,
        after: row,
      );
      return g.id!;
    });
  }

  /// Goal id → saved so far, in paise.
  Future<Map<int, int>> saved() async {
    final db = await _db.database;
    final out = <int, int>{
      for (final r in await db.query(
        'goals',
        columns: ['id', 'starting_amount'],
      ))
        r['id'] as int: r['starting_amount'] as int? ?? 0,
    };
    final moves = await db.rawQuery(
      "SELECT link_id, SUM(CASE WHEN link_type = 'goal' THEN amount ELSE -amount END) AS t "
      "FROM movements WHERE link_type IN ('goal', 'goal_out') AND status = 'completed' "
      'GROUP BY link_id',
    );
    for (final r in moves) {
      final id = r['link_id'] as int;
      if (out.containsKey(id)) {
        out[id] = out[id]! + ((r['t'] as num?)?.round() ?? 0);
      }
    }
    // Contributions recorded as expenses before v19 still count toward
    // progress, so nobody's saved amount drops on upgrade.
    final legacy = await db.rawQuery(
      "SELECT goal_id, SUM(amount) AS t FROM txns WHERE goal_id IS NOT NULL "
      "AND type = 'expense' GROUP BY goal_id",
    );
    for (final r in legacy) {
      final id = r['goal_id'] as int;
      if (out.containsKey(id)) {
        out[id] = out[id]! + ((r['t'] as num?)?.round() ?? 0);
      }
    }
    return out;
  }

  Future<Goal> _goal(int id) async {
    final db = await _db.database;
    final r = await db.query('goals', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) throw const GoalException('That goal no longer exists.');
    final g = Goal.fromMap(r.first);
    if (g.account == null) {
      throw const GoalException('Link the goal to a savings account first.');
    }
    return g;
  }

  /// Moves money from [from] into the goal's account, tagged with the
  /// goal. Planned when [done] is false. Returns the movement id.
  Future<int> contribute(
    int goalId, {
    required String from,
    required int amountPaise,
    bool done = true,
    DateTime? date,
  }) async {
    final g = await _goal(goalId);
    if (amountPaise <= 0) {
      throw const GoalException('Enter an amount greater than zero.');
    }
    if (from == g.account) {
      throw const GoalException('The money is already in the goal’s account.');
    }
    final now = date ?? DateTime.now();
    return _accounts.addTransfer(
      Transfer(
        fromAccount: from,
        toAccount: g.account!,
        amountPaise: amountPaise,
        note: 'Goal · ${g.name}',
        date: isoDate(now),
        createdAt: DateTime.now().toIso8601String(),
        status: done ? MovementStatus.completed : MovementStatus.planned,
      ),
      link: (type: 'goal', id: goalId),
    );
  }

  /// Takes money back out of the goal into [to] (e.g. to spend on it).
  /// Never more than has been saved.
  Future<int> withdraw(
    int goalId, {
    required String to,
    required int amountPaise,
    DateTime? date,
  }) async {
    final g = await _goal(goalId);
    final have = (await saved())[goalId] ?? 0;
    if (amountPaise <= 0) {
      throw const GoalException('Enter an amount greater than zero.');
    }
    if (amountPaise > have) {
      throw const GoalException('That’s more than is saved for it.');
    }
    final now = date ?? DateTime.now();
    return _accounts.addTransfer(
      Transfer(
        fromAccount: g.account!,
        toAccount: to,
        amountPaise: amountPaise,
        note: 'From goal · ${g.name}',
        date: isoDate(now),
        createdAt: DateTime.now().toIso8601String(),
      ),
      link: (type: 'goal_out', id: goalId),
    );
  }

  Future<void> setAchieved(int id, bool achieved) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        'goals',
        {'status': achieved ? 'achieved' : 'active'},
        where: 'id = ?',
        whereArgs: [id],
      );
      await writeAudit(
        txn,
        entity: 'goal',
        entityId: id,
        action: achieved ? 'achieved' : 'reopen',
      );
    });
  }

  /// Deletes the goal tracker only — the money stays in its account.
  Future<void> remove(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final before = await txn.query('goals', where: 'id = ?', whereArgs: [id]);
      await txn.delete('goals', where: 'id = ?', whereArgs: [id]);
      await writeAudit(
        txn,
        entity: 'goal',
        entityId: id,
        action: 'delete',
        before: before.firstOrNull,
      );
    });
  }
}
