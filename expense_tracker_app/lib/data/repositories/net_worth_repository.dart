import 'package:sqflite/sqflite.dart';

import '../datasources/app_database.dart';

class NetWorthPoint {
  /// yyyy-MM.
  final String month;
  final int assets;
  final int liabilities;
  final int netWorth;
  const NetWorthPoint(this.month, this.assets, this.liabilities, this.netWorth);
}

/// Month-end net worth as last seen in each month. Paise.
class NetWorthRepository {
  final AppDatabase _db;
  NetWorthRepository([AppDatabase? db]) : _db = db ?? AppDatabase.instance;

  static String monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  /// Upserts this month's figure; earlier months stay as they were.
  Future<void> record(
    DateTime when, {
    required int assets,
    required int liabilities,
  }) async {
    final db = await _db.database;
    await db.insert('net_worth_snapshots', {
      'month': monthKey(when),
      'assets': assets,
      'liabilities': liabilities,
      'net_worth': assets - liabilities,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// The last [months] recorded months, oldest first.
  Future<List<NetWorthPoint>> history(int months) async {
    final db = await _db.database;
    final rows = await db.query(
      'net_worth_snapshots',
      orderBy: 'month DESC',
      limit: months,
    );
    return [
      for (final r in rows.reversed)
        NetWorthPoint(
          r['month'] as String,
          r['assets'] as int,
          r['liabilities'] as int,
          r['net_worth'] as int,
        ),
    ];
  }
}
