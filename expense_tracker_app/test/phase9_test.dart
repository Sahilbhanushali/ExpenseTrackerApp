import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:expense_tracker_app/core/finance/allocation.dart';
import 'package:expense_tracker_app/core/finance/budgets.dart';
import 'package:expense_tracker_app/core/finance/wealth.dart';
import 'package:expense_tracker_app/core/theme/app_theme.dart';
import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/account.dart';
import 'package:expense_tracker_app/data/models/credit_card.dart';
import 'package:expense_tracker_app/data/models/goal.dart';
import 'package:expense_tracker_app/data/models/loan.dart';
import 'package:expense_tracker_app/data/repositories/account_repository.dart';
import 'package:expense_tracker_app/data/repositories/allocation_repository.dart';
import 'package:expense_tracker_app/data/repositories/budget_repository.dart';
import 'package:expense_tracker_app/data/repositories/card_repository.dart';
import 'package:expense_tracker_app/data/repositories/goal_repository.dart';
import 'package:expense_tracker_app/data/repositories/investment_repository.dart';
import 'package:expense_tracker_app/data/repositories/loan_repository.dart';
import 'package:expense_tracker_app/data/repositories/reconciliation_repository.dart';
import 'package:expense_tracker_app/data/repositories/transaction_repository.dart';
import 'package:expense_tracker_app/features/accounts/accounts_controller.dart';
import 'package:expense_tracker_app/features/allocation/allocation_controller.dart';
import 'package:expense_tracker_app/features/allocation/allocation_needs.dart';
import 'package:expense_tracker_app/features/budgets/budget_controller.dart';
import 'package:expense_tracker_app/features/emergency/emergency_controller.dart';
import 'package:expense_tracker_app/features/emergency/emergency_screen.dart';
import 'package:expense_tracker_app/features/goals/goals_controller.dart';
import 'package:expense_tracker_app/features/goals/goals_screen.dart';
import 'package:expense_tracker_app/features/investments/investments_screen.dart';
import 'package:expense_tracker_app/features/settings/settings_controller.dart';

import 'helpers/sqflite_ffi_setup.dart';

DateTime d(int m, int day, [int y = 2026]) => DateTime(y, m, day);

