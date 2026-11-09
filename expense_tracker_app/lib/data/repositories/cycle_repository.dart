import '../../core/finance/salary_cycle.dart';
import '../datasources/app_database.dart';
import 'audit_log.dart';

/// A cycle change that was refused, with a message fit to show the user.
class CycleException implements Exception {
  final String message;
  const CycleException(this.message);
  @override
  String toString() => message;
}

/// Salary profile and salary cycles. Cycles only store their start; every
/// range is derived by [resolveCycles], and transactions are matched to a
/// cycle purely by date — nothing is copied per reporting view.
class CycleRepository {
  final AppDatabase _db;
  CycleRepository([AppDatabase? db]) : _db = db ?? AppDatabase.instance;

  Future<SalaryProfile> profile() async {
    final db = await _db.database;
    final rows = await db.query('salary_profile', where: 'id = 1');
    if (rows.isEmpty) return const SalaryProfile();
    final r = rows.first;
    return SalaryProfile(
      ctcAnnualPaise: r['ctc_annual'] as int?,
      grossMonthlyPaise: r['gross_monthly'] as int?,
      expectedNetPaise: r['expected_net'] as int?,
      dayFrom: r['day_from'] as int,
      dayTo: r['day_to'] as int,
      account: r['account'] as String?,
    );
  }

  Future<void> saveProfile(SalaryProfile p) async {
    if (p.dayFrom < 1 || p.dayTo > 31 || p.dayFrom > p.dayTo) {
      throw const CycleException('Pick a valid range of days.');
    }
    final row = {
      'id': 1,
      'ctc_annual': p.ctcAnnualPaise,
      'gross_monthly': p.grossMonthlyPaise,
      'expected_net': p.expectedNetPaise,
      'day_from': p.dayFrom,
      'day_to': p.dayTo,
      'account': p.account,
    };
    final db = await _db.database;
    await db.transaction((txn) async {
      final before = await txn.query('salary_profile', where: 'id = 1');
      await txn.delete('salary_profile', where: 'id = 1');
      await txn.insert('salary_profile', row);
      await writeAudit(
        txn,
        entity: 'salary_profile',
        entityId: 1,
        action: 'save',
        before: before.isEmpty ? null : before.first,
        after: row,
      );
    });
  }

  Future<List<CycleRecord>> list() async {
    final db = await _db.database;
    final rows = await db.query('income_cycles', orderBy: 'start_date ASC');
    return [
      for (final r in rows)
        CycleRecord(
          id: r['id'] as int,
          start: DateTime.parse(r['start_date'] as String),
          salaryTxnId: r['salary_txn_id'] as int?,
          untrackedSalaryPaise: r['untracked_salary'] as int?,
          closedAt: r['closed_at'] == null
              ? null
              : DateTime.parse(r['closed_at'] as String),
          note: r['note'] as String?,
        ),
    ];
  }

  /// Records a salary that arrived on [date] and starts a new cycle there.
  ///
  /// Normally this also writes the salary as an income transaction into
  /// [account]. When [alreadyInBalance] is true — the account's opening
  /// balance was entered after the salary landed — no transaction is
  /// written (rule 8: it would count the same money twice) and the amount
  /// is kept on the cycle only.
  ///
  /// If a cycle already starts on [date] without a salary, the salary is
  /// attached to it. Returns the cycle id.
  Future<int> recordSalary({
    required int amountPaise,
    required DateTime date,
    String? account,
    bool alreadyInBalance = false,
    String? note,
    DateTime? today,
  }) async {
    if (amountPaise <= 0) {
      throw const CycleException('Enter the salary amount you received.');
    }
    final day = dateOnly(date);
    final now = today ?? DateTime.now();
    final cycles = resolveCycles(await list());
    final sameDay = cycles.where((c) => c.start == day).firstOrNull;
    if (sameDay != null &&
        (sameDay.record.salaryTxnId != null ||
            sameDay.record.untrackedSalaryPaise != null)) {
      throw const CycleException(
        'A salary is already recorded for the cycle starting that day.',
      );
    }
    if (sameDay == null) {
      final error = validateCycleStart(day, cycles, now);
      if (error != null) throw CycleException(error);
    } else if (sameDay.record.isClosed) {
      throw const CycleException('That cycle is closed.');
    }

    final db = await _db.database;
    return db.transaction((txn) async {
      int? txnId;
      if (!alreadyInBalance) {
        txnId = await txn.insert('txns', {
          'date': isoDate(day),
          'category': 'salary',
          'amount': amountPaise,
          'note': (note == null || note.trim().isEmpty) ? 'Salary' : note,
          'type': 'income',
          'created_at': now.toIso8601String(),
          'account': account,
          'source': 'manual',
        });
      }
      final salaryFields = {
        'salary_txn_id': txnId,
        'untracked_salary': alreadyInBalance ? amountPaise : null,
      };
      final int cycleId;
      if (sameDay != null) {
        cycleId = sameDay.record.id!;
        await txn.update(
          'income_cycles',
          salaryFields,
          where: 'id = ?',
          whereArgs: [cycleId],
        );
      } else {
        cycleId = await txn.insert('income_cycles', {
          'start_date': isoDate(day),
          ...salaryFields,
          'note': note,
          'created_at': now.toIso8601String(),
        });
      }
      await writeAudit(
        txn,
        entity: 'cycle',
        entityId: cycleId,
        action: 'salary',
        after: {
          'start_date': isoDate(day),
          'amount': amountPaise,
          'account': account,
          'already_in_balance': alreadyInBalance,
          'salary_txn_id': txnId,
        },
      );
      return cycleId;
    });
  }

