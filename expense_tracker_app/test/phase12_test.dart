import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;

import 'package:expense_tracker_app/core/finance/allocation.dart';
import 'package:expense_tracker_app/core/finance/budgets.dart';
import 'package:expense_tracker_app/core/finance/cards.dart';
import 'package:expense_tracker_app/core/finance/cycle_closing.dart';
import 'package:expense_tracker_app/core/finance/salary_cycle.dart';
import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/account.dart';
import 'package:expense_tracker_app/data/models/credit_card.dart';
import 'package:expense_tracker_app/data/models/movement.dart';
import 'package:expense_tracker_app/data/models/recurring_bill.dart';
import 'package:expense_tracker_app/data/models/transaction.dart';
import 'package:expense_tracker_app/data/repositories/account_repository.dart';
import 'package:expense_tracker_app/data/repositories/allocation_repository.dart';
import 'package:expense_tracker_app/data/repositories/budget_repository.dart';
import 'package:expense_tracker_app/data/repositories/card_repository.dart';
import 'package:expense_tracker_app/data/repositories/cycle_repository.dart';
import 'package:expense_tracker_app/data/repositories/goal_repository.dart';
import 'package:expense_tracker_app/data/repositories/investment_repository.dart';
import 'package:expense_tracker_app/data/repositories/loan_repository.dart';
import 'package:expense_tracker_app/data/repositories/reconciliation_repository.dart';
import 'package:expense_tracker_app/data/repositories/recurring_repository.dart';
import 'package:expense_tracker_app/data/repositories/transaction_repository.dart';
import 'package:expense_tracker_app/features/accounts/accounts_controller.dart';
import 'package:expense_tracker_app/features/allocation/allocation_needs.dart';
import 'package:expense_tracker_app/features/budgets/budget_controller.dart';
import 'package:expense_tracker_app/features/cards/cards_controller.dart';
import 'package:expense_tracker_app/features/cycles/cycle_closing_service.dart';
import 'package:expense_tracker_app/features/cycles/cycle_controller.dart';
import 'package:expense_tracker_app/features/lending/lending_controller.dart';
import 'package:expense_tracker_app/features/loans/loans_controller.dart';

import 'fixtures/app_database_v12.dart';
import 'helpers/sqflite_ffi_setup.dart';

DateTime d(int m, int day, [int y = 2026]) => DateTime(y, m, day);

/// Every table and its columns, for comparing an upgraded file with a
/// freshly created one.
Future<Map<String, Set<String>>> schemaOf(Database db) async {
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  return {
    for (final t in tables)
      t['name'] as String: {
        for (final c in await db.rawQuery('PRAGMA table_info(${t['name']})'))
          c['name'] as String,
      },
  };
}

Future<Set<String>> indexesOf(Database db) async => {
  for (final r in await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'index' "
    "AND name NOT LIKE 'sqlite_%'",
  ))
    r['name'] as String,
};