void main() {
  group('wealth maths', () {
    test('goal pace from a target date', () {
      const g = GoalProgress(target: 6000000, saved: 1200000);
      expect((g.remaining, g.percent), (4800000, 20));
      final dated = GoalProgress(
        target: 6000000,
        saved: 1200000,
        targetDate: d(11, 20, 2027),
        monthlyContribution: 300000,
      );
      expect(monthsBetween(d(11, 20), d(11, 20, 2027)), 12);
      expect(dated.requiredMonthly(d(11, 20)), 400000);
      expect(dated.onTrack(d(11, 20)), isFalse);
      expect(dated.suggested(d(11, 20)), 300000);
      expect(
        const GoalProgress(target: 100, saved: 100).suggested(d(1, 1)),
        isNull,
      );
    });

    test('essential monthly: override, then budgets, then spending', () {
      const budgets = [
        Budget(
          period: BudgetPeriod.month,
          category: 'rent',
          limitPaise: 1500000,
          essential: true,
        ),
        Budget(
          period: BudgetPeriod.week,
          category: 'groceries',
          limitPaise: 120000,
          essential: true,
        ),
        Budget(period: BudgetPeriod.month, category: 'fun', limitPaise: 500000),
      ];
      final b = essentialMonthly(
        budgets: budgets,
        averageEssentialSpending: 999,
      );
      expect((b.amount, b.source), (1500000 + 520000, EssentialSource.budgets));
      expect(
        essentialMonthly(
          override: 2500000,
          budgets: budgets,
          averageEssentialSpending: 0,
        ).source,
        EssentialSource.override,
      );
      expect(
        essentialMonthly(
          budgets: const [],
          averageEssentialSpending: 1800000,
        ).source,
        EssentialSource.spending,
      );
    });

    test('emergency fund status and target', () {
      final t = emergencyTarget(months: 6, essentialMonthly: 2000000);
      expect(t, 12000000);
      final s = EmergencyStatus(
        current: 3000000,
        target: t,
        essentialMonthly: 2000000,
      );
      expect((s.shortfall, s.percent, s.coverageMonths), (9000000, 25, 1.5));
      expect(s.suggestedContribution, 750000); // a twelfth of the gap
      expect(emergencyTarget(amount: 5000000, essentialMonthly: 1), 5000000);
    });

    test('an investment account is worth uninvested cash + holdings', () {
      const s = InvestmentStanding(
        balance: 1000000,
        invested: 800000,
        currentValue: 900000,
        holdings: 2,
      );
      expect((s.uninvested, s.worth, s.gain), (200000, 1100000, 100000));
    });
  });

  group('on the ledger', () {
    setUpAll(initFfiSqflite);
    late AppDatabase app;
    late AccountRepository accounts;
    late TransactionRepository txns;
    late GoalRepository goals;

    setUp(() async {
      app = AppDatabase.forTesting();
      accounts = AccountRepository(app);
      txns = TransactionRepository(app);
      goals = GoalRepository(app);
      await accounts.add(
        'Salary',
        2000000,
        roles: {AccountRole.salary, AccountRole.daily},
      );
      await accounts.add('Savings', 0, roles: {AccountRole.savings});
    });

    Future<int> laptop({String? account = 'Savings', int starting = 0}) =>
        goals.save(
          Goal(
            name: 'Laptop',
            targetPaise: 8000000,
            createdAt: 'x',
            account: account,
            startingPaise: starting,
          ),
        );

    test('B3: adding to a goal is a transfer, never spending', () async {
      final id = await laptop();
      await goals.contribute(
        id,
        from: 'Salary',
        amountPaise: 300000,
        date: d(11, 20),
      );
      expect((await txns.monthTotal('2026-11')).expense, 0);
      expect(await accounts.balance('Salary'), 1700000);
      expect(await accounts.balance('Savings'), 300000);
      expect((await goals.saved())[id], 300000);
      // The money is counted once — in the savings account — not again.
      final total = (await accounts.allBalances()).values.fold(
        0,
        (a, b) => a + b,
      );
      expect(total, 2000000);
    });

    test('planned contributions wait; withdrawals are capped', () async {
      final id = await laptop(starting: 100000);
      await goals.contribute(
        id,
        from: 'Salary',
        amountPaise: 200000,
        done: false,
      );
      expect((await goals.saved())[id], 100000);
      await goals.contribute(id, from: 'Salary', amountPaise: 200000);
      await expectLater(
        goals.withdraw(id, to: 'Salary', amountPaise: 400000),
        throwsA(isA<GoalException>()),
      );
      await goals.withdraw(id, to: 'Salary', amountPaise: 50000);
      expect((await goals.saved())[id], 250000);
    });

    test('a goal needs an account; deleting it leaves the money', () async {
      final unlinked = await laptop(account: null);
      await expectLater(
        goals.contribute(unlinked, from: 'Salary', amountPaise: 1),
        throwsA(isA<GoalException>()),
      );
      final id = await laptop();
      await goals.contribute(id, from: 'Salary', amountPaise: 300000);
      await goals.remove(id);
      expect(await accounts.balance('Savings'), 300000);
    });

    test('holdings set an investment account’s worth, counted once', () async {
      await accounts.add('Zerodha', 0, type: AccountType.investment);
      await accounts.addTransfer(
        const Transfer(
          fromAccount: 'Salary',
          toAccount: 'Zerodha',
          amountPaise: 1000000,
          date: '2026-11-10',
          createdAt: 'x',
        ),
      );
      final inv = InvestmentRepository(app);
      await inv.save(
        Holding(
          account: 'Zerodha',
          name: 'Index fund',
          investedPaise: 800000,
          currentValuePaise: 900000,
          asOf: d(11, 20),
        ),
      );
      final ctrl = AccountsController(
        accounts,
        ReconciliationRepository(app),
        inv,
      );
      await ctrl.refresh();
      final z = ctrl.accounts.firstWhere((a) => a.account.name == 'Zerodha');
      expect((z.balance, z.worth), (1000000, 200000 + 900000));
      expect(ctrl.totalFor(AccountType.investment), 1100000);
    });

    test(
      'emergency fund = emergency account balance vs months of essentials',
      () async {
        await accounts.add(
          'Rainy day',
          3000000,
          roles: {AccountRole.emergency},
        );
        final settings = AllocationRepository(app);
        final ctrl = AccountsController(
          accounts,
          ReconciliationRepository(app),
          InvestmentRepository(app),
        );
        await ctrl.refresh();
        final e = EmergencyController(settings: settings, txnRepo: txns);
        e.attach(
          ctrl,
          BudgetController(repo: BudgetRepository(app), txnRepo: txns),
        );
        await e.save(
          months: 6,
          essentialOverride: 2000000,
          monthlyContribution: 500000,
        );
        final s = e.status!;
        expect(
          (s.current, s.target, s.suggestedContribution),
          (3000000, 12000000, 500000),
        );
        expect(e.essentialSource, EssentialSource.override);
        expect((await settings.settings()).emergencyMonths, 6);
      },
    );

    test(
      'goals become allocation needs; a done transfer counts toward them',
      () async {
        final id = await goals.save(
          Goal(
            name: 'Trip',
            targetPaise: 1200000,
            createdAt: 'x',
            account: 'Savings',
            monthlyContributionPaise: 200000,
          ),
        );
        final standing = GoalStanding(
          goal: (await goals.list()).single,
          saved: 0,
        );
        final needs = buildNeeds(
          AllocationSnapshot(
            today: d(11, 20),
            horizon: d(12, 15),
            currency: '₹',
            accounts: const [],
            budgets: const [],
            cards: const [],
            loans: const [],
            bills: const [],
            settings: const AllocationSettings(),
            goals: [standing],
          ),
        );
        final n = needs.single;
        expect(
          (n.key, n.bucket, n.required, n.destination),
          ('goal:$id', AllocBucket.savings, 200000, 'Savings'),
        );
        final repo = AllocationRepository(app);
        await repo.reserve(
          's',
          n,
          amount: 200000,
          destination: 'Savings',
          moveFrom: 'Salary',
        );
        expect((await goals.saved())[id], 0); // planned only
        await repo.markTransferred((await repo.decisions('s')).single.id);
        expect((await goals.saved())[id], 200000);
      },
    );

    test('renaming an account updates everything that names it', () async {
      final card = await CardRepository(app).save(
        const CreditCard(
          name: 'HDFC',
          limitPaise: 1,
          repaymentAccount: 'Salary',
        ),
      );
      await LoanRepository(app).add(
        Loan(
          name: 'Car',
          principalPaise: 100000,
          emiPaise: 50000,
          tenureMonths: 2,
          startDate: d(12, 1),
          account: 'Salary',
        ),
      );
      await laptop(account: 'Salary');
      final salary = (await accounts.list()).firstWhere(
        (a) => a.name == 'Salary',
      );
      await accounts.update(salary.id!, name: 'HDFC Salary');
      expect(
        (await CardRepository(
          app,
        ).list()).firstWhere((c) => c.id == card).repaymentAccount,
        'HDFC Salary',
      );
      expect((await LoanRepository(app).list()).single.account, 'HDFC Salary');
      expect((await goals.list()).single.account, 'HDFC Salary');
    });
  });

  test('v18 -> v19 extends goals and adds holdings', () async {
    initFfiSqflite();
    final tmp = await Directory.systemTemp.createTemp('spendo_v19');
    addTearDown(() => tmp.delete(recursive: true));
    final path = '${tmp.path}/spendo.db';
    var app = AppDatabase.forTesting(path);
    var db = await app.database;
    await db.execute('DROP TABLE investment_holdings');
    for (final c in [
      'target_date',
      'priority',
      'monthly_contribution',
      'account',
      'kind',
      'status',
      'starting_amount',
    ]) {
      await db.execute('ALTER TABLE goals DROP COLUMN $c');
    }
    await db.insert('goals', {
      'name': 'Old goal',
      'target': 500000,
      'created_at': 'x',
    });
    await db.execute('PRAGMA user_version = 18');
    await app.close();
    app = AppDatabase.forTesting(path);
    final g = (await GoalRepository(app).list()).single;
    expect(
      (g.name, g.priority, g.startingPaise, g.account),
      ('Old goal', 2, 0, null),
    );
    expect(await InvestmentRepository(app).list(), isEmpty);
    await app.close();
  });

  group('screens', () {
    setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ]) {
      for (final screen in ['goals', 'emergency', 'investments']) {
        testWidgets('$screen at 320px, 1.5×, $name', (tester) async {
          tester.view.physicalSize = const Size(320, 568);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.5;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final accounts = AccountsController(
            _Accounts(),
            _Recon(),
            _Holdings(),
          );
          await accounts.refresh();
          final goals = GoalsController(goalRepo: _Goals());
          await goals.refresh();
          final emergency = _Emergency();
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider(create: (_) => SettingsController()),
                ChangeNotifierProvider.value(value: accounts),
                ChangeNotifierProvider.value(value: goals),
                ChangeNotifierProvider<EmergencyController>.value(
                  value: emergency,
                ),
                ChangeNotifierProvider(create: (_) => AllocationController()),
              ],
              child: MaterialApp(
                theme: theme(),
                home: switch (screen) {
                  'goals' => const GoalsScreen(),
                  'emergency' => const EmergencyScreen(),
                  _ => InvestmentsScreen(repo: _Holdings()),
                },
              ),
            ),
          );
          await tester.pump(const Duration(seconds: 1));
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -3000),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}

