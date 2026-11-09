import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../../core/finance/loans.dart';
import '../../core/finance/salary_cycle.dart';
import '../datasources/app_database.dart';
import '../models/loan.dart';
import '../models/movement.dart';
import '../models/transaction.dart';
import 'account_repository.dart';
import 'audit_log.dart';

class LoanException implements Exception {
  final String message;
  const LoanException(this.message);
  @override
  String toString() => message;
}

/// What one installment payment did. All paise.
class LoanPaymentResult {
  final int interest;
  final int principal;
  final bool loanClosed;
  const LoanPaymentResult(this.interest, this.principal, this.loanClosed);
}

/// Installment loans with schedules.
///
/// - Principal repaid is a movement bank → loan: it lowers the debt and is
///   never an expense (rule 3).
/// - Interest, fees and charges are expense transactions (rule 4).
/// - Installments are generated once into `loan_installments` (unique per
///   loan and sequence), so a schedule can't be duplicated.
/// - What's owed = principal + corrections − principal repaid.
class LoanRepository {
  final AppDatabase _db;
  LoanRepository([AppDatabase? db]) : _db = db ?? AppDatabase.instance;

  Future<List<Loan>> list() async {
    final db = await _db.database;
    return (await db.query(
      'loans',
      orderBy: 'id ASC',
    )).map(Loan.fromMap).toList();
  }

  /// Every loan with its schedule and what's owed, newest first.
  /// Builds schedules for loans saved before v16 the first time.
  Future<List<LoanStanding>> standings() async {
    final db = await _db.database;
    final loans = await list();
    final out = <LoanStanding>[];
    for (final stale in loans) {
      await _ensureSchedule(stale);
      // Re-read: building a legacy schedule updates the loan row.
      final loan = Loan.fromMap(
        (await db.query('loans', where: 'id = ?', whereArgs: [stale.id])).first,
      );
      final rows = await db.query(
        'loan_installments',
        where: 'loan_id = ?',
        whereArgs: [loan.id],
        orderBy: 'seq ASC',
      );
      out.add(
        LoanStanding(
          loan: loan,
          installments: rows.map(_installmentFrom).toList(),
          outstandingPrincipal: await _outstanding(db, loan),
          interestPaid: await _interestPaid(db, loan.id!),
        ),
      );
    }
    return out.reversed.toList();
  }

  static LoanInstallment _installmentFrom(Map<String, Object?> r) =>
      LoanInstallment(
        id: r['id'] as int,
        seq: r['seq'] as int,
        dueDate: DateTime.parse(r['due_date'] as String),
        amount: r['amount'] as int,
        principal: r['principal'] as int,
        interest: r['interest'] as int,
        principalPaid: r['principal_paid'] as int,
        interestPaid: r['interest_paid'] as int,
        status: r['status'] as String,
      );

  static Future<int> _outstanding(DatabaseExecutor ex, Loan loan) async {
    final corrections = await ex.rawQuery(
      "SELECT SUM(amount) AS t FROM loan_events WHERE loan_id = ? AND kind = 'correction'",
      [loan.id],
    );
    // Only repayments (positive loan postings) reduce what's owed; the
    // negative posting of a disbursement is the other side of cash arriving.
    final repaid = await ex.rawQuery(
      "SELECT SUM(p.amount) AS t FROM postings p JOIN movements m ON m.id = p.movement_id "
      "WHERE p.owner_type = 'loan' AND p.owner_id = ? AND p.amount > 0 "
      "AND m.status = 'completed'",
      [loan.id],
    );
    final v =
        loan.principalPaise +
        ((corrections.first['t'] as num?)?.round() ?? 0) -
        ((repaid.first['t'] as num?)?.round() ?? 0);
    return v < 0 ? 0 : v;
  }

  static Future<int> _interestPaid(DatabaseExecutor ex, int loanId) async {
    final r = await ex.rawQuery(
      "SELECT SUM(amount) AS t FROM txns WHERE loan_id = ? AND type = 'expense' "
      "AND source = 'loan'",
      [loanId],
    );
    return (r.first['t'] as num?)?.round() ?? 0;
  }