  /// Starts a cycle with no salary attached — e.g. when you begin tracking
  /// partway through a pay period. A salary can be attached later by
  /// recording one on the same date.
  Future<int> startCycle(DateTime date, {String? note, DateTime? today}) async {
    final day = dateOnly(date);
    final error = validateCycleStart(
      day,
      resolveCycles(await list()),
      today ?? DateTime.now(),
    );
    if (error != null) throw CycleException(error);
    final db = await _db.database;
    return db.transaction((txn) async {
      final id = await txn.insert('income_cycles', {
        'start_date': isoDate(day),
        'note': note,
        'created_at': DateTime.now().toIso8601String(),
      });
      await writeAudit(
        txn,
        entity: 'cycle',
        entityId: id,
        action: 'create',
        after: {'start_date': isoDate(day)},
      );
      return id;
    });
  }

  /// Manual correction of a cycle's start (which also moves the previous
  /// cycle's end). The salary transaction keeps its own date.
  Future<void> moveStart(int id, DateTime newStart, {DateTime? today}) async {
    final day = dateOnly(newStart);
    final cycles = resolveCycles(await list());
    if (!cycles.any((c) => c.record.id == id)) {
      throw const CycleException('That cycle no longer exists.');
    }
    final error = validateCycleStart(
      day,
      cycles,
      today ?? DateTime.now(),
      movingId: id,
    );
    if (error != null) throw CycleException(error);
    final before = cycles.firstWhere((c) => c.record.id == id).start;
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        'income_cycles',
        {'start_date': isoDate(day)},
        where: 'id = ?',
        whereArgs: [id],
      );
      await writeAudit(
        txn,
        entity: 'cycle',
        entityId: id,
        action: 'move',
        before: {'start_date': isoDate(before)},
        after: {'start_date': isoDate(day)},
      );
    });
  }

  /// Removes a cycle boundary; the previous cycle then runs on through
  /// these dates. The salary transaction is kept — it's still money you
  /// received.
  Future<void> remove(int id) async {
    final cycles = resolveCycles(await list());
    final idx = cycles.indexWhere((c) => c.record.id == id);
    if (idx < 0) return;
    final c = cycles[idx];
    if (c.record.isClosed) {
      throw const CycleException('A closed cycle can’t be removed.');
    }
    if (idx > 0 && cycles[idx - 1].record.isClosed) {
      throw const CycleException(
        'The previous cycle is closed, and removing this one would change it.',
      );
    }
    final db = await _db.database;
    await db.transaction((txn) async {
      final row = await txn.query(
        'income_cycles',
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.delete('income_cycles', where: 'id = ?', whereArgs: [id]);
      await writeAudit(
        txn,
        entity: 'cycle',
        entityId: id,
        action: 'delete',
        before: row.firstOrNull,
      );
    });
  }

  /// Salary and other income received within [cycle]'s dates.
  Future<CycleIncome> incomeFor(CycleRange cycle, DateTime today) async {
    final db = await _db.database;
    final linked = cycle.record.salaryTxnId;
    var salary = cycle.record.untrackedSalaryPaise ?? 0;
    if (linked != null) {
      final rows = await db.query(
        'txns',
        columns: ['amount'],
        where: "id = ? AND type = 'income'",
        whereArgs: [linked],
      );
      // The salary entry was deleted: there is no salary to count.
      salary = rows.isEmpty ? 0 : (rows.first['amount'] as num).round();
    }
    final other = await db.rawQuery(
      "SELECT SUM(amount) AS total FROM txns WHERE type = 'income' "
      'AND date >= ? AND date <= ? AND id != ?',
      [isoDate(cycle.start), isoDate(cycle.queryEnd(today)), linked ?? -1],
    );
    return CycleIncome(
      salary: salary,
      additional: (other.first['total'] as num?)?.round() ?? 0,
    );
  }
}