class _Accounts extends AccountRepository {
  _Accounts() : super(AppDatabase.forTesting());
  @override
  Future<List<MoneyAccount>> list() async => const [
    MoneyAccount(
      id: 1,
      name: 'Salary',
      createdAt: 'x',
      roles: {AccountRole.salary, AccountRole.daily},
    ),
    MoneyAccount(
      id: 2,
      name: 'A long savings account name',
      createdAt: 'x',
      roles: {AccountRole.savings},
    ),
    MoneyAccount(
      id: 3,
      name: 'Rainy day',
      createdAt: 'x',
      roles: {AccountRole.emergency},
    ),
    MoneyAccount(
      id: 4,
      name: 'Zerodha',
      createdAt: 'x',
      type: AccountType.investment,
    ),
  ];
  @override
  Future<Map<String, int>> allBalances() async => {
    'Salary': 2000000,
    'A long savings account name': 1500000,
    'Rainy day': 3000000,
    'Zerodha': 1000000,
  };
  @override
  Future<int> unassignedTxnCount() async => 0;
  @override
  Future<List<Transfer>> plannedTransfers() async => const [];
  @override
  Future<List<Transfer>> transfersFor(
    String name, {
    DateTime? from,
    DateTime? to,
  }) async => const [];
}

class _Recon extends ReconciliationRepository {
  _Recon() : super(AppDatabase.forTesting());
  @override
  Future<Map<String, Reconciliation>> latest() async => {};
}

