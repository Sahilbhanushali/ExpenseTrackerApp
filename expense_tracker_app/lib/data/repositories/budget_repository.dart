import '../../core/finance/budgets.dart';
import '../../core/finance/salary_cycle.dart';
import '../datasources/app_database.dart';
import 'audit_log.dart';

class BudgetException implements Exception {
  final String message;
  const BudgetException(this.message);
  @override
  String toString() => message;
}

/// Budgets for every period. The single source of budget limits; the old
/// month-only values in config.json are imported once (see [importLegacy]).
class BudgetRepository {
  final AppDatabase _db;
  BudgetRepository([AppDatabase? db]) : _db = db ?? AppDatabase.instance;

  static Budget _from(Map<String, Object?> r) => Budget(
    id: r['id'] as int,
    period: budgetPeriodFrom(r['period'] as String),
    category: r['category'] as String?,
    limitPaise: r['limit_amount'] as int,
    start: r['start_date'] == null
        ? null
        : DateTime.parse(r['start_date'] as String),
    end: r['end_date'] == null ? null : DateTime.parse(r['end_date'] as String),
    cautionPct: r['caution_pct'] as int,
    essential: r['essential'] == 1,
    name: r['name'] as String?,
  );

  static Map<String, Object?> _row(Budget b) => {
    'period': b.period.name,
    'category': b.category,
    'limit_amount': b.limitPaise,
    'start_date': b.start == null ? null : isoDate(b.start!),
    'end_date': b.end == null ? null : isoDate(b.end!),
    'caution_pct': b.cautionPct,
    'essential': b.essential ? 1 : 0,
    'name': b.name,
  };

  Future<List<Budget>> list() async {
    final db = await _db.database;
    final rows = await db.query('budgets', orderBy: 'period, category');
    return rows.map(_from).toList();
  }

  /// Inserts or updates. Throws [BudgetException] with a user-facing reason.
  Future<int> save(Budget b) async {
    final error = validateBudget(b, await list());
    if (error != null) throw BudgetException(error);
    final db = await _db.database;
    return db.transaction((txn) async {
      final row = _row(b);
      if (b.id == null) {
        final id = await txn.insert('budgets', {
          ...row,
          'created_at': DateTime.now().toIso8601String(),
        });
        await writeAudit(
          txn,
          entity: 'budget',
          entityId: id,
          action: 'create',
          after: row,
        );
        return id;
      }
      final before = await txn.query(
        'budgets',
        where: 'id = ?',
        whereArgs: [b.id],
      );
      await txn.update('budgets', row, where: 'id = ?', whereArgs: [b.id]);
      await writeAudit(
        txn,
        entity: 'budget',
        entityId: b.id,
        action: 'update',
        before: before.firstOrNull,
        after: row,
      );
      return b.id!;
    });
  }

  Future<void> remove(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final before = await txn.query(
        'budgets',
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.delete('budgets', where: 'id = ?', whereArgs: [id]);
      await writeAudit(
        txn,
        entity: 'budget',
        entityId: id,
        action: 'delete',
        before: before.firstOrNull,
      );
    });
  }

  /// Copies the pre-v15 monthly budget and category caps from config into
  /// this table, once. Returns how many budgets were created.
  Future<int> importLegacy(
    int monthlyPaise,
    Map<String, int> categories,
  ) async {
    if ((await list()).isNotEmpty) return 0;
    var n = 0;
    if (monthlyPaise > 0) {
      await save(Budget(period: BudgetPeriod.month, limitPaise: monthlyPaise));
      n++;
    }
    for (final e in categories.entries) {
      if (e.value <= 0) continue;
      await save(
        Budget(
          period: BudgetPeriod.month,
          category: e.key,
          limitPaise: e.value,
        ),
      );
      n++;
    }
    return n;
  }
}
