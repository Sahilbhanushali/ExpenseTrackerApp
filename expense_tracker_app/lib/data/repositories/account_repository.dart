import '../datasources/app_database.dart';
import '../models/account.dart';

/// Port of expense_bot/db.py's accounts/transfers functions.
class AccountRepository {
  final AppDatabase _db;
  AccountRepository([AppDatabase? db]) : _db = db ?? AppDatabase.instance;

  Future<int> add(String name, double openingBalance) async {
    final db = await _db.database;
    return db.insert('accounts', {
      'name': name,
      'opening_balance': openingBalance,
      'is_default': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<MoneyAccount>> list() async {
    final db = await _db.database;
    final rows = await db.query('accounts', orderBy: 'id ASC');
    return rows.map(MoneyAccount.fromMap).toList();
  }

  Future<String?> defaultAccount() async {
    final db = await _db.database;
    final rows = await db.query('accounts', where: 'is_default = 1');
    return rows.isEmpty ? null : rows.first['name'] as String;
  }

  Future<bool> setDefault(String name) async {
    final db = await _db.database;
    final rows = await db.query('accounts', where: 'name = ?', whereArgs: [name]);
    if (rows.isEmpty) return false;
    await db.update('accounts', {'is_default': 0});
    await db.update('accounts', {'is_default': 1}, where: 'name = ?', whereArgs: [name]);
    return true;
  }

  Future<double?> balance(String name) async {
    final db = await _db.database;
    final accRows = await db.query('accounts', where: 'name = ?', whereArgs: [name]);
    if (accRows.isEmpty) return null;
    var balance = (accRows.first['opening_balance'] as num).toDouble();

    final txnRows = await db.rawQuery(
      "SELECT type, SUM(amount) as total FROM txns WHERE account = ? GROUP BY type",
      [name],
    );
    for (final r in txnRows) {
      final total = (r['total'] as num?)?.toDouble() ?? 0;
      if (r['type'] == 'expense' || r['type'] == 'lent') {
        balance -= total;
      } else {
        balance += total;
      }
    }

    final inRows = await db.rawQuery(
      "SELECT SUM(amount) as total FROM transfers WHERE to_account = ?",
      [name],
    );
    final outRows = await db.rawQuery(
      "SELECT SUM(amount) as total FROM transfers WHERE from_account = ?",
      [name],
    );
    final transferredIn = (inRows.first['total'] as num?)?.toDouble() ?? 0;
    final transferredOut = (outRows.first['total'] as num?)?.toDouble() ?? 0;
    balance += transferredIn - transferredOut;

    return balance;
  }

  Future<int> addTransfer(Transfer transfer) async {
    final db = await _db.database;
    return db.insert('transfers', transfer.toMap()..remove('id'));
  }
}