  /// Schedule for a loan as entered: with a rate, reducing balance; without
  /// one, the implied interest spread evenly.
  static List<InstallmentPlan> planFor(Loan loan) => buildSchedule(
    principal: loan.principalPaise,
    emi: loan.emiPaise,
    count: loan.tenureMonths,
    firstDue: loan.startDate,
    annualRateBps: loan.rateBps,
    totalInterest: loan.rateBps == null
        ? (loan.interestPaise > 0
              ? loan.interestPaise
              : loan.impliedInterestPaise)
        : 0,
  );

  static Future<void> _insertPlan(
    DatabaseExecutor ex,
    int loanId,
    List<InstallmentPlan> plan,
  ) async {
    for (final i in plan) {
      await ex.insert('loan_installments', {
        'loan_id': loanId,
        'seq': i.seq,
        'due_date': isoDate(i.dueDate),
        'amount': i.amount,
        'principal': i.principal,
        'interest': i.interest,
      });
    }
  }

  /// Loans saved before schedules existed: build theirs once, mark the
  /// installments already counted as paid, and record the principal they
  /// repaid as a correction so what's owed stays right.
  Future<void> _ensureSchedule(Loan loan) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final has = await txn.rawQuery(
        'SELECT COUNT(*) AS n FROM loan_installments WHERE loan_id = ?',
        [loan.id],
      );
      if ((has.first['n'] as int) > 0) return;
      final plan = planFor(loan);
      await _insertPlan(txn, loan.id!, plan);
      final paid = plan.take(loan.installmentsPaid).toList();
      if (paid.isEmpty) return;
      for (final i in paid) {
        await txn.update(
          'loan_installments',
          {
            'principal_paid': i.principal,
            'interest_paid': i.interest,
            'status': 'paid',
          },
          where: 'loan_id = ? AND seq = ?',
          whereArgs: [loan.id, i.seq],
        );
      }
      await txn.insert('loan_events', {
        'loan_id': loan.id,
        'kind': 'correction',
        'amount': -paid.fold<int>(0, (s, i) => s + i.principal),
        'date': isoDate(DateTime.now()),
        'note': 'Installments paid before schedules were tracked',
        'created_at': DateTime.now().toIso8601String(),
      });
      await txn.update(
        'loans',
        {'split_estimated': loan.rateBps == null ? 1 : 0},
        where: 'id = ?',
        whereArgs: [loan.id],
      );
    });
  }

  /// Adds a loan with its schedule, plus its one-time opening effect (see
  /// [LoanOpening]). [purchaseCategory] is the expense category for a
  /// purchase-financed loan. Returns the loan id.
  Future<int> add(Loan loan, {String purchaseCategory = 'other'}) async {
    if (loan.name.trim().isEmpty) {
      throw const LoanException('Give the loan a name.');
    }
    if (loan.principalPaise <= 0 ||
        loan.emiPaise <= 0 ||
        loan.tenureMonths <= 0) {
      throw const LoanException('Enter the amount, EMI and number of months.');
    }
    if (loan.rateBps == null &&
        loan.emiPaise * loan.tenureMonths < loan.principalPaise) {
      throw const LoanException(
        'EMI × months is less than the amount, so it would never be repaid.',
      );
    }
    if (loan.opening == LoanOpening.disbursed && loan.account == null) {
      throw const LoanException('Pick the account the money arrived in.');
    }
    final db = await _db.database;
    return db.transaction((txn) async {
      final row = Loan(
        name: loan.name.trim(),
        principalPaise: loan.principalPaise,
        interestPaise: loan.rateBps == null ? loan.impliedInterestPaise : 0,
        emiPaise: loan.emiPaise,
        tenureMonths: loan.tenureMonths,
        startDate: loan.startDate,
        note: loan.note,
        account: loan.account,
        kind: loan.kind,
        lender: loan.lender,
        rateBps: loan.rateBps,
        opening: loan.opening,
        splitEstimated: loan.rateBps == null,
      ).toMap()..remove('id');
      final id = await txn.insert('loans', row);
      await _insertPlan(txn, id, planFor(Loan.fromMap({...row, 'id': id})));
      final today = isoDate(DateTime.now());
      if (loan.opening == LoanOpening.disbursed) {
        final accId = await _accountId(txn, loan.account!);
        final m = await txn.insert('movements', {
          'ref': AccountRepository.newRef('loan-open'),
          'kind': MovementKind.loanOpen.name,
          'date': today,
          'amount': loan.principalPaise,
          'status': 'completed',
          'note': 'Loan received · ${loan.name}',
          'created_at': DateTime.now().toIso8601String(),
          'completed_at': DateTime.now().toIso8601String(),
          'link_type': 'loan',
          'link_id': id,
        });
        await _post(txn, m, PostingOwner.account, accId, loan.principalPaise);
        await _post(txn, m, PostingOwner.loan, id, -loan.principalPaise);
      } else if (loan.opening == LoanOpening.purchase) {
        // The item bought on EMI is spent once, today; installments then
        // only repay the loan (rule 10).
        await txn.insert(
          'txns',
          Transaction(
            date: today,
            category: purchaseCategory,
            amountPaise: loan.principalPaise,
            note: loan.name,
            type: TxnType.expense,
            createdAt: DateTime.now().toIso8601String(),
            loanId: id,
            source: 'loan-purchase',
          ).toMap()..remove('id'),
        );
      }
      await writeAudit(
        txn,
        entity: 'loan',
        entityId: id,
        action: 'create',
        after: row,
      );
      return id;
    });
  }

  static Future<int> _accountId(DatabaseExecutor ex, String name) async {
    final r = await ex.query(
      'accounts',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [name],
    );
    if (r.isEmpty) throw const LoanException('Pick an account.');
    return r.first['id'] as int;
  }

  static Future<void> _post(
    DatabaseExecutor ex,
    int movementId,
    PostingOwner owner,
    int ownerId,
    int amount,
  ) => ex.insert(
    'postings',
    Posting(
      movementId: movementId,
      ownerType: owner,
      ownerId: ownerId,
      amountPaise: amount,
    ).toMap(),
  );

  /// Principal movement bank → loan. Returns the movement id.
  static Future<int> _repayPrincipal(
    DatabaseExecutor ex, {
    required Loan loan,
    required int accountId,
    required int amount,
    required String date,
    required String note,
    String linkType = 'loan',
    int? linkId,
  }) async {
    final m = await ex.insert('movements', {
      'ref': AccountRepository.newRef('loan'),
      'kind': MovementKind.loanPrincipal.name,
      'date': date,
      'amount': amount,
      'status': 'completed',
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
      'completed_at': DateTime.now().toIso8601String(),
      'link_type': linkType,
      'link_id': linkId ?? loan.id,
    });
    await _post(ex, m, PostingOwner.account, accountId, -amount);
    await _post(ex, m, PostingOwner.loan, loan.id!, amount);
    return m;
  }

  static Future<int> _expense(
    DatabaseExecutor ex, {
    required Loan loan,
    required String category,
    required int amount,
    required String date,
    required String account,
    required String note,
  }) => ex.insert(
    'txns',
    Transaction(
      date: date,
      category: category,
      amountPaise: amount,
      note: note,
      type: TxnType.expense,
      createdAt: DateTime.now().toIso8601String(),
      account: account,
      loanId: loan.id,
      source: 'loan',
    ).toMap()..remove('id'),
  );

  Future<Loan> _load(DatabaseExecutor ex, int loanId) async {
    final r = await ex.query('loans', where: 'id = ?', whereArgs: [loanId]);
    if (r.isEmpty) throw const LoanException('That loan no longer exists.');
    final loan = Loan.fromMap(r.first);
    if (!loan.active) throw const LoanException('That loan is closed.');
    return loan;
  }

  /// Pays the next installment due (or [amountPaise] toward it): interest
  /// still owed first, as an expense; the rest as principal. A partial
  /// payment leaves the installment due with the remainder.
  Future<LoanPaymentResult> payInstallment(
    int loanId, {
    int? amountPaise,
    required DateTime date,
    required String account,
  }) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final loan = await _load(txn, loanId);
      final rows = await txn.query(
        'loan_installments',
        where: "loan_id = ? AND status = 'due'",
        whereArgs: [loanId],
        orderBy: 'seq ASC',
        limit: 1,
      );
      if (rows.isEmpty) throw const LoanException('No installment is due.');
      final inst = _installmentFrom(rows.first);
      final amount = amountPaise ?? inst.remaining;
      if (amount <= 0) throw const LoanException('Enter the amount paid.');
      if (amount > inst.remaining) {
        throw const LoanException(
          'That’s more than this installment. Use Prepay for the extra.',
        );
      }
      final split = splitPayment(
        amount: amount,
        interestDue: inst.interest - inst.interestPaid,
        principalDue: inst.principal - inst.principalPaid,
      );
      final accId = await _accountId(txn, account);
      final day = isoDate(date);
      int? movementId, txnId;
      if (split.principal > 0) {
        movementId = await _repayPrincipal(
          txn,
          loan: loan,
          accountId: accId,
          amount: split.principal,
          date: day,
          note: 'EMI ${inst.seq} · ${loan.name}',
          linkType: 'installment',
          linkId: inst.id,
        );
      }
      if (split.interest > 0) {
        txnId = await _expense(
          txn,
          loan: loan,
          category: 'interest',
          amount: split.interest,
          date: day,
          account: account,
          note: 'Interest · EMI ${inst.seq} · ${loan.name}',
        );
      }
      final full = split.interest + split.principal == inst.remaining;
      await txn.update(
        'loan_installments',
        {
          'principal_paid': inst.principalPaid + split.principal,
          'interest_paid': inst.interestPaid + split.interest,
          'status': full ? 'paid' : 'due',
        },
        where: 'id = ?',
        whereArgs: [inst.id],
      );
      await txn.insert('loan_payments', {
        'loan_id': loanId,
        'owner_type': LoanPaymentOwner.emiLoan,
        'amount': amount,
        'date': day,
        'note': 'EMI ${inst.seq}',
        'created_at': DateTime.now().toIso8601String(),
        'installment_id': inst.id,
        'principal': split.principal,
        'interest': split.interest,
        'movement_id': movementId,
        'txn_id': txnId,
      });
      final closed = await _closeIfDone(txn, loan);
      await writeAudit(
        txn,
        entity: 'loan',
        entityId: loanId,
        action: 'pay',
        after: {
          'installment': inst.seq,
          'principal': split.principal,
          'interest': split.interest,
        },
      );
      return LoanPaymentResult(split.interest, split.principal, closed);
    });
  }

  Future<bool> _closeIfDone(DatabaseExecutor ex, Loan loan) async {
    final left = await ex.rawQuery(
      "SELECT COUNT(*) AS n FROM loan_installments WHERE loan_id = ? AND status = 'due'",
      [loan.id],
    );
    if ((left.first['n'] as int) > 0) return false;
    if (await _outstanding(ex, loan) > 0) return false;
    await ex.update(
      'loans',
      {'status': 'closed', 'active': 0},
      where: 'id = ?',
      whereArgs: [loan.id],
    );
    return true;
  }

  /// Rebuilds the unpaid future of the schedule from what's owed now.
  /// Paid and part-paid installments are never touched.
  static Future<void> _reschedule(
    DatabaseExecutor ex,
    Loan loan,
    int outstanding,
    PrepayMode mode,
  ) async {
    final rows = (await ex.query(
      'loan_installments',
      where: 'loan_id = ?',
      whereArgs: [loan.id],
      orderBy: 'seq ASC',
    )).map(_installmentFrom).toList();
    final future = rows.where((i) => i.isDue && !i.partlyPaid).toList();
    final kept = rows.where((i) => !future.contains(i)).toList();
    final keptPrincipalDue = kept
        .where((i) => i.isDue)
        .fold<int>(0, (s, i) => s + i.principal - i.principalPaid);
    final principal = outstanding - keptPrincipalDue;
    await ex.delete(
      'loan_installments',
      where: "loan_id = ? AND status = 'due' AND principal_paid = 0 AND interest_paid = 0",
      whereArgs: [loan.id],
    );
    if (principal <= 0) return;
    final nextSeq = (kept.isEmpty ? 0 : kept.last.seq) + 1;
    final firstDue = future.isNotEmpty
        ? future.first.dueDate
        : addMonths(kept.isEmpty ? loan.startDate : kept.last.dueDate, 1);
    final oldPrincipal = future.fold<int>(0, (s, i) => s + i.principal);
    final oldInterest = future.fold<int>(0, (s, i) => s + i.interest);
    // Without a rate, remaining interest shrinks in proportion to the
    // principal still owed (marked estimated).
    final interest = oldPrincipal == 0
        ? 0
        : oldInterest * principal ~/ oldPrincipal;
    late int count, emi;
    if (mode == PrepayMode.reduceEmi && future.isNotEmpty) {
      count = future.length;
      emi = loan.rateBps != null
          ? emiFor(principal, loan.rateBps!, count)
          : ((principal + interest) / count).ceil();
    } else {
      emi = loan.emiPaise;
      count = loan.rateBps != null
          ? (monthsToClear(principal, emi, loan.rateBps) ?? future.length)
          : ((principal + interest) / emi).ceil();
    }
    await _insertPlan(
      ex,
      loan.id!,
      buildSchedule(
        principal: principal,
        emi: emi,
        count: count,
        firstDue: firstDue,
        annualRateBps: loan.rateBps,
        totalInterest: interest,
        startSeq: nextSeq,
      ),
    );
    await ex.update(
      'loans',
      {'emi_amount': emi},
      where: 'id = ?',
      whereArgs: [loan.id],
    );
  }

  /// Extra principal paid now; future installments are rebuilt per [mode].
  Future<void> prepay(
    int loanId, {
    required int amountPaise,
    required DateTime date,
    required String account,
    PrepayMode mode = PrepayMode.reduceTenure,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final loan = await _load(txn, loanId);
      final owed = await _outstanding(txn, loan);
      if (amountPaise <= 0) throw const LoanException('Enter the amount paid.');
      if (amountPaise > owed) {
        throw const LoanException('That’s more than is owed. Use Close loan.');
      }
      final accId = await _accountId(txn, account);
      final m = await _repayPrincipal(
        txn,
        loan: loan,
        accountId: accId,
        amount: amountPaise,
        date: isoDate(date),
        note: 'Prepayment · ${loan.name}',
      );
      await txn.insert('loan_events', {
        'loan_id': loanId,
        'kind': 'prepayment',
        'amount': amountPaise,
        'date': isoDate(date),
        'movement_id': m,
        'note': mode.name,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _reschedule(txn, loan, owed - amountPaise, mode);
      await _closeIfDone(txn, loan);
      await writeAudit(
        txn,
        entity: 'loan',
        entityId: loanId,
        action: 'prepay',
        after: {'amount': amountPaise, 'mode': mode.name},
      );
    });
  }

  /// Pays off everything owed now, plus any foreclosure [chargesPaise]
  /// (an expense). Remaining installments are cancelled.
  Future<void> foreclose(
    int loanId, {
    required DateTime date,
    required String account,
    int chargesPaise = 0,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final loan = await _load(txn, loanId);
      final owed = await _outstanding(txn, loan);
      final accId = await _accountId(txn, account);
      final day = isoDate(date);
      int? m, t;
      if (owed > 0) {
        m = await _repayPrincipal(
          txn,
          loan: loan,
          accountId: accId,
          amount: owed,
          date: day,
          note: 'Loan closed · ${loan.name}',
        );
      }
      if (chargesPaise > 0) {
        t = await _expense(
          txn,
          loan: loan,
          category: 'fees',
          amount: chargesPaise,
          date: day,
          account: account,
          note: 'Foreclosure charges · ${loan.name}',
        );
      }
      await txn.update(
        'loan_installments',
        {'status': 'cancelled'},
        where: "loan_id = ? AND status = 'due'",
        whereArgs: [loanId],
      );
      await txn.update(
        'loans',
        {'status': 'closed', 'active': 0},
        where: 'id = ?',
        whereArgs: [loanId],
      );
      await txn.insert('loan_events', {
        'loan_id': loanId,
        'kind': 'foreclosure',
        'amount': owed,
        'date': day,
        'movement_id': m,
        'txn_id': t,
        'created_at': DateTime.now().toIso8601String(),
      });
      await writeAudit(
        txn,
        entity: 'loan',
        entityId: loanId,
        action: 'foreclose',
        after: {'principal': owed, 'charges': chargesPaise},
      );
    });
  }

  /// Sets what's owed to match the lender's figure. No money moves; the
  /// difference is recorded as a correction and the future schedule is
  /// rebuilt (same EMI).
  Future<void> correctOutstanding(
    int loanId,
    int newOutstanding, {
    String? note,
  }) async {
    if (newOutstanding < 0) throw const LoanException("Can't be negative.");
    final db = await _db.database;
    await db.transaction((txn) async {
      final loan = await _load(txn, loanId);
      final owed = await _outstanding(txn, loan);
      final delta = newOutstanding - owed;
      if (delta == 0) return;
      await txn.insert('loan_events', {
        'loan_id': loanId,
        'kind': 'correction',
        'amount': delta,
        'date': isoDate(DateTime.now()),
        'note': note,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _reschedule(txn, loan, newOutstanding, PrepayMode.reduceTenure);
      await _closeIfDone(txn, loan);
      await writeAudit(
        txn,
        entity: 'loan',
        entityId: loanId,
        action: 'correct',
        before: {'outstanding': owed},
        after: {'outstanding': newOutstanding, 'note': note},
      );
    });
  }

  /// Hides a loan. Refused while money is still owed — close it instead.
  Future<bool> remove(int id) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final r = await txn.query('loans', where: 'id = ?', whereArgs: [id]);
      if (r.isEmpty) return false;
      final loan = Loan.fromMap(r.first);
      if (loan.active && await _outstanding(txn, loan) > 0) {
        throw const LoanException(
          'Money is still owed on this loan. Pay it off or correct the balance first.',
        );
      }
      await txn.update(
        'loans',
        {'status': 'closed', 'active': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      await writeAudit(txn, entity: 'loan', entityId: id, action: 'remove');
      return true;
    });
  }

  /// Undoes an installment payment whose interest entry [txnId] is being
  /// deleted: removes its principal movement and rolls the installment
  /// back. Called inside the delete's transaction. Returns false when
  /// [txnId] isn't part of a recorded payment.
  static Future<bool> reversePaymentFor(DatabaseExecutor ex, int txnId) async {
    final rows = await ex.query(
      'loan_payments',
      where: 'txn_id = ?',
      whereArgs: [txnId],
    );
    if (rows.isEmpty) return false;
    await _reverse(ex, rows.first);
    return true;
  }

  /// Undoes the most recent installment payment on [loanId] — its interest
  /// expense, its principal movement and the installment's paid amounts.
  /// Returns false when there's nothing to undo.
  Future<bool> undoLastPayment(int loanId) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'loan_payments',
        where: 'loan_id = ? AND installment_id IS NOT NULL',
        whereArgs: [loanId],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final p = rows.first;
      if (p['txn_id'] != null) {
        await txn.delete('txns', where: 'id = ?', whereArgs: [p['txn_id']]);
      }
      await _reverse(txn, p);
      await writeAudit(
        txn,
        entity: 'loan',
        entityId: loanId,
        action: 'undo_payment',
        before: p,
      );
      return true;
    });
  }

  static Future<void> _reverse(
    DatabaseExecutor ex,
    Map<String, Object?> p,
  ) async {
    final movementId = p['movement_id'] as int?;
    if (movementId != null) {
      await ex.delete(
        'postings',
        where: 'movement_id = ?',
        whereArgs: [movementId],
      );
      await ex.delete('movements', where: 'id = ?', whereArgs: [movementId]);
    }
    await ex.rawUpdate(
      'UPDATE loan_installments SET principal_paid = principal_paid - ?, '
      "interest_paid = interest_paid - ?, status = 'due' WHERE id = ?",
      [p['principal'] ?? 0, p['interest'] ?? 0, p['installment_id']],
    );
    await ex.update(
      'loans',
      {'status': 'active', 'active': 1},
      where: 'id = ?',
      whereArgs: [p['loan_id']],
    );
    await ex.delete('loan_payments', where: 'id = ?', whereArgs: [p['id']]);
  }
}