void main() {
  setUpAll(initFfiSqflite);

  group('full upgrade from v12', () {
    late Directory tmp;
    late String path;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('spendo_v12_full');
      path = '${tmp.path}/spendo.db';
    });
    tearDown(() => tmp.delete(recursive: true));

    /// A real v12 file, created by the v12 code itself, with data in it.
    Future<int> seedV12() async {
      final old = AppDatabaseV12.forTesting(path);
      final db = await old.database;
      Future<void> account(String name, int opening, String type, [int? v]) =>
          db.insert('accounts', {
            'name': name,
            'opening_balance': opening,
            'is_default': name == 'Salary' ? 1 : 0,
            'created_at': '2026-01-01T00:00:00.000',
            'type': type,
            'current_value': v,
          });
      await account('Salary', 1000000, 'cash');
      await account('Savings', 500000, 'cash');
      await account('Rainy day', 200000, 'emergency_fund');
      await account('Broker', 100000, 'investment', 120000);
      Future<int> txn(
        String date,
        String type,
        int amount, {
        String category = 'food',
        String? who,
        int? settled,
      }) => db.insert('txns', {
        'date': date,
        'category': category,
        'amount': amount,
        'type': type,
        'created_at': '${date}T00:00:00.000',
        'account': 'Salary',
        'counterparty': who,
        'settled': settled,
      });
      await txn('2026-11-10', 'income', 1900000, category: 'salary');
      await txn('2026-11-12', 'expense', 250000);
      // Lent ₹5,000, ₹2,000 back: v12 shrank the row to ₹3,000 in place
      // and kept the payment as history.
      final lent = await txn(
        '2026-10-01',
        'lent',
        300000,
        category: 'lending',
        who: 'Ravi',
        settled: 0,
      );
      await db.insert('loan_payments', {
        'loan_id': lent,
        'owner_type': 'person_loan',
        'amount': 200000,
        'date': '2026-10-15',
        'created_at': '2026-10-15T00:00:00.000',
      });
      await db.insert('transfers', {
        'from_account': 'Salary',
        'to_account': 'Savings',
        'amount': 300000,
        'date': '2026-11-11',
        'created_at': '2026-11-11T00:00:00.000',
      });
      await db.insert('loans', {
        'name': 'Fridge',
        'principal': 3000000,
        'interest_amount': 0,
        'emi_amount': 500000,
        'tenure_months': 6,
        'installments_paid': 1,
        'start_date': '2026-10-05',
        'account': 'Salary',
        'active': 1,
      });
      await db.insert('goals', {
        'name': 'Trip',
        'target': 1000000,
        'created_at': '2026-01-01T00:00:00.000',
      });
      await db.insert('recurring', {
        'amount': 800000,
        'category': 'rent',
        'note': 'Rent',
        'day_of_month': 1,
        'active': 1,
        'type': 'expense',
      });
      expect(await db.getVersion(), 12);
      await old.close();
      return lent;
    }

    const salaryBalance =
        1000000 + 1900000 - 250000 - 300000 /* lent, net */ - 300000;

    test('runs every step to the current version; schema matches a fresh '
        'install; balances, debts and history survive', () async {
      final lent = await seedV12();
      final app = AppDatabase.forTesting(path);
      final db = await app.database;
      expect(await db.getVersion(), 20);

      final fresh = AppDatabase.forTesting();
      final freshDb = await fresh.database;
      expect(await schemaOf(db), await schemaOf(freshDb));
      expect(await indexesOf(db), containsAll(await indexesOf(freshDb)));

      final accounts = AccountRepository(app);
      expect(await accounts.allBalances(), {
        'Salary': salaryBalance,
        'Savings': 800000,
        'Rainy day': 200000,
        'Broker': 100000,
      });
      final roles = {for (final a in await accounts.list()) a.name: a.roles};
      expect(roles['Rainy day'], {AccountRole.emergency});
      expect(roles['Broker'], {AccountRole.investment});

      // B6 on an upgraded entry: the old payment isn't subtracted twice.
      final txns = TransactionRepository(app);
      final lending = LendingController(
        txnRepo: txns,
        recurringRepo: RecurringRepository(app),
        accountRepo: accounts,
      );
      await lending.refresh();
      final row = lending.outstanding.single;
      expect(lending.remaining(row), 300000);
      expect(
        lending.originalAmount(row, await lending.paymentHistory(lent)),
        500000,
      );
      // A new repayment is dated today and leaves the entry alone.
      final r = await lending.repay(lent, 100000);
      expect(
        (r!.applied, r.remaining, r.row.amountPaise),
        (100000, 200000, 300000),
      );
      expect(lending.remaining(lending.outstanding.single), 200000);
      expect(
        lending.originalAmount(
          lending.outstanding.single,
          await lending.paymentHistory(lent),
        ),
        500000,
      );
      expect(await accounts.balance('Salary'), salaryBalance + 100000);

      // Older modules read their upgraded rows.
      final loans = LoansController(
        loanRepo: LoanRepository(app),
        txnRepo: txns,
      );
      await loans.refresh();
      expect(loans.loans.single.loan.name, 'Fridge');
      expect(loans.outstanding, greaterThan(0));
      expect((await GoalRepository(app).list()).single.name, 'Trip');
      expect(
        (await RecurringRepository(app).list()).single.amountPaise,
        800000,
      );
      expect((await txns.monthTotal('2026-11')).income, 1900000);
      await fresh.close();
      await app.close();
    });

    test('every step is safe to run again', () async {
      await seedV12();
      var app = AppDatabase.forTesting(path);
      final before = await AccountRepository(app).allBalances();
      final db = await app.database;
      final movements = (await db.query('movements')).length;
      await db.execute('PRAGMA user_version = 12');
      await app.close();

      app = AppDatabase.forTesting(path);
      final again = await app.database;
      expect(await again.getVersion(), 20);
      expect(await AccountRepository(app).allBalances(), before);
      expect(await again.query('movements'), hasLength(movements));
      await app.close();
    });
  });

  group('November, end to end (scenarios 1–10)', () {
    test('one salary cycle through every scenario', () async {
      final app = AppDatabase.forTesting();
      final txns = TransactionRepository(app);
      final accounts = AccountRepository(app);
      final cards = CardRepository(app);
      final cycles = CycleRepository(app);
      final recon = ReconciliationRepository(app);
      await accounts.add(
        'Salary',
        100000,
        roles: {AccountRole.salary, AccountRole.daily},
      );
      await accounts.add('Savings', 500000, roles: {AccountRole.savings});
      await accounts.add('Emergency', 3000000, roles: {AccountRole.emergency});
      final card = await cards.save(
        const CreditCard(
          name: 'HDFC',
          limitPaise: 10000000,
          statementDay: 14,
          repaymentAccount: 'Salary',
        ),
      );
      await BudgetRepository(app).save(
        const Budget(
          period: BudgetPeriod.month,
          category: 'groceries',
          limitPaise: 1000000,
          essential: true,
        ),
      );
      await RecurringRepository(app).add(
        const RecurringBill(
          amountPaise: 800000,
          category: 'rent',
          note: 'Rent',
          dayOfMonth: 1,
        ),
      );
      Future<int> spend(
        String date,
        int paise, {
        String category = 'groceries',
        int? onCard,
      }) => txns.add(
        Transaction(
          date: date,
          category: category,
          amountPaise: paise,
          type: TxnType.expense,
          createdAt: '${date}T00:00:00.000',
          account: onCard == null ? 'Salary' : null,
          cardId: onCard,
        ),
      );

      // Before the cycle: the fridge on the card, turned into an EMI.
      final fridge = await spend(
        '2026-10-01',
        3000000,
        category: 'appliances',
        onCard: card,
      );
      final emi = await cards.addEmi(
        CardEmi(
          cardId: card,
          purchaseTxnId: fridge,
          description: 'Fridge',
          purchaseAmount: 3000000,
          purchaseDate: d(10, 1),
          tenureMonths: 6,
          installment: 520000,
        ),
      );

      // Scenario 1: ₹19,000 salary on 10 November.
      await cycles.recordSalary(
        amountPaise: 1900000,
        date: d(11, 10),
        account: 'Salary',
        today: d(11, 10),
      );
      Future<CycleRange> nov() async =>
          resolveCycles(await cycles.list()).first;
      expect((await nov()).start, d(11, 10));
      expect(await accounts.balance('Salary'), 2000000);

      // Scenario 7: ₹3,000 salary → savings — not income, not spending.
      await accounts.addTransfer(
        const Transfer(
          fromAccount: 'Salary',
          toAccount: 'Savings',
          amountPaise: 300000,
          date: '2026-11-11',
          createdAt: 'x',
        ),
      );
      await spend('2026-11-12', 250000);
      expect(await accounts.balance('Savings'), 800000);
      expect(await txns.totalsRange(d(11, 10), d(11, 12)), isA<MonthTotal>());
      var nov12 = await txns.totalsRange(d(11, 10), d(11, 12));
      expect((nov12.income, nov12.expense), (1900000, 250000));

      // Scenarios 3 & 5: statement on 14 Nov carries the fridge EMI.
      final stmt = await cards.addStatement(
        CardStatement(
          cardId: card,
          periodStart: d(10, 15),
          periodEnd: d(11, 14),
          generatedOn: d(11, 14),
          dueDate: d(11, 29),
          figures: const StatementFigures(
            totalDue: 640000,
            minimumDue: 32000,
            emiInstallments: 520000,
            charges: 120000,
          ),
        ),
        billedEmis: {emi: (principal: null, interest: null)},
        newCharges: 120000,
      );
      // The fridge counts once (October); November only sees the charges.
      expect((await txns.monthTotal('2026-10')).expense, 3000000);
      expect((await txns.monthTotal('2026-11')).expense, 250000 + 120000);
      expect((await cards.outstanding())[card], 3000000 + 120000);

      // Scenario 4: due 29 November.
      var st = (await cards.statements(card)).single;
      expect(st.standing(d(11, 28)).state, StatementState.unpaid);
      expect(st.standing(d(11, 30)).state, StatementState.overdue);

      // Allocation, from the same data the app uses.
      final accountsCtrl = AccountsController(
        accounts,
        recon,
        InvestmentRepository(app),
      );
      final cardsCtrl = CardsController(cards, recon);
      final budgets = BudgetController(
        repo: BudgetRepository(app),
        txnRepo: txns,
      );
      final bills = await RecurringRepository(app).list();
      const settings = AllocationSettings(
        emergencyTarget: 5000000,
        emergencyMonthly: 500000,
        investPerCycle: 200000,
      );
      Future<(AllocationSnapshot, AllocationPlan)> plan(DateTime today) async {
        await accountsCtrl.refresh();
        await cardsCtrl.refresh();
        await budgets.refresh(today: today);
        final s = AllocationSnapshot(
          today: today,
          horizon: d(12, 15),
          currency: '₹',
          accounts: accountsCtrl.accounts,
          budgets: budgets.usages,
          cards: cardsCtrl.cards,
          loans: const [],
          bills: bills,
          settings: settings,
        );
        return (s, allocate(available: s.liquid, needs: buildNeeds(s)));
      }

      // Scenarios 9 & 10 on 15 Nov: groceries left ₹7,500, card ₹6,400,
      // rent ₹8,000 against ₹14,500 of spendable cash.
      var (snap, p) = await plan(d(11, 15));
      expect(snap.liquid, 2000000 - 300000 - 250000);
      // Scenario 10: savings (₹8,000) and emergency (₹30,000) aren't in it.
      final byKey = {for (final l in p.lines) l.need.bucket: l};
      expect(
        p.lines
            .where((l) => l.need.bucket == AllocBucket.emergency)
            .single
            .need
            .required,
        500000,
      );
      expect(p.proposedTotal, snap.liquid);
      expect(p.criticalShortfall, 750000 + 640000 + 800000 - 1450000);
      expect(byKey[AllocBucket.investing]!.proposed, 0);
      expect(byKey[AllocBucket.investing]!.skippedBecause, isNotNull);
      expect(byKey[AllocBucket.emergency]!.proposed, 0);

      // Scenario 2: ₹2,000 more on 20 Nov raises cycle income and cash.
      await txns.add(
        const Transaction(
          date: '2026-11-20',
          category: 'freelance',
          amountPaise: 200000,
          type: TxnType.income,
          createdAt: 'x',
          account: 'Salary',
        ),
      );
      final income = await cycles.incomeFor(await nov(), d(11, 21));
      expect(
        (income.salary, income.additional, income.total),
        (1900000, 200000, 2100000),
      );
      (snap, p) = await plan(d(11, 20));
      expect(snap.liquid, 1650000);
      expect(p.criticalShortfall, 2190000 - 1650000);

      // Scenario 6: the bill is paid from the salary account on 25 Nov —
      // debt settled, not new spending (rule 2).
      await cards.pay(
        cardId: card,
        fromAccount: 'Salary',
        amountPaise: 640000,
        date: d(11, 25),
        statementId: stmt,
      );
      st = (await cards.statements(card)).single;
      expect(st.standing(d(11, 30)).state, StatementState.paid);
      expect(await accounts.balance('Salary'), 1650000 - 640000);
      expect((await cards.outstanding())[card], 3120000 - 640000);
      expect((await txns.monthTotal('2026-11')).expense, 370000);
      (snap, p) = await plan(d(11, 26));
      expect(
        p.lines.where((l) => l.need.key.startsWith('card:')),
        isEmpty,
        reason: 'a paid statement is no longer a need',
      );

      // Scenario 8: December's salary arrives; November's leftover is
      // carried forward, and the cycle freezes.
      await cycles.recordSalary(
        amountPaise: 2100000,
        date: d(12, 12),
        account: 'Salary',
        today: d(12, 12),
      );
      final service = CycleClosingService(
        cycles: cycles,
        txns: txns,
        accounts: accounts,
        cards: cards,
        loans: LoanRepository(app),
      );
      final preview = await service.preview(
        await nov(),
        unallocatedNow: (await accounts.balance('Salary'))!,
        reserved: 0,
        today: d(12, 12),
      );
      expect((preview.income.total, preview.spent), (2100000, 370000));
      expect(preview.leftover, 2100000 - 370000);
      final salaryBefore = await accounts.balance('Salary');
      await service.close(
        preview,
        [
          LeftoverAction(
            kind: LeftoverKind.carryForward,
            amountPaise: preview.leftover,
            label: 'Carry forward',
          ),
        ],
        source: 'Salary',
        today: d(12, 12),
      );
      expect(await accounts.balance('Salary'), salaryBefore);
      expect((await txns.monthTotal('2026-12')).expense, 0);
      final closed = await nov();
      expect(closed.record.isClosed, isTrue);
      final ctrl = CycleController(repo: cycles, txnRepo: txns);
      await ctrl.refresh();
      final frozen = await ctrl.summaryFor(closed);
      expect(frozen.frozen, isNotNull);
      expect(frozen.spent, 370000);

      // The whole month, counted once each way.
      final novTotals = await txns.monthTotal('2026-11');
      expect((novTotals.income, novTotals.expense), (2100000, 370000));
      expect(await accounts.allBalances(), {
        'Salary': 100000 + 2100000 - 300000 - 250000 - 640000 + 2100000,
        'Savings': 800000,
        'Emergency': 3000000,
      });
      final db = await app.database;
      expect(
        await db.query(
          'movements',
          where: "status = 'completed' AND kind = ?",
          whereArgs: [MovementKind.cardPayment.name],
        ),
        hasLength(1),
      );
      await app.close();
    });
  });
}
