import '../../core/finance/salary_cycle.dart';
import '../datasources/app_database.dart';
import 'audit_log.dart';

enum HoldingKind { mutualFund, stocks, fixedDeposit, ppf, gold, bonds, other }

String holdingKindLabel(HoldingKind k) => switch (k) {
  HoldingKind.mutualFund => 'Mutual fund',
  HoldingKind.stocks => 'Stocks',
  HoldingKind.fixedDeposit => 'Fixed deposit',
  HoldingKind.ppf => 'PPF / EPF',
  HoldingKind.gold => 'Gold',
  HoldingKind.bonds => 'Bonds',
  HoldingKind.other => 'Other',
};

/// A holding recorded by hand. [currentValuePaise] is the user's own figure
/// as of [asOf] — never a live price.
class Holding {
  final int? id;
  final String account;
  final String name;
  final HoldingKind kind;
  final int investedPaise;
  final int currentValuePaise;
  final DateTime asOf;
  final String? note;

  const Holding({
    this.id,
    required this.account,
    required this.name,
    this.kind = HoldingKind.other,
    required this.investedPaise,
    required this.currentValuePaise,
    required this.asOf,
    this.note,
  });

  int get gain => currentValuePaise - investedPaise;
}

class InvestmentException implements Exception {
  final String message;
  const InvestmentException(this.message);
  @override
  String toString() => message;
}

class InvestmentRepository {
  final AppDatabase _db;
  InvestmentRepository([AppDatabase? db]) : _db = db ?? AppDatabase.instance;

  static Holding _from(Map<String, Object?> r) => Holding(
    id: r['id'] as int,
    account: r['account'] as String,
    name: r['name'] as String,
    kind:
        HoldingKind.values.where((k) => k.name == r['kind']).firstOrNull ??
        HoldingKind.other,
    investedPaise: r['invested'] as int,
    currentValuePaise: r['current_value'] as int,
    asOf: DateTime.parse(r['as_of'] as String),
    note: r['note'] as String?,
  );

  Future<List<Holding>> list() async {
    final db = await _db.database;
    final rows = await db.query(
      'investment_holdings',
      where: "status = 'active'",
      orderBy: 'account, name',
    );
    return rows.map(_from).toList();
  }

  /// Account name → (invested, current value) across its holdings.
  Future<Map<String, ({int invested, int current, int count})>> totals() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT account, SUM(invested) AS i, SUM(current_value) AS c, COUNT(*) AS n '
      "FROM investment_holdings WHERE status = 'active' GROUP BY account",
    );
    return {
      for (final r in rows)
        r['account'] as String: (
          invested: (r['i'] as num).round(),
          current: (r['c'] as num).round(),
          count: r['n'] as int,
        ),
    };
  }

  Future<int> save(Holding h) async {
    if (h.name.trim().isEmpty) {
      throw const InvestmentException('Name the holding.');
    }
    if (h.investedPaise < 0 || h.currentValuePaise < 0) {
      throw const InvestmentException("Amounts can't be negative.");
    }
    final row = {
      'account': h.account,
      'name': h.name.trim(),
      'kind': h.kind.name,
      'invested': h.investedPaise,
      'current_value': h.currentValuePaise,
      'as_of': isoDate(h.asOf),
      'note': h.note,
    };
    final db = await _db.database;
    return db.transaction((txn) async {
      if (h.id == null) {
        final id = await txn.insert('investment_holdings', {
          ...row,
          'created_at': DateTime.now().toIso8601String(),
        });
        await writeAudit(
          txn,
          entity: 'holding',
          entityId: id,
          action: 'create',
          after: row,
        );
        return id;
      }
      final before = await txn.query(
        'investment_holdings',
        where: 'id = ?',
        whereArgs: [h.id],
      );
      await txn.update(
        'investment_holdings',
        row,
        where: 'id = ?',
        whereArgs: [h.id],
      );
      await writeAudit(
        txn,
        entity: 'holding',
        entityId: h.id,
        action: 'update',
        before: before.firstOrNull,
        after: row,
      );
      return h.id!;
    });
  }

  /// Sold or matured: kept for the record, no longer counted.
  Future<void> close(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        'investment_holdings',
        {'status': 'closed'},
        where: 'id = ?',
        whereArgs: [id],
      );
      await writeAudit(txn, entity: 'holding', entityId: id, action: 'close');
    });
  }
}