class _Holdings extends InvestmentRepository {
  _Holdings() : super(AppDatabase.forTesting());
  @override
  Future<Map<String, ({int invested, int current, int count})>>
  totals() async => {'Zerodha': (invested: 800000, current: 900000, count: 1)};
  @override
  Future<List<Holding>> list() async => [
    Holding(
      account: 'Zerodha',
      name: 'A very long index fund name',
      investedPaise: 800000,
      currentValuePaise: 900000,
      asOf: DateTime(2026, 11, 20),
    ),
  ];
}

class _Goals extends GoalRepository {
  _Goals() : super(AppDatabase.forTesting());
  @override
  Future<List<Goal>> list() async => [
    Goal(
      id: 1,
      name: 'New laptop with a long name',
      targetPaise: 8000000,
      createdAt: 'x',
      account: 'A long savings account name',
      targetDate: DateTime(2027, 11, 20),
      monthlyContributionPaise: 300000,
      priority: 1,
    ),
    const Goal(
      id: 2,
      name: 'Wealth',
      targetPaise: 100000000,
      createdAt: 'x',
      horizon: GoalHorizon.long,
    ),
  ];
  @override
  Future<Map<int, int>> saved() async => {1: 1200000, 2: 0};
}

class _Emergency extends EmergencyController {
  @override
  EmergencyStatus? get status => const EmergencyStatus(
    current: 3000000,
    target: 12000000,
    essentialMonthly: 2000000,
  );
  @override
  Future<void> refresh() async {}
  @override
  Future<List<(String, String, int)>> withdrawals() async => [
    ('2026-11-01', 'Hospital bill', 500000),
  ];
}
