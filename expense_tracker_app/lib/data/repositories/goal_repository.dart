import '../datasources/app_database.dart';
import '../models/goal.dart';

/// Multiple savings goals — port of the reference ledger's addGoal/
/// contributeToGoal/deleteGoal. Progress is derived from linked txns
/// (goal_id) rather than stored, same "derive, don't duplicate" approach
/// as the rest of this data layer.
class GoalRepository {
  final AppDatabase _db;
  GoalRepository([AppDatabase? db]) : _db = db ?? AppDatabase.instance;

  Future<int> add(String name, double target, {String? note}) async {
    final db = await _db.database;
    return db.insert('goals', {
      'name': name,
      'target': target,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Goal>> list() async {
    final db = await _db.database;
    final rows = await db.query('goals', orderBy: 'id ASC');
    return rows.map(Goal.fromMap).toList();
  }

  /// Sum of all transactions contributed toward this goal so far.
  Future<double> savedAmount(int goalId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      "SELECT SUM(amount) as total FROM txns WHERE goal_id = ?",
      [goalId],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<bool> update(
    int id, {
    String? name,
    double? target,
    String? note,
  }) async {
    final db = await _db.database;
    final fields = <String, Object?>{};
    if (name != null) fields['name'] = name;
    if (target != null) fields['target'] = target;
    if (note != null) fields['note'] = note;
    if (fields.isEmpty) return false;
    final count = await db.update(
      'goals',
      fields,
      where: 'id = ?',
      whereArgs: [id],
    );
    return count > 0;
  }

  /// Deletes the goal tracker only — contributions already logged stay in
  /// the ledger as ordinary expenses.
  Future<bool> remove(int id) async {
    final db = await _db.database;
    final count = await db.delete('goals', where: 'id = ?', whereArgs: [id]);
    return count > 0;
  }
}
