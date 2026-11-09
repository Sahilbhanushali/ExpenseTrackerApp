import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/core/finance/budgets.dart';
import 'package:expense_tracker_app/core/finance/salary_cycle.dart';
import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/transaction.dart';
import 'package:expense_tracker_app/data/repositories/account_repository.dart';
import 'package:expense_tracker_app/data/repositories/budget_repository.dart';
import 'package:expense_tracker_app/data/repositories/income_repository.dart';
import 'package:expense_tracker_app/data/repositories/transaction_repository.dart';
import 'package:expense_tracker_app/features/budgets/budget_controller.dart';

import 'helpers/sqflite_ffi_setup.dart';

DateTime d(int m, int day, [int y = 2026]) => DateTime(y, m, day);

Transaction expense(String date, int paise, {String category = 'food'}) =>
    Transaction(
      date: date,
      category: category,
      amountPaise: paise,
      type: TxnType.expense,
      createdAt: '${date}T00:00:00.000',
      account: 'Bank',
    );

void main() {
  group('budget periods', () {
    const month = Budget(period: BudgetPeriod.month, limitPaise: 100);
    test('month, week (Mon–Sun) and day contain today', () {
      final m = currentPeriod(month, d(11, 18))!;
      expect((m.start, m.end), (d(11, 1), d(11, 30)));
      final w = currentPeriod(
        const Budget(period: BudgetPeriod.week, limitPaise: 1),
        d(11, 18), // Wednesday
      )!;
      expect((w.start, w.end), (d(11, 16), d(11, 22)));
      final day = currentPeriod(
        const Budget(period: BudgetPeriod.day, limitPaise: 1),
        d(11, 18),
      )!;
      expect(day.days, 1);
    });

    test('a cycle budget lasts to the latest expected salary day', () {
      const b = Budget(period: BudgetPeriod.cycle, limitPaise: 1);
      final cycle = resolveCycles([CycleRecord(id: 1, start: d(11, 10))])
          .single;
      final r = currentPeriod(b, d(11, 20), cycle: cycle)!;
      expect((r.start, r.end), (d(11, 10), d(12, 15)));
      expect(r.daysLeft(d(11, 20)), 26);
      // Salary late: the period stretches to today.
      expect(currentPeriod(b, d(12, 18), cycle: cycle)!.end, d(12, 18));
      expect(currentPeriod(b, d(11, 20)), isNull);
    });

    test('levels, pace and validation', () {
      expect(budgetLevel(79, 100, 80), BudgetLevel.ok);
      expect(budgetLevel(80, 100, 80), BudgetLevel.caution);
      expect(budgetLevel(100, 100, 80), BudgetLevel.reached);
      expect(budgetLevel(101, 100, 80), BudgetLevel.exceeded);
      final u = BudgetUsage(
        budget: const Budget(period: BudgetPeriod.month, limitPaise: 30000),
        range: PeriodRange(d(11, 1), d(11, 30)),
        spent: 10000,
        daysLeft: 10,
      );
      expect(u.perDayLeft, 2000);
      expect(validateBudget(month, [month]), contains('already'));
      expect(
        validateBudget(
          Budget(
            period: BudgetPeriod.custom,
            limitPaise: 1,
            start: d(11, 10),
            end: d(11, 1),
          ),
          const [],
        ),
        contains('before'),
      );
      expect(
        cycleBudgetGap(2100000, const [
          Budget(
            period: BudgetPeriod.cycle,
            category: 'food',
            limitPaise: 500000,
          ),
          Budget(
            period: BudgetPeriod.cycle,
            category: 'rent',
            limitPaise: 900000,
          ),
        ]),
        700000,
      );
    });
  });

  group('on the ledger', () {
    setUpAll(initFfiSqflite);
    late AppDatabase app;
    late TransactionRepository txns;
    late AccountRepository accounts;

    setUp(() async {
      app = AppDatabase.forTesting();
      txns = TransactionRepository(app);
      accounts = AccountRepository(app);
      await accounts.add('Bank', 1000000);
    });

    test(
      'refunds lower spending, add to the balance, are not income',
      () async {
        final id = await txns.add(expense('2026-11-12', 100000));
        await txns.addRefund(
          expenseId: id,
          amountPaise: 30000,
          date: '2026-11-15',
        );
        final month = await txns.monthTotal('2026-11');
        expect(month.expense, 70000);
        expect(month.income, 0);
        expect((await txns.categoryTotals('2026-11'))['food'], 70000);
        expect(await accounts.balance('Bank'), 1000000 - 100000 + 30000);
        expect(await txns.refundedFor(id), 30000);

        await expectLater(
          txns.addRefund(expenseId: id, amountPaise: 80000, date: '2026-11-16'),
          throwsStateError,
        );
        await expectLater(
          txns.update(id, amountPaise: 20000),
          throwsStateError,
        );
        // Deleting the purchase takes its refunds with it.
        await txns.deleteById(id);
        expect((await txns.monthTotal('2026-11')).expense, 0);
        expect(await accounts.balance('Bank'), 1000000);
      },
    );

    test('expected income is not money until received', () async {
      final income = IncomeRepository(app);
      final id = await income.addExpected(
        ExpectedIncome(
          source: IncomeSource.freelance,
          amountPaise: 500000,
          expectedDate: d(11, 25),
          account: 'Bank',
        ),
      );
      expect(await accounts.balance('Bank'), 1000000);
      await income.markReceived(id, amountPaise: 450000, date: d(11, 26));
      expect(await accounts.balance('Bank'), 1450000);
      final bySource = await income.receivedBySource(d(11, 1), d(11, 30));
      expect(bySource, {IncomeSource.freelance: 450000});
      expect((await income.list(pendingOnly: true)), isEmpty);
      await expectLater(
        income.markReceived(id, amountPaise: 1, date: d(11, 27)),
        throwsA(isA<IncomeException>()),
      );
    });

    test('budgets track their period; income never moves a limit', () async {
      final repo = BudgetRepository(app);
      await repo.save(
        const Budget(period: BudgetPeriod.month, limitPaise: 2000000),
      );
      await repo.save(
        const Budget(
          period: BudgetPeriod.week,
          category: 'food',
          limitPaise: 150000,
          cautionPct: 80,
        ),
      );
      await expectLater(
        repo.save(const Budget(period: BudgetPeriod.month, limitPaise: 1)),
        throwsA(isA<BudgetException>()),
      );
      final ctrl = BudgetController(repo: repo, txnRepo: txns);
      await ctrl.refresh(today: d(11, 18));
      final before = ctrl.levels();

      await txns.add(expense('2026-11-17', 130000));
      await txns.add(
        Transaction(
          date: '2026-11-17',
          category: 'income',
          amountPaise: 200000,
          type: TxnType.income,
          createdAt: '2026-11-17T00:00:00.000',
          account: 'Bank',
          incomeSource: IncomeSource.freelance,
        ),
      );
      await ctrl.refresh(today: d(11, 18));
      final week = ctrl.usages.firstWhere(
        (u) => u.budget.period == BudgetPeriod.week,
      );
      expect(week.spent, 130000);
      expect(week.level, BudgetLevel.caution);
      expect(ctrl.monthOverall, 2000000); // extra income changed nothing
      expect(ctrl.crossedSince(before, '₹').single, contains('86% used'));
    });

    test('old config budgets are imported exactly once', () async {
      final repo = BudgetRepository(app);
      expect(await repo.importLegacy(1700000, {'food': 800000, 'x': 0}), 2);
      expect(await repo.importLegacy(1700000, {'food': 800000}), 0);
      final ctrl = BudgetController(repo: repo, txnRepo: txns);
      await ctrl.refresh();
      expect(ctrl.monthOverall, 1700000);
      expect(ctrl.monthCategoryCaps, {'food': 800000});
    });
  });

  test('v14 -> v15 rebuilds txns without losing a row', () async {
    initFfiSqflite();
    final tmp = await Directory.systemTemp.createTemp('spendo_v15');
    addTearDown(() => tmp.delete(recursive: true));
    final path = '${tmp.path}/spendo.db';
    var app = AppDatabase.forTesting(path);
    var db = await app.database;
    // Wind txns back to the v14 shape (old CHECK, no new columns).
    await db.execute('DROP TABLE txns');
    await db.execute('''
      CREATE TABLE txns (
        id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL,
        category TEXT NOT NULL, amount INTEGER NOT NULL, note TEXT,
        type TEXT NOT NULL CHECK (type IN ('expense', 'income', 'lent', 'borrowed')),
        created_at TEXT NOT NULL, counterparty TEXT, settled INTEGER,
        account TEXT, goal_id INTEGER, loan_id INTEGER,
        source TEXT NOT NULL DEFAULT 'manual', external_ref TEXT)
    ''');
    await db.insert('txns', {
      'id': 41,
      'date': '2026-11-10',
      'category': 'salary',
      'amount': 1900000,
      'type': 'income',
      'created_at': 'x',
    });
    await db.insert('txns', {
      'id': 42,
      'date': '2026-11-11',
      'category': 'food',
      'amount': 25000,
      'type': 'expense',
      'created_at': 'x',
      'external_ref': 'sms-1',
    });
    for (final t in ['expected_income', 'budgets']) {
      await db.execute('DROP TABLE $t');
    }
    await db.execute('PRAGMA user_version = 14');
    await app.close();

    app = AppDatabase.forTesting(path);
    db = await app.database;
    final rows = await db.query('txns', orderBy: 'id');
    expect(rows.map((r) => r['id']), [41, 42]);
    expect(rows.first['income_source'], 'salary');
    expect(rows.last['external_ref'], 'sms-1');
    final txns = TransactionRepository(app);
    await txns.addRefund(expenseId: 42, amountPaise: 5000, date: '2026-11-12');
    expect((await txns.monthTotal('2026-11')).expense, 20000);
    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'txns'",
    );
    expect(
      indexes.map((r) => r['name']),
      containsAll([
        'idx_txns_date',
        'idx_txns_external_ref',
        'idx_txns_refund_of',
      ]),
    );
    await app.close();
  });
}
