import '../datasources/app_database.dart';
import '../models/account.dart';

/// Sentinel distinguishing "leave current_value untouched" from "explicitly
/// clear it" in [AccountRepository.update] — a plain `null` default can't
/// tell those apart since null is also the valid "clear it" value.
const Object unsetCurrentValue = Object();

/// Port of expense_bot/db.py's accounts/transfers functions.
class AccountRepository {
  final AppDatabase _db;
  AccountRepository([AppDatabase? db]) : _db = db ?? AppDatabase.instance;

  Future<int> add(
    String name,
    int openingBalancePaise, {
    AccountType type = AccountType.cash,
    int? currentValuePaise,
  }) async {
    final db = await _db.database;
    return db.insert('accounts', {
      'name': name,
      'opening_balance': openingBalancePaise,
      'is_default': 0,
      'created_at': DateTime.now().toIso8601String(),
      'type': accountTypeToString(type),
      'current_value': currentValuePaise,
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
    final rows = await db.query(
      'accounts',
      where: 'name = ?',
      whereArgs: [name],
    );
    if (rows.isEmpty) return false;
    await db.update('accounts', {'is_default': 0});
    await db.update(
      'accounts',
      {'is_default': 1},
      where: 'name = ?',
      whereArgs: [name],
    );
    return true;
  }

  /// In paise.
  Future<int?> balance(String name) async {
    final db = await _db.database;
    final accRows = await db.query(
      'accounts',
      where: 'name = ?',
      whereArgs: [name],
    );
    if (accRows.isEmpty) return null;
    var balance = (accRows.first['opening_balance'] as num).round();

    final txnRows = await db.rawQuery(
      "SELECT type, SUM(amount) as total FROM txns WHERE account = ? GROUP BY type",
      [name],
    );
    for (final r in txnRows) {
      final total = (r['total'] as num?)?.round() ?? 0;
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
    final transferredIn = (inRows.first['total'] as num?)?.round() ?? 0;
    final transferredOut = (outRows.first['total'] as num?)?.round() ?? 0;
    balance += transferredIn - transferredOut;

    return balance;
  }

  /// Renames an account and/or changes its opening balance. A rename
  /// cascades to every txns/transfers row referencing the old name so
  /// balances stay correct.
  Future<bool> update(
    int id, {
    String? name,
    int? openingBalancePaise,
    AccountType? type,
    Object? currentValue = unsetCurrentValue,
  }) async {
    final db = await _db.database;
    final rows = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return false;
    final oldName = rows.first['name'] as String;

    final fields = <String, Object?>{};
    if (name != null && name != oldName) fields['name'] = name;
    if (openingBalancePaise != null) {
      fields['opening_balance'] = openingBalancePaise;
    }
    if (type != null) fields['type'] = accountTypeToString(type);
    if (!identical(currentValue, unsetCurrentValue)) {
      fields['current_value'] = currentValue;
    }
    if (fields.isEmpty) return false;

    await db.update('accounts', fields, where: 'id = ?', whereArgs: [id]);
    if (fields.containsKey('name')) {
      await db.update(
        'txns',
        {'account': name},
        where: 'account = ?',
        whereArgs: [oldName],
      );
      await db.update(
        'transfers',
        {'from_account': name},
        where: 'from_account = ?',
        whereArgs: [oldName],
      );
      await db.update(
        'transfers',
        {'to_account': name},
        where: 'to_account = ?',
        whereArgs: [oldName],
      );
    }
    return true;
  }

  /// How many transactions and transfers reference this account. Deleting
  /// an account that still has history would orphan those rows: they'd
  /// vanish from every balance while still counting toward month totals and
  /// category charts, so the books quietly stop reconciling.
  Future<int> linkedRecordCount(String name) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT '
      '(SELECT COUNT(*) FROM txns WHERE account = ?) + '
      '(SELECT COUNT(*) FROM transfers WHERE from_account = ? OR to_account = ?) '
      'AS c',
      [name, name, name],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Deletes an account, moving any history it owns to [reassignTo] first.
  ///
  /// Refuses (returns false) when the account still has linked records and
  /// no destination was given — callers must decide what happens to that
  /// money rather than letting it silently disappear.
  Future<bool> remove(int id, {String? reassignTo}) async {
    final db = await _db.database;
    final rows = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return false;
    final name = rows.first['name'] as String;

    return db.transaction<bool>((txn) async {
      final linked = await txn.rawQuery(
        'SELECT '
        '(SELECT COUNT(*) FROM txns WHERE account = ?) + '
        '(SELECT COUNT(*) FROM transfers WHERE from_account = ? OR to_account = ?) '
        'AS c',
        [name, name, name],
      );
      final count = (linked.first['c'] as int?) ?? 0;

      if (count > 0) {
        if (reassignTo == null) return false;
        await txn.update(
          'txns',
          {'account': reassignTo},
          where: 'account = ?',
          whereArgs: [name],
        );
        await txn.update(
          'transfers',
          {'from_account': reassignTo},
          where: 'from_account = ?',
          whereArgs: [name],
        );
        await txn.update(
          'transfers',
          {'to_account': reassignTo},
          where: 'to_account = ?',
          whereArgs: [name],
        );
      }

      final deleted = await txn.delete(
        'accounts',
        where: 'id = ?',
        whereArgs: [id],
      );
      return deleted > 0;
    });
  }

  /// Every account's balance in three queries total, rather than four per
  /// account. This runs after every add/edit/delete in the app, so the old
  /// N+1 version meant ~40 queries per transaction with ten accounts.
  /// Account name → balance in paise.
  Future<Map<String, int>> allBalances() async {
    final db = await _db.database;
    final balances = <String, int>{};

    for (final row in await db.query('accounts')) {
      balances[row['name'] as String] = (row['opening_balance'] as num).round();
    }

    final txnRows = await db.rawQuery(
      'SELECT account, type, SUM(amount) AS total FROM txns '
      'WHERE account IS NOT NULL GROUP BY account, type',
    );
    for (final r in txnRows) {
      final name = r['account'] as String;
      if (!balances.containsKey(name)) continue;
      final total = (r['total'] as num?)?.round() ?? 0;
      final outgoing = r['type'] == 'expense' || r['type'] == 'lent';
      balances[name] = balances[name]! + (outgoing ? -total : total);
    }

    final transferRows = await db.rawQuery(
      'SELECT from_account, to_account, SUM(amount) AS total FROM transfers '
      'GROUP BY from_account, to_account',
    );
    for (final r in transferRows) {
      final total = (r['total'] as num?)?.round() ?? 0;
      final from = r['from_account'] as String;
      final to = r['to_account'] as String;
      if (balances.containsKey(from)) balances[from] = balances[from]! - total;
      if (balances.containsKey(to)) balances[to] = balances[to]! + total;
    }

    return balances;
  }

  /// Transactions linked to no account — they count toward no balance.
  Future<int> unassignedTxnCount() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM txns WHERE account IS NULL',
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  /// Transfers into or out of [name], newest first. Transfers are few
  /// compared to transactions, so they're loaded in one query.
  Future<List<Transfer>> transfersFor(
    String name, {
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _db.database;
    final where = ['(from_account = ? OR to_account = ?)'];
    final args = <Object?>[name, name];
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (from != null) {
      where.add('date >= ?');
      args.add(iso(from));
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(iso(to));
    }
    final rows = await db.query(
      'transfers',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(Transfer.fromMap).toList();
  }

  Future<int> addTransfer(Transfer transfer) async {
    final db = await _db.database;
    return db.insert('transfers', transfer.toMap()..remove('id'));
  }
}
