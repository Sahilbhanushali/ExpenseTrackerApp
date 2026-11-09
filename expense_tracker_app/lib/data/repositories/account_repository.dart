import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../core/finance/accounting.dart';
import '../datasources/app_database.dart';
import '../models/account.dart';
import '../models/movement.dart';
import '../models/transaction.dart';
import 'audit_log.dart';

/// Sentinel distinguishing "leave current_value untouched" from "explicitly
/// clear it" in [AccountRepository.update] — a plain `null` default can't
/// tell those apart since null is also the valid "clear it" value.
const Object unsetCurrentValue = Object();

/// Accounts and the transfers between them.
///
/// Balance = opening balance + Σ transactions on the account + Σ completed
/// postings to it. Transfers are `movements` with two postings (−from, +to)
/// sharing one ref, written in a single database transaction.
class AccountRepository {
  final AppDatabase _db;
  AccountRepository([AppDatabase? db]) : _db = db ?? AppDatabase.instance;

  static final _random = Random();
  static String newRef(String kind) =>
      '$kind-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  Future<int> add(
    String name,
    int openingBalancePaise, {
    AccountType type = AccountType.cash,
    int? currentValuePaise,
    String? bankName,
    String? last4,
    Set<AccountRole>? roles,
    BankType? bankType,
    int holdPaise = 0,
  }) async {
    final db = await _db.database;
    final row = {
      'bank_type': bankType?.name,
      'hold_amount': holdPaise,
      'name': name,
      'opening_balance': openingBalancePaise,
      'is_default': 0,
      'created_at': DateTime.now().toIso8601String(),
      'type': accountTypeToString(type),
      'current_value': currentValuePaise,
      'bank_name': _blankToNull(bankName),
      'last4': _blankToNull(last4),
      'roles': rolesToCsv(roles ?? defaultRolesFor(type)),
      'status': AccountStatus.active.name,
    };
    return db.transaction((txn) async {
      final id = await txn.insert('accounts', row);
      await writeAudit(
        txn,
        entity: 'account',
        entityId: id,
        action: 'create',
        after: row,
      );
      return id;
    });
  }

  static String? _blankToNull(String? v) =>
      v == null || v.trim().isEmpty ? null : v.trim();

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

  Future<int?> _idFor(DatabaseExecutor ex, String name) async {
    final rows = await ex.query(
      'accounts',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [name],
    );
    return rows.isEmpty ? null : rows.first['id'] as int;
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
      'SELECT type, SUM(amount) as total FROM txns WHERE account = ? GROUP BY type',
      [name],
    );
    for (final r in txnRows) {
      balance += txnBalanceEffect(
        txnTypeFromString(r['type'] as String),
        (r['total'] as num?)?.round() ?? 0,
      );
    }

    final posted = await db.rawQuery(
      "SELECT SUM(p.amount) AS total FROM postings p "
      "JOIN movements m ON m.id = p.movement_id "
      "WHERE p.owner_type = 'account' AND p.owner_id = ? "
      "AND m.status = 'completed'",
      [accRows.first['id']],
    );
    return balance + ((posted.first['total'] as num?)?.round() ?? 0);
  }

  /// The balance as it stood at the end of [date]: opening balance,
  /// transactions dated up to then, and completed movements dated up to
  /// then. What a bank statement for that day should show.
  Future<int?> balanceAsOf(
    String name,
    DateTime date, {
    DatabaseExecutor? within,
  }) async {
    final db = within ?? await _db.database;
    final acc = await db.query(
      'accounts',
      where: 'name = ?',
      whereArgs: [name],
    );
    if (acc.isEmpty) return null;
    final day = _iso(date);
    var balance = (acc.first['opening_balance'] as num).round();
    final txnRows = await db.rawQuery(
      'SELECT type, SUM(amount) AS t FROM txns WHERE account = ? AND date <= ? GROUP BY type',
      [name, day],
    );
    for (final r in txnRows) {
      balance += txnBalanceEffect(
        txnTypeFromString(r['type'] as String),
        (r['t'] as num?)?.round() ?? 0,
      );
    }
    final posted = await db.rawQuery(
      "SELECT SUM(p.amount) AS t FROM postings p JOIN movements m ON m.id = p.movement_id "
      "WHERE p.owner_type = 'account' AND p.owner_id = ? AND m.status = 'completed' "
      'AND m.date <= ?',
      [acc.first['id'], day],
    );
    return balance + ((posted.first['t'] as num?)?.round() ?? 0);
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Transfers recorded as planned (approved, not yet done at the bank),
  /// oldest first. They don't affect any balance until completed.
  Future<List<Transfer>> plannedTransfers() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      "$_transferSelect AND m.status = 'planned' ORDER BY m.date ASC, m.id ASC",
    );
    return rows.map(_transferFrom).toList();
  }

  /// Edits an account. A rename cascades to `txns.account` (still keyed by
  /// name); postings use the id, so they need nothing. Old and new values
  /// go to the audit log.
  Future<bool> update(
    int id, {
    String? name,
    int? openingBalancePaise,
    AccountType? type,
    Object? currentValue = unsetCurrentValue,
    String? bankName,
    String? last4,
    Set<AccountRole>? roles,
    AccountStatus? status,
    BankType? bankType,
    int? holdPaise,
  }) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'accounts',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) return false;
      final before = rows.first;
      final oldName = before['name'] as String;

      final fields = <String, Object?>{};
      if (name != null && name != oldName) fields['name'] = name;
      if (openingBalancePaise != null &&
          openingBalancePaise != before['opening_balance']) {
        fields['opening_balance'] = openingBalancePaise;
      }
      if (type != null) fields['type'] = accountTypeToString(type);
      if (!identical(currentValue, unsetCurrentValue)) {
        fields['current_value'] = currentValue;
      }
      if (bankName != null) fields['bank_name'] = _blankToNull(bankName);
      if (last4 != null) fields['last4'] = _blankToNull(last4);
      if (roles != null) fields['roles'] = rolesToCsv(roles);
      if (status != null) fields['status'] = status.name;
      if (bankType != null) fields['bank_type'] = bankType.name;
      if (holdPaise != null && holdPaise != before['hold_amount']) {
        fields['hold_amount'] = holdPaise;
      }
      if (fields.isEmpty) return false;

      await txn.update('accounts', fields, where: 'id = ?', whereArgs: [id]);
      if (fields.containsKey('name')) {
        for (final table in ['txns', 'salary_profile']) {
          await txn.update(
            table,
            {'account': name},
            where: 'account = ?',
            whereArgs: [oldName],
          );
        }
      }
      await writeAudit(
        txn,
        entity: 'account',
        entityId: id,
        action: 'update',
        before: {for (final k in fields.keys) k: before[k]},
        after: fields,
      );
      return true;
    });
  }

  static const _linkedSql =
      'SELECT '
      '(SELECT COUNT(*) FROM txns WHERE account = ?) + '
      "(SELECT COUNT(*) FROM postings WHERE owner_type = 'account' AND owner_id = ?) "
      'AS c';

  /// How many transactions and transfer sides reference this account.
  /// Deleting an account that still has history would orphan those rows:
  /// they'd vanish from every balance while still counting toward month
  /// totals and category charts, so the books quietly stop reconciling.
  Future<int> linkedRecordCount(String name) async {
    final db = await _db.database;
    final id = await _idFor(db, name);
    final rows = await db.rawQuery(_linkedSql, [name, id]);
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Deletes an account, moving any history it owns to [reassignTo] first.
  ///
  /// Refuses (returns false) when the account still has linked records and
  /// no destination was given — callers must decide what happens to that
  /// money rather than letting it silently disappear.
  Future<bool> remove(int id, {String? reassignTo}) async {
    final db = await _db.database;
    return db.transaction<bool>((txn) async {
      final rows = await txn.query(
        'accounts',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) return false;
      final name = rows.first['name'] as String;
      final linked = await txn.rawQuery(_linkedSql, [name, id]);
      final count = (linked.first['c'] as int?) ?? 0;

      if (count > 0) {
        if (reassignTo == null) return false;
        final targetId = await _idFor(txn, reassignTo);
        if (targetId == null) return false;
        await txn.update(
          'txns',
          {'account': reassignTo},
          where: 'account = ?',
          whereArgs: [name],
        );
        await txn.update(
          'postings',
          {'owner_id': targetId},
          where: "owner_type = 'account' AND owner_id = ?",
          whereArgs: [id],
        );
      }

      final deleted = await txn.delete(
        'accounts',
        where: 'id = ?',
        whereArgs: [id],
      );
      await writeAudit(
        txn,
        entity: 'account',
        entityId: id,
        action: 'delete',
        before: rows.first,
        after: reassignTo == null ? null : {'history_moved_to': reassignTo},
      );
      return deleted > 0;
    });
  }

  /// Every account's balance in three queries total. Runs after every write
  /// in the app. Account name → balance in paise.
  Future<Map<String, int>> allBalances() async {
    final db = await _db.database;
    final balances = <String, int>{};
    final names = <int, String>{};

    for (final row in await db.query('accounts')) {
      final name = row['name'] as String;
      names[row['id'] as int] = name;
      balances[name] = (row['opening_balance'] as num).round();
    }

    final txnRows = await db.rawQuery(
      'SELECT account, type, SUM(amount) AS total FROM txns '
      'WHERE account IS NOT NULL GROUP BY account, type',
    );
    for (final r in txnRows) {
      final name = r['account'] as String;
      if (!balances.containsKey(name)) continue;
      balances[name] =
          balances[name]! +
          txnBalanceEffect(
            txnTypeFromString(r['type'] as String),
            (r['total'] as num?)?.round() ?? 0,
          );
    }

    final postingRows = await db.rawQuery(
      "SELECT p.owner_id AS id, SUM(p.amount) AS total FROM postings p "
      "JOIN movements m ON m.id = p.movement_id "
      "WHERE p.owner_type = 'account' AND m.status = 'completed' "
      'GROUP BY p.owner_id',
    );
    for (final r in postingRows) {
      final name = names[r['id']];
      if (name == null) continue;
      balances[name] = balances[name]! + ((r['total'] as num?)?.round() ?? 0);
    }
    return balances;
  }

  /// Transactions linked to no account — they count toward no balance.
  Future<int> unassignedTxnCount() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      // Card spending and loan-financed purchases have no bank account
      // by design; they belong to the card or loan.
      'SELECT COUNT(*) AS n FROM txns WHERE account IS NULL '
      'AND card_id IS NULL AND loan_id IS NULL',
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  /// Every movement with a side on an account — transfers, card bills,
  /// loan repayments and disbursements — with the other side named.
  static const _transferSelect =
      "SELECT m.id, m.kind, m.date, m.amount, m.note, m.created_at, m.status, "
      "COALESCE(fa.name, fc.name, fl.name) AS from_name, "
      "COALESCE(ta.name, tc.name, tl.name) AS to_name, "
      "fa.id AS from_acc, ta.id AS to_acc "
      "FROM movements m "
      "JOIN postings fp ON fp.movement_id = m.id AND fp.amount < 0 "
      "JOIN postings tp ON tp.movement_id = m.id AND tp.amount > 0 "
      "LEFT JOIN accounts fa ON fp.owner_type = 'account' AND fa.id = fp.owner_id "
      "LEFT JOIN accounts ta ON tp.owner_type = 'account' AND ta.id = tp.owner_id "
      "LEFT JOIN credit_cards fc ON fp.owner_type = 'card' AND fc.id = fp.owner_id "
      "LEFT JOIN credit_cards tc ON tp.owner_type = 'card' AND tc.id = tp.owner_id "
      "LEFT JOIN loans fl ON fp.owner_type = 'loan' AND fl.id = fp.owner_id "
      "LEFT JOIN loans tl ON tp.owner_type = 'loan' AND tl.id = tp.owner_id "
      "WHERE 1 = 1";

  static Transfer _transferFrom(Map<String, Object?> r) => Transfer(
    id: r['id'] as int,
    fromAccount: r['from_name'] as String? ?? 'Removed account',
    toAccount: r['to_name'] as String? ?? 'Removed account',
    amountPaise: (r['amount'] as num).round(),
    note: r['note'] as String?,
    date: r['date'] as String,
    createdAt: r['created_at'] as String,
    status: movementStatusFrom(r['status'] as String?),
    kind: MovementKind.values.firstWhere(
      (k) => k.name == r['kind'],
      orElse: () => MovementKind.transfer,
    ),
  );

  /// Transfers into or out of [name], newest first, cancelled ones left
  /// out. Transfers are few compared to transactions, so they're loaded in
  /// one query.
  Future<List<Transfer>> transfersFor(
    String name, {
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _db.database;
    final id = await _idFor(db, name);
    if (id == null) return [];
    final where = ["m.status != 'cancelled'", '(fa.id = ? OR ta.id = ?)'];
    final args = <Object?>[id, id];
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (from != null) {
      where.add('m.date >= ?');
      args.add(iso(from));
    }
    if (to != null) {
      where.add('m.date <= ?');
      args.add(iso(to));
    }
    final rows = await db.rawQuery(
      '$_transferSelect AND ${where.join(' AND ')} ORDER BY m.date DESC, m.id DESC',
      args,
    );
    return rows.map(_transferFrom).toList();
  }

  /// Records a transfer between two of your accounts: one movement, a −
  /// posting on the source and a + posting on the destination, plus an
  /// audit entry — all or nothing. Returns the movement id.
  ///
  /// [Transfer.status] planned records an intention that doesn't touch
  /// balances until [setTransferStatus] marks it completed.
  Future<int> addTransfer(Transfer transfer, {DatabaseExecutor? within}) async {
    if (transfer.amountPaise <= 0) {
      throw ArgumentError.value(transfer.amountPaise, 'amount', 'must be > 0');
    }
    if (transfer.fromAccount == transfer.toAccount) {
      throw ArgumentError('A transfer needs two different accounts');
    }
    Future<int> write(DatabaseExecutor ex) async {
      final fromId = await _idFor(ex, transfer.fromAccount);
      final toId = await _idFor(ex, transfer.toAccount);
      if (fromId == null || toId == null) {
        throw StateError('Unknown account in transfer');
      }
      final completed = transfer.status == MovementStatus.completed;
      final movement = {
        'ref': newRef('transfer'),
        'kind': MovementKind.transfer.name,
        'date': transfer.date,
        'amount': transfer.amountPaise,
        'status': transfer.status.name,
        'note': transfer.note,
        'created_at': transfer.createdAt,
        'completed_at': completed ? DateTime.now().toIso8601String() : null,
      };
      final id = await ex.insert('movements', movement);
      for (final p in [
        Posting(
          movementId: id,
          ownerType: PostingOwner.account,
          ownerId: fromId,
          amountPaise: -transfer.amountPaise,
        ),
        Posting(
          movementId: id,
          ownerType: PostingOwner.account,
          ownerId: toId,
          amountPaise: transfer.amountPaise,
        ),
      ]) {
        await ex.insert('postings', p.toMap());
      }
      await writeAudit(
        ex,
        entity: 'movement',
        entityId: id,
        action: 'create',
        after: {
          ...movement,
          'from': transfer.fromAccount,
          'to': transfer.toAccount,
        },
      );
      return id;
    }

    if (within != null) return write(within);
    final db = await _db.database;
    return db.transaction(write);
  }

  /// Several transfers that must happen together (e.g. splitting income):
  /// either all are recorded or none are.
  Future<void> addTransfers(List<Transfer> transfers) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      for (final t in transfers) {
        await addTransfer(t, within: txn);
      }
    });
  }

  /// Planned → completed (done at the bank) or → cancelled. A cancelled
  /// transfer keeps its rows for the record but stops affecting balances.
  Future<bool> setTransferStatus(int movementId, MovementStatus status) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'movements',
        where: 'id = ?',
        whereArgs: [movementId],
      );
      if (rows.isEmpty || rows.first['status'] == status.name) return false;
      // Loan movements are tied to installment state; they're undone from
      // the loan (Undo last payment), never by flipping status here.
      if (rows.first['kind'] == MovementKind.loanPrincipal.name ||
          rows.first['kind'] == MovementKind.loanOpen.name) {
        throw StateError('Undo loan payments from the loan');
      }
      if (rows.first['status'] == MovementStatus.cancelled.name) {
        throw StateError('A cancelled movement stays cancelled');
      }
      final fields = {
        'status': status.name,
        'completed_at': status == MovementStatus.completed
            ? DateTime.now().toIso8601String()
            : rows.first['completed_at'],
      };
      await txn.update(
        'movements',
        fields,
        where: 'id = ?',
        whereArgs: [movementId],
      );
      await writeAudit(
        txn,
        entity: 'movement',
        entityId: movementId,
        action: 'status',
        before: {'status': rows.first['status']},
        after: {'status': status.name},
      );
      return true;
    });
  }
}
