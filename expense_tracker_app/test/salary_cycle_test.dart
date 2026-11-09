import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:expense_tracker_app/core/finance/salary_cycle.dart';
import 'package:expense_tracker_app/core/theme/app_theme.dart';
import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/transaction.dart';
import 'package:expense_tracker_app/data/repositories/account_repository.dart';
import 'package:expense_tracker_app/data/repositories/cycle_repository.dart';
import 'package:expense_tracker_app/data/repositories/transaction_repository.dart';
import 'package:expense_tracker_app/features/cycles/cycle_card.dart';
import 'package:expense_tracker_app/features/cycles/cycle_controller.dart';

import 'helpers/sqflite_ffi_setup.dart';

const _profile = SalaryProfile(dayFrom: 7, dayTo: 15);
DateTime d(int m, int day, [int y = 2026]) => DateTime(y, m, day);

CycleRecord rec(int id, DateTime start, {bool closed = false}) =>
    CycleRecord(id: id, start: start, closedAt: closed ? d(12, 20) : null);

void main() {
  group('cycle dates', () {
    test('salary dates decide the cycles, not fixed days', () {
      final cycles = resolveCycles([rec(2, d(12, 12)), rec(1, d(11, 10))]);
      expect(cycles[0].start, d(11, 10));
      expect(cycles[0].end, d(12, 11));
      expect(cycles[1].start, d(12, 12));
      expect(cycles[1].end, isNull);
      expect(cycleOn(cycles, d(12, 11))!.record.id, 1);
      expect(cycleOn(cycles, d(12, 12))!.record.id, 2);
      expect(cycleOn(cycles, d(11, 9)), isNull);
    });

    test('next salary window is the 7th–15th of the following month', () {
      final w = nextSalaryWindow(d(11, 10), _profile);
      expect(w.earliest, d(12, 7));
      expect(w.latest, d(12, 15));
      final feb = nextSalaryWindow(
        d(1, 30),
        const SalaryProfile(dayFrom: 25, dayTo: 31),
      );
      expect(feb.latest, d(2, 28));
    });

    test('money must last to the latest expected day, then salary is late', () {
      final open = resolveCycles([rec(1, d(11, 10))]).single;
      final s = standingOf(open, _profile, d(11, 20));
      expect(s.dayNumber, 11);
      expect(s.daysToLast, 26); // 20 Nov … 15 Dec inclusive
      expect(s.salaryLate, isFalse);
      final late = standingOf(open, _profile, d(12, 16));
      expect(late.salaryLate, isTrue);
      expect(late.daysToLast, isNull);
    });

    test('invalid starts are refused with a reason', () {
      final today = d(12, 20);
      final cycles = resolveCycles([
        rec(1, d(10, 9), closed: true),
        rec(2, d(11, 10)),
        rec(3, d(12, 12)),
      ]);
      expect(validateCycleStart(d(12, 21), cycles, today), contains('future'));
      expect(validateCycleStart(d(11, 10), cycles, today), contains('already'));
      expect(validateCycleStart(d(10, 20), cycles, today), contains('closed'));
      expect(validateCycleStart(d(11, 25), cycles, today), isNull);
      // Moving cycle 3 must stay between its neighbours.
      expect(
        validateCycleStart(d(11, 5), cycles, today, movingId: 3),
        isNotNull,
      );
      expect(validateCycleStart(d(12, 14), cycles, today, movingId: 3), isNull);
      // Cycle 2's previous cycle is closed, so its start is fixed.
      expect(
        validateCycleStart(d(11, 12), cycles, today, movingId: 2),
        contains('closed'),
      );
    });
  });

  group('cycles on the ledger', () {
    setUpAll(initFfiSqflite);

    late AppDatabase app;
    late CycleRepository repo;
    late TransactionRepository txns;
    late AccountRepository accounts;

    setUp(() async {
      app = AppDatabase.forTesting();
      repo = CycleRepository(app);
      txns = TransactionRepository(app);
      accounts = AccountRepository(app);
      await accounts.add('Salary', 500000);
    });

    Future<void> income(String date, int paise) => txns.add(
      Transaction(
        date: date,
        category: 'freelance',
        amountPaise: paise,
        type: TxnType.income,
        createdAt: '${date}T00:00:00.000',
        account: 'Salary',
      ),
    );

    Future<void> expense(String date, int paise) => txns.add(
      Transaction(
        date: date,
        category: 'food',
        amountPaise: paise,
        type: TxnType.expense,
        createdAt: '${date}T00:00:00.000',
        account: 'Salary',
      ),
    );

    test(
      'scenarios 1–2: ₹19,000 salary on 10 Nov, ₹2,000 extra on 20 Nov',
      () async {
        await repo.recordSalary(
          amountPaise: 1900000,
          date: d(11, 10),
          account: 'Salary',
          today: d(11, 21),
        );
        await income('2026-11-20', 200000);
        await expense('2026-11-15', 350000);

        final c = resolveCycles(await repo.list()).single;
        final got = await repo.incomeFor(c, d(11, 21));
        expect(got.salary, 1900000);
        expect(got.additional, 200000);
        expect(got.total, 2100000);
        // Received salary is cash in the account.
        expect(await accounts.balance('Salary'), 500000 + 2100000 - 350000);
        // The calendar month sees the same rows.
        expect((await txns.monthTotal('2026-11')).income, 2100000);
      },
    );

    test('variable salaries; one transaction counted once per view', () async {
      await repo.recordSalary(
        amountPaise: 1900000,
        date: d(11, 10),
        account: 'Salary',
        today: d(12, 20),
      );
      await expense('2026-12-05', 100000);
      await repo.recordSalary(
        amountPaise: 2150000,
        date: d(12, 12),
        account: 'Salary',
        today: d(12, 20),
      );
      final ctrl = CycleController(repo: repo, txnRepo: txns);
      await ctrl.refresh();
      final nov = await ctrl.summaryFor(ctrl.cycles.first, today: d(12, 20));
      final dec = await ctrl.summaryFor(ctrl.cycles.last, today: d(12, 20));
      expect(nov.cycle.end, d(12, 11));
      expect(nov.income.salary, 1900000);
      expect(nov.spent, 100000); // 5 Dec is in the Nov–Dec cycle …
      expect(dec.income.salary, 2150000);
      expect(dec.spent, 0);
      // … and in December's calendar month, from the same single row.
      expect((await txns.monthTotal('2026-12')).expense, 100000);
      final db = await app.database;
      expect(await db.query('txns', where: "type = 'expense'"), hasLength(1));
    });

    test(
      'salary already inside the opening balance is not added again',
      () async {
        await repo.recordSalary(
          amountPaise: 1900000,
          date: d(11, 10),
          account: 'Salary',
          alreadyInBalance: true,
          today: d(11, 21),
        );
        expect(await accounts.balance('Salary'), 500000);
        expect((await txns.monthTotal('2026-11')).income, 0);
        final c = resolveCycles(await repo.list()).single;
        expect((await repo.incomeFor(c, d(11, 21))).salary, 1900000);
      },
    );

    test('a salary can join a cycle started without one, only once', () async {
      await repo.startCycle(d(11, 10), today: d(11, 21));
      await repo.recordSalary(
        amountPaise: 1900000,
        date: d(11, 10),
        account: 'Salary',
        today: d(11, 21),
      );
      expect(await repo.list(), hasLength(1));
      await expectLater(
        repo.recordSalary(
          amountPaise: 1,
          date: d(11, 10),
          account: 'Salary',
          today: d(11, 21),
        ),
        throwsA(isA<CycleException>()),
      );
    });

    test('closed cycles never move (rule 15)', () async {
      final first = await repo.startCycle(d(10, 9), today: d(12, 20));
      final second = await repo.startCycle(d(11, 10), today: d(12, 20));
      final db = await app.database;
      await db.update(
        'income_cycles',
        {'closed_at': '2026-11-10T00:00:00.000'},
        where: 'id = ?',
        whereArgs: [first],
      );
      Future<void> refused(Future<void> f) =>
          expectLater(f, throwsA(isA<CycleException>()));
      await refused(repo.moveStart(first, d(10, 1), today: d(12, 20)));
      await refused(repo.moveStart(second, d(11, 12), today: d(12, 20)));
      await refused(repo.remove(second));
      await refused(repo.startCycle(d(10, 20), today: d(12, 20)));
    });

    test(
      'moving a start is audited; a deleted salary entry counts as zero',
      () async {
        final id = await repo.recordSalary(
          amountPaise: 1900000,
          date: d(11, 10),
          account: 'Salary',
          today: d(11, 21),
        );
        await repo.moveStart(id, d(11, 11), today: d(11, 21));
        final db = await app.database;
        final audit = await db.query(
          'audit_log',
          where: "entity = 'cycle' AND action = 'move'",
        );
        expect(audit.single['before_json'], '{"start_date":"2026-11-10"}');

        final salaryTxn = (await db.query('txns')).single['id'] as int;
        await txns.deleteById(salaryTxn);
        final c = resolveCycles(await repo.list()).single;
        expect((await repo.incomeFor(c, d(11, 21))).salary, 0);
      },
    );

    test('profile rejects an impossible day range', () {
      expect(
        () => repo.saveProfile(const SalaryProfile(dayFrom: 16, dayTo: 7)),
        throwsA(isA<CycleException>()),
      );
    });
  });

  test('v13 -> v14 adds the cycle tables', () async {
    initFfiSqflite();
    final tmp = await Directory.systemTemp.createTemp('spendo_v14');
    addTearDown(() => tmp.delete(recursive: true));
    final path = '${tmp.path}/spendo.db';
    var app = AppDatabase.forTesting(path);
    var db = await app.database;
    await db.execute('DROP TABLE income_cycles');
    await db.execute('DROP TABLE salary_profile');
    await db.execute('PRAGMA user_version = 13');
    await app.close();

    app = AppDatabase.forTesting(path);
    final repo = CycleRepository(app);
    await repo.startCycle(d(11, 10), today: d(11, 21));
    expect(await repo.list(), hasLength(1));
    expect((await repo.profile()).dayFrom, 7);
    await app.close();
  });

  group('CycleCard', () {
    setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

    for (final (size, scale) in [
      (const Size(320, 568), 1.5),
      (const Size(820, 1180), 1.0),
    ]) {
      testWidgets('lays out at $size, text x$scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final cycle = resolveCycles([rec(1, d(11, 10))]).single;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: CycleCard(
                  currency: '₹',
                  summary: CycleSummary(
                    cycle: cycle,
                    income: const CycleIncome(
                      salary: 1900000,
                      additional: 200000,
                    ),
                    spent: 2345678,
                    categories: const {},
                    standing: standingOf(cycle, _profile, d(11, 20)),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(
          find.text('Spent more than this cycle’s income'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
