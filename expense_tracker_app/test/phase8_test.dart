import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/core/finance/cycle_closing.dart';
import 'package:expense_tracker_app/core/finance/salary_cycle.dart';
import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/account.dart';
import 'package:expense_tracker_app/data/models/credit_card.dart';
import 'package:expense_tracker_app/data/models/transaction.dart';
import 'package:expense_tracker_app/data/repositories/account_repository.dart';
import 'package:expense_tracker_app/data/repositories/card_repository.dart';
import 'package:expense_tracker_app/data/repositories/cycle_repository.dart';
import 'package:expense_tracker_app/data/repositories/loan_repository.dart';
import 'package:expense_tracker_app/data/repositories/transaction_repository.dart';
import 'package:expense_tracker_app/features/cycles/cycle_closing_service.dart';
import 'package:expense_tracker_app/features/cycles/cycle_controller.dart';

import 'helpers/sqflite_ffi_setup.dart';

DateTime d(int m, int day, [int y = 2026]) => DateTime(y, m, day);

void main() {
  group('closing rules', () {
    test('leftover never exceeds what the cycle left or what is free now', () {
      expect(
        leftoverAvailable(cycleNet: 400000, unallocatedNow: 2500000),
        400000,
      );
      expect(
        leftoverAvailable(cycleNet: 400000, unallocatedNow: 100000),
        100000,
      );
      expect(leftoverAvailable(cycleNet: -50000, unallocatedNow: 900000), 0);
    });

    test('choices are validated', () {
      const save = LeftoverAction(
        kind: LeftoverKind.savings,
        amountPaise: 300000,
        target: 'Savings',
        label: 's',
      );
      expect(validateLeftover([save], 400000), isNull);
      expect(validateLeftover([save, save], 400000), contains('more than'));
      expect(
        validateLeftover(const [
          LeftoverAction(
            kind: LeftoverKind.savings,
            amountPaise: 1,
            label: 's',
          ),
        ], 400000),
        contains('Pick where'),
      );
      expect(
        validateLeftover(const [
          LeftoverAction(
            kind: LeftoverKind.carryForward,
            amountPaise: 0,
            label: 'c',
          ),
        ], 400000),
        isNotNull,
      );
    });

    test('a frozen summary reads back exactly', () {
      final s = CycleCloseSummary(
        start: d(11, 10),
        end: d(12, 11),
        salary: 1900000,
        additionalIncome: 200000,
        spent: 1500000,
        categories: const {'food': 500000},
        balances: const {'Salary': 600000},
        cardsOwed: 0,
        loansOutstanding: 0,
        reservedAtClose: 0,
        unpaidObligations: const {},
        leftoverAvailable: 600000,
        actions: const [
          LeftoverAction(
            kind: LeftoverKind.carryForward,
            amountPaise: 100000,
            label: 'c',
          ),
        ],
        closedAt: d(12, 12),
      );
      final r = CycleCloseSummary.decode(s.encode());
      expect(
        (r.net, r.carriedForward, r.rulesVersion),
        (600000, 100000, kClosingRulesVersion),
      );
      expect(r.categories, {'food': 500000});
    });
  });

  group('closing on the ledger', () {
    setUpAll(initFfiSqflite);
    late AppDatabase app;
    late AccountRepository accounts;
    late TransactionRepository txns;
    late CycleRepository cycles;
    late CardRepository cards;
    late CycleClosingService service;

    setUp(() async {
      app = AppDatabase.forTesting();
      accounts = AccountRepository(app);
      txns = TransactionRepository(app);
      cycles = CycleRepository(app);
      cards = CardRepository(app);
      service = CycleClosingService(
        cycles: cycles,
        txns: txns,
        accounts: accounts,
        cards: cards,
        loans: LoanRepository(app),
      );
      await accounts.add(
        'Salary',
        0,
        roles: {AccountRole.salary, AccountRole.daily},
      );
      await accounts.add('Savings', 0, roles: {AccountRole.savings});
      await cycles.recordSalary(
        amountPaise: 1900000,
        date: d(11, 10),
        account: 'Salary',
        today: d(12, 20),
      );
      await txns.add(
        const Transaction(
          date: '2026-11-20',
          category: 'food',
          amountPaise: 1500000,
          type: TxnType.expense,
          createdAt: 'x',
          account: 'Salary',
        ),
      );
      await cycles.recordSalary(
        amountPaise: 2100000,
        date: d(12, 12),
        account: 'Salary',
        today: d(12, 20),
      );
    });

    Future<CycleRange> nov() async => resolveCycles(await cycles.list()).first;

    test(
      'scenario 8: the leftover is carried forward and split; history freezes',
      () async {
        final cardId = await cards.save(
          const CreditCard(
            name: 'HDFC',
            limitPaise: 1000000,
            openingOutstandingPaise: 300000,
          ),
        );
        // ₹25,000 is free now, but only ₹4,000 is November's leftover.
        final p = await service.preview(
          await nov(),
          unallocatedNow: 2500000,
          reserved: 0,
          today: d(12, 20),
        );
        expect((p.net, p.leftover), (400000, 400000));
        expect(p.balances['Salary'], 400000);

        await service.close(
          p,
          [
            const LeftoverAction(
              kind: LeftoverKind.carryForward,
              amountPaise: 100000,
              label: 'Carry',
            ),
            const LeftoverAction(
              kind: LeftoverKind.savings,
              amountPaise: 200000,
              target: 'Savings',
              label: 'Save',
            ),
            LeftoverAction(
              kind: LeftoverKind.cardPayment,
              amountPaise: 100000,
              target: 'card:$cardId',
              label: 'Card',
            ),
          ],
          source: 'Salary',
          today: d(12, 20),
        );
        expect(await accounts.balance('Savings'), 200000);
        expect(await accounts.balance('Salary'), 400000 + 2100000 - 300000);
        expect((await cards.outstanding())[cardId], 200000);
        // Moving leftover is never spending or income.
        expect((await txns.monthTotal('2026-12')).expense, 0);

        final closed = await nov();
        expect(closed.record.isClosed, isTrue);
        final ctrl = CycleController(repo: cycles, txnRepo: txns);
        await ctrl.refresh();
        final frozen = await ctrl.summaryFor(closed);
        expect(frozen.frozen!.actions.length, 3);
        expect(frozen.spent, 1500000);

        // Editing an old entry doesn't silently rewrite the closed cycle.
        final food = (await txns.queryPage(type: TxnType.expense)).single;
        await txns.update(food.id!, amountPaise: 1600000);
        expect((await ctrl.summaryFor(closed)).spent, 1500000);
        expect((await ctrl.liveSummaryFor(closed)).spent, 1600000);

        // Its dates are fixed; it can only be reopened explicitly.
        await expectLater(
          cycles.moveStart(closed.record.id!, d(11, 9), today: d(12, 20)),
          throwsA(isA<CycleException>()),
        );
        await cycles.reopen(closed.record.id!);
        await ctrl.refresh();
        expect((await ctrl.summaryFor(ctrl.cycles.first)).spent, 1600000);
        final db = await app.database;
        expect(
          await db.query(
            'audit_log',
            where: "entity = 'cycle' AND action IN ('close', 'reopen')",
          ),
          hasLength(2),
        );
      },
    );

    test('nothing is closed or moved when a choice is invalid', () async {
      final p = await service.preview(
        await nov(),
        unallocatedNow: 2500000,
        reserved: 0,
        today: d(12, 20),
      );
      await expectLater(
        service.close(p, const [
          LeftoverAction(
            kind: LeftoverKind.custom,
            amountPaise: 100000,
            target: 'Salary',
            label: 'x',
          ),
        ], source: 'Salary'),
        throwsA(isA<CycleException>()),
      );
      await expectLater(
        service.close(p, const [
          LeftoverAction(
            kind: LeftoverKind.savings,
            amountPaise: 500000,
            target: 'Savings',
            label: 'x',
          ),
        ], source: 'Salary'),
        throwsA(isA<CycleException>()),
      );
      expect((await nov()).record.isClosed, isFalse);
      expect(await accounts.balance('Savings'), 0);
    });

    test('planned transfers at closing wait for the bank', () async {
      final p = await service.preview(
        await nov(),
        unallocatedNow: 2500000,
        reserved: 0,
        today: d(12, 20),
      );
      await service.close(
        p,
        const [
          LeftoverAction(
            kind: LeftoverKind.savings,
            amountPaise: 200000,
            target: 'Savings',
            label: 's',
          ),
        ],
        source: 'Salary',
        transfersDone: false,
        today: d(12, 20),
      );
      expect(await accounts.balance('Savings'), 0);
      expect((await accounts.plannedTransfers()).single.amountPaise, 200000);
    });

    test('an overspent cycle closes with nothing to decide', () async {
      await txns.add(
        const Transaction(
          date: '2026-11-25',
          category: 'rent',
          amountPaise: 900000,
          type: TxnType.expense,
          createdAt: 'x',
          account: 'Salary',
        ),
      );
      final p = await service.preview(
        await nov(),
        unallocatedNow: 2500000,
        reserved: 0,
        today: d(12, 20),
      );
      expect((p.net, p.leftover), (-500000, 0));
      await service.close(p, const [], source: 'Salary', today: d(12, 20));
      expect((await nov()).record.isClosed, isTrue);
    });

    test('the open cycle cannot be closed; reopen goes newest first', () async {
      final open = resolveCycles(await cycles.list()).last;
      await expectLater(
        service.preview(open, unallocatedNow: 0, reserved: 0),
        throwsA(isA<CycleException>()),
      );
    });
  });
}
