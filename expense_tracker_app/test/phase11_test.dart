import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:expense_tracker_app/core/finance/budgets.dart';
import 'package:expense_tracker_app/core/finance/calendar_events.dart';
import 'package:expense_tracker_app/core/finance/dashboard.dart';
import 'package:expense_tracker_app/core/theme/app_theme.dart';
import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/account.dart';
import 'package:expense_tracker_app/data/models/loan.dart';
import 'package:expense_tracker_app/data/models/movement.dart';
import 'package:expense_tracker_app/data/models/transaction.dart';
import 'package:expense_tracker_app/data/repositories/account_repository.dart';
import 'package:expense_tracker_app/data/repositories/allocation_repository.dart';
import 'package:expense_tracker_app/data/repositories/budget_repository.dart';
import 'package:expense_tracker_app/data/repositories/card_repository.dart';
import 'package:expense_tracker_app/data/repositories/config_repository.dart';
import 'package:expense_tracker_app/data/repositories/cycle_repository.dart';
import 'package:expense_tracker_app/data/repositories/goal_repository.dart';
import 'package:expense_tracker_app/data/repositories/income_repository.dart';
import 'package:expense_tracker_app/data/repositories/investment_repository.dart';
import 'package:expense_tracker_app/data/repositories/loan_repository.dart';
import 'package:expense_tracker_app/data/repositories/net_worth_repository.dart';
import 'package:expense_tracker_app/data/repositories/reconciliation_repository.dart';
import 'package:expense_tracker_app/data/repositories/recurring_repository.dart';
import 'package:expense_tracker_app/data/repositories/transaction_repository.dart';
import 'package:expense_tracker_app/data/models/app_config.dart';
import 'package:expense_tracker_app/features/accounts/accounts_controller.dart';
import 'package:expense_tracker_app/features/allocation/allocation_controller.dart';
import 'package:expense_tracker_app/features/budgets/budget_controller.dart';
import 'package:expense_tracker_app/features/calendar/calendar_controller.dart';
import 'package:expense_tracker_app/features/cards/cards_controller.dart';
import 'package:expense_tracker_app/features/cycles/cycle_controller.dart';
import 'package:expense_tracker_app/features/dashboard/dashboard_controller.dart';
import 'package:expense_tracker_app/features/dashboard/widgets/net_worth_section.dart';
import 'package:expense_tracker_app/features/dashboard/widgets/overview_cards.dart';
import 'package:expense_tracker_app/features/emergency/emergency_controller.dart';
import 'package:expense_tracker_app/features/expenses/expenses_controller.dart';
import 'package:expense_tracker_app/features/goals/goals_controller.dart';
import 'package:expense_tracker_app/features/income/income_controller.dart';
import 'package:expense_tracker_app/features/lending/lending_controller.dart';
import 'package:expense_tracker_app/features/loans/loans_controller.dart';
import 'package:expense_tracker_app/features/recurring/recurring_controller.dart';
import 'package:expense_tracker_app/features/settings/settings_controller.dart';

import 'helpers/sqflite_ffi_setup.dart';

DateTime day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + offset);
}

String iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _Config extends ConfigRepository {
  AppConfig stored = const AppConfig();
  @override
  Future<AppConfig> load() async => stored;
  @override
  Future<void> save(AppConfig config) async => stored = config;
}

MoneyAccount acc(
  String name, {
  AccountType type = AccountType.cash,
  Set<AccountRole> roles = const {},
  AccountStatus status = AccountStatus.active,
  int hold = 0,
}) => MoneyAccount(
  name: name,
  createdAt: 'x',
  type: type,
  roles: roles,
  status: status,
  holdPaise: hold,
);

FinEvent ev(String key, DateTime date, EventKind kind, int amount) => FinEvent(
  key: key,
  date: date,
  kind: kind,
  title: key,
  amount: amount,
  flow: kind == EventKind.statement ? MoneyFlow.info : MoneyFlow.outgoing,
);

BudgetUsage usage(String category, int spent, int limit) => BudgetUsage(
  budget: Budget(
    period: BudgetPeriod.month,
    category: category,
    limitPaise: limit,
  ),
  range: PeriodRange(DateTime(2026, 11), DateTime(2026, 11, 30)),
  spent: spent,
  daysLeft: 10,
);

void main() {
  group('financial position', () {
    test('each account counted once; actual vs reserved vs available', () {
      final p = FinancialPosition.from(
        [
          (
            account: acc('Salary', roles: {AccountRole.salary}, hold: 100000),
            balance: 2100000,
            worth: 2100000,
          ),
          (account: acc('Wallet'), balance: 50000, worth: 50000),
          (
            account: acc('Savings', roles: {AccountRole.savings}),
            balance: 500000,
            worth: 500000,
          ),
          (
            account: acc('Rainy', type: AccountType.emergencyFund),
            balance: 1000000,
            worth: 1000000,
          ),
          (
            // A savings account that also invests counts as investing.
            account: acc(
              'Broker',
              roles: {AccountRole.investment, AccountRole.savings},
            ),
            balance: 300000,
            worth: 350000,
          ),
          (
            account: acc('Old', status: AccountStatus.closed),
            balance: 20000,
            worth: 20000,
          ),
        ],
        reserved: 400000,
        receivables: 10000,
        borrowed: 5000,
        loans: 900000,
        cards: 320000,
      );
      expect(p.inAccounts, 2150000); // closed account isn't spendable
      expect(p.onHold, 100000);
      expect(p.available, 2150000 - 100000 - 400000);
      expect(
        (p.cash, p.savings, p.emergency, p.investments),
        (2170000, 500000, 1000000, 350000),
      );
      expect(p.debt, 1225000);
      expect(
        p.netWorth.total,
        2170000 + 500000 + 1000000 + 350000 + 10000 - 1225000,
      );
    });

    test('debt overview: next dues and overdue obligations only', () {
      final today = DateTime(2026, 11, 20);
      final d = debtOverview(
        [
          ev('emi-late', DateTime(2026, 11, 5), EventKind.emi, 150000),
          ev('card', DateTime(2026, 11, 29), EventKind.cardDue, 320000),
          ev('stmt', DateTime(2026, 12, 14), EventKind.statement, 0),
          ev('emi', DateTime(2026, 12, 5), EventKind.emi, 150000),
          ev('transfer', DateTime(2026, 11, 1), EventKind.transfer, 1),
        ],
        today,
        cards: 320000,
        loans: 900000,
      );
      expect(d.overdue.map((e) => e.key), ['emi-late']);
      expect(d.overdueTotal, 150000);
      expect(d.nextEmi?.key, 'emi');
      expect(d.nextCardDue?.key, 'card');
      expect(d.nextStatement?.key, 'stmt');
      expect(d.total, 1220000);
      expect(
        dueBy(
          [
            ev('emi-late', DateTime(2026, 11, 5), EventKind.emi, 150000),
            ev('card', DateTime(2026, 11, 29), EventKind.cardDue, 320000),
            ev('emi', DateTime(2026, 12, 5), EventKind.emi, 150000),
          ],
          today,
          DateTime(2026, 12, 1),
        ),
        470000,
      );
    });

    test('comparable period: same point last month / cycle / before', () {
      expect(
        comparablePeriod(
          DateTime(2026, 11, 1),
          DateTime(2026, 11, 20, 18),
          previousStart: DateTime(2026, 10, 1),
        ),
        (from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 20)),
      );
      // A long month against a short one stops at the short one's end.
      expect(
        comparablePeriod(
          DateTime(2026, 3, 1),
          DateTime(2026, 3, 31),
          previousStart: DateTime(2026, 2, 1),
        ),
        (from: DateTime(2026, 2, 1), to: DateTime(2026, 2, 28)),
      );
      // Cycle that started 10 Nov, previous started 12 Oct.
      expect(
        comparablePeriod(
          DateTime(2026, 11, 10),
          DateTime(2026, 11, 14),
          previousStart: DateTime(2026, 10, 12),
        ),
        (from: DateTime(2026, 10, 12), to: DateTime(2026, 10, 16)),
      );
      expect(comparablePeriod(DateTime(2026, 11, 10), DateTime(2026, 11, 16)), (
        from: DateTime(2026, 11, 3),
        to: DateTime(2026, 11, 9),
      ));
    });
  });

  group('insights', () {
    InsightInput input({
      bool current = true,
      int spent = 1200000,
      int income = 1900000,
      int previousSpent = 1000000,
      Map<String, int> categories = const {'food': 600000, 'travel': 100000},
      Map<String, int> previous = const {'food': 300000, 'travel': 120000},
    }) => InsightInput(
      period: 'month',
      currency: '₹',
      current: current,
      spent: spent,
      income: income,
      previousSpent: previousSpent,
      categories: categories,
      previousCategories: previous,
      movedToSavings: 300000,
      budgets: [
        usage('shopping', 550000, 500000),
        usage('fuel', 170000, 200000),
        usage('rent', 100000, 600000),
      ],
      overdue: [
        ev('Fridge EMI 2', DateTime(2026, 11, 5), EventKind.emi, 150000),
      ],
      criticalShortfall: 250000,
      salaryLate: true,
      emergencyTarget: 6000000,
      emergencyCoverage: 0.4,
    );

    test('most urgent first, figures from the input', () {
      final list = insightsFor(input());
      expect(list.map((i) => i.id), [
        'overdue',
        'shortfall',
        'salary-late',
        'over-budget',
        'pace-up',
        'emergency-low',
        'near-budget',
        'category-jump',
        'kept',
        'saved',
      ]);
      final byId = {for (final i in list) i.id: i};
      expect(byId['overdue']!.title, '1 payment overdue');
      expect(byId['overdue']!.detail, contains('5 Nov'));
      expect(byId['shortfall']!.title, '₹2,500 short before payday');
      expect(byId['over-budget']!.title, 'Over budget: shopping');
      expect(byId['over-budget']!.detail, 'By ₹500 in total.');
      expect(byId['near-budget']!.title, 'Close to the limit: fuel (85%)');
      expect(byId['pace-up']!.title, 'Spending is up 20% on last month');
      expect(byId['category-jump']!.title, 'Food: ₹3,000 more than last month');
      expect(byId['kept']!.title, 'You’ve kept 36% of this month’s income');
      expect(byId['saved']!.title, '₹3,000 moved to savings this month');
    });

    test('a past period only talks about its own figures', () {
      final ids = insightsFor(input(current: false)).map((i) => i.id).toSet();
      expect(ids, {'pace-up', 'category-jump', 'kept', 'saved'});
    });

    test('small changes are noise; overspending is called out', () {
      final ids = insightsFor(
        input(
          current: false,
          spent: 1050000,
          income: 1000000,
          previousSpent: 1020000,
          categories: {'food': 330000},
          previous: {'food': 300000},
        ),
      ).map((i) => i.id).toList();
      expect(ids, ['overspent', 'saved']);
      expect(
        insightsFor(input(current: false, spent: 700000)).map((i) => i.id),
        contains('pace-down'),
      );
    });
  });

  group('data', () {
    setUpAll(initFfiSqflite);

    test('net worth snapshots: one row per month, oldest first', () async {
      final repo = NetWorthRepository(AppDatabase.forTesting());
      await repo.record(DateTime(2026, 10, 31), assets: 100, liabilities: 40);
      await repo.record(DateTime(2026, 11, 2), assets: 200, liabilities: 50);
      await repo.record(DateTime(2026, 11, 9), assets: 250, liabilities: 50);
      final h = await repo.history(12);
      expect(h.map((p) => (p.month, p.netWorth)), [
        ('2026-10', 60),
        ('2026-11', 200),
      ]);
      expect((await repo.history(1)).single.month, '2026-11');
    });

    test('v19 -> v20 adds the snapshot table', () async {
      initFfiSqflite();
      final tmp = await Directory.systemTemp.createTemp('spendo_v20');
      addTearDown(() => tmp.delete(recursive: true));
      final path = '${tmp.path}/spendo.db';
      var app = AppDatabase.forTesting(path);
      final db = await app.database;
      await db.execute('DROP TABLE net_worth_snapshots');
      await db.execute('PRAGMA user_version = 19');
      await app.close();
      app = AppDatabase.forTesting(path);
      final repo = NetWorthRepository(app);
      expect(await repo.history(12), isEmpty);
      await repo.record(DateTime(2026, 11), assets: 1, liabilities: 0);
      expect((await repo.history(12)).single.netWorth, 1);
      await app.close();
    });

    test('dashboard from real data: matches allocation, debt, insights, '
        'one snapshot per month', () async {
      final app = AppDatabase.forTesting();
      final txns = TransactionRepository(app);
      final accountsRepo = AccountRepository(app);
      await accountsRepo.add(
        'Salary',
        2100000,
        roles: {AccountRole.salary, AccountRole.daily},
        holdPaise: 100000,
      );
      await accountsRepo.add('Savings', 500000, roles: {AccountRole.savings});
      await accountsRepo.add('Rainy', 1000000, roles: {AccountRole.emergency});
      await accountsRepo.add('Broker', 300000, type: AccountType.investment);
      await txns.add(
        Transaction(
          date: iso(day(0)),
          category: 'food',
          amountPaise: 200000,
          type: TxnType.expense,
          createdAt: 'x',
          account: 'Salary',
        ),
      );
      Transfer move(String to, int amount, MovementStatus status) => Transfer(
        fromAccount: 'Salary',
        toAccount: to,
        amountPaise: amount,
        date: iso(day(0)),
        createdAt: 'x',
        status: status,
      );
      // Scenario 7: ₹3,000 to savings, done. A planned one doesn't count.
      await accountsRepo.addTransfer(
        move('Savings', 300000, MovementStatus.completed),
      );
      await accountsRepo.addTransfer(
        move('Rainy', 100000, MovementStatus.planned),
      );
      final loans = LoanRepository(app);
      await loans.add(
        Loan(
          name: 'Fridge',
          principalPaise: 3000000,
          emiPaise: 500000,
          tenureMonths: 6,
          startDate: day(-3),
          account: 'Salary',
        ),
      );
      final cycles = CycleRepository(app);
      await cycles.recordSalary(
        amountPaise: 1900000,
        date: day(-1),
        account: 'Salary',
        today: day(0),
        alreadyInBalance: true,
      );

      final settings = SettingsController(_Config());
      await settings.init();
      final expenses = ExpensesController(
        txnRepo: txns,
        accountRepo: accountsRepo,
      );
      final accounts = AccountsController(
        accountsRepo,
        ReconciliationRepository(app),
        InvestmentRepository(app),
      );
      final lending = LendingController(
        txnRepo: txns,
        recurringRepo: RecurringRepository(app),
        accountRepo: accountsRepo,
      );
      final recurring = RecurringController(
        recurringRepo: RecurringRepository(app),
        txnRepo: txns,
        accountRepo: accountsRepo,
      );
      final loanCtrl = LoansController(loanRepo: loans, txnRepo: txns);
      final goals = GoalsController(goalRepo: GoalRepository(app))
        ..attach(accounts);
      final cycleCtrl = CycleController(repo: cycles, txnRepo: txns)
        ..attach(expenses);
      final budgets = BudgetController(
        repo: BudgetRepository(app),
        txnRepo: txns,
      )..attach(expenses, cycleCtrl);
      final income = IncomeController(IncomeRepository(app));
      final cards = CardsController(
        CardRepository(app),
        ReconciliationRepository(app),
      );
      await Future.wait([
        expenses.refresh(),
        accounts.refresh(),
        lending.refresh(),
        recurring.refresh(),
        loanCtrl.refresh(),
        goals.refresh(),
        cycleCtrl.refresh(),
        income.refresh(),
        cards.refresh(),
      ]);
      await budgets.refresh();
      final emergency = EmergencyController(
        settings: AllocationRepository(app),
        txnRepo: txns,
      )..attach(accounts, budgets);
      await emergency.refresh();
      final allocation = AllocationController(AllocationRepository(app))
        ..attach(
          accounts: accounts,
          budgets: budgets,
          cards: cards,
          loans: loanCtrl,
          recurring: recurring,
          cycles: cycleCtrl,
          settings: settings,
          goals: goals,
          emergency: emergency,
        );
      await allocation.refresh();
      final calendar = CalendarController(scheduleReminders: false)
        ..attach(
          cycles: cycleCtrl,
          income: income,
          loans: loanCtrl,
          cards: cards,
          recurring: recurring,
          accounts: accounts,
          settings: settings,
        );
      await calendar.refresh();
      final snapshots = NetWorthRepository(app);
      final d = DashboardController(snapshots: snapshots)
        ..attach(
          accounts: accounts,
          lending: lending,
          loans: loanCtrl,
          cards: cards,
          allocation: allocation,
          calendar: calendar,
          cycles: cycleCtrl,
          emergency: emergency,
          budgets: budgets,
          expenses: expenses,
          settings: settings,
        );
      await d.refresh();

      final pos = d.position;
      expect(pos.inAccounts, 2100000 - 200000 - 300000);
      expect(pos.savings, 800000);
      expect(pos.emergency, 1000000); // planned transfer not counted
      expect(pos.available, allocation.view!.plan.available);
      expect(pos.loans, loanCtrl.outstanding);
      expect(d.debt.overdue.single.kind, EventKind.emi);

      final plan = d.cyclePlan();
      expect(plan.unallocated, pos.available);
      expect(plan.dueBeforePayday, greaterThanOrEqualTo(500000));

      final list = await d.insights(
        from: DateTime(day(0).year, day(0).month),
        to: DateTime.now(),
        previousStart: DateTime(day(0).year, day(0).month - 1),
        period: 'month',
      );
      final byId = {for (final i in list) i.id: i};
      expect(byId['overdue']!.title, '1 payment overdue');
      expect(byId['saved']!.title, '₹3,000 moved to savings this month');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      var h = await snapshots.history(12);
      expect(h.single.netWorth, pos.netWorth.total);
      await txns.add(
        Transaction(
          date: iso(day(0)),
          category: 'food',
          amountPaise: 100000,
          type: TxnType.expense,
          createdAt: 'y',
          account: 'Salary',
        ),
      );
      await accounts.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      h = await snapshots.history(12);
      expect(h.single.netWorth, pos.netWorth.total - 100000);
    });
  });

  group('screens', () {
    setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ]) {
      testWidgets('dashboard blocks lay out at 320px, 1.5×, $name', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) => SettingsController(_Config()),
              ),
              ChangeNotifierProvider<DashboardController>(
                create: (_) => _FakeDashboard(),
              ),
              ChangeNotifierProvider(create: (_) => ExpensesController()),
              ChangeNotifierProvider(create: (_) => EmergencyController()),
              ChangeNotifierProvider(create: (_) => GoalsController()),
              ChangeNotifierProvider(create: (_) => AllocationController()),
            ],
            child: MaterialApp(
              theme: theme(),
              home: Scaffold(
                body: ListView(
                  children: [
                    const NetWorthSection(),
                    const CyclePlanCard(),
                    InsightsSection(
                      from: DateTime(2026, 11),
                      to: DateTime(2026, 11, 20),
                      period: 'month',
                    ),
                    const FinanceOverview(),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Available'), findsOneWidget);
        expect(find.text('Reserved'), findsOneWidget);
        expect(find.text('Due before payday'), findsOneWidget);
        expect(find.text('Insights'), findsOneWidget);
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -2000),
        );
        await tester.pump();
        expect(find.text('Wealth'), findsOneWidget);
        expect(find.textContaining('Net worth up'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

class _FakeDashboard extends DashboardController {
  _FakeDashboard() : super(recordSnapshots: false);

  @override
  bool get ready => true;

  @override
  FinancialPosition get position => const FinancialPosition(
    inAccounts: 123456789,
    onHold: 100000,
    reserved: 4500000,
    cash: 123456789,
    savings: 800000,
    emergency: 1000000,
    investments: 350000,
    loans: 2500000,
    cards: 640000,
  );

  @override
  DebtOverview get debt => DebtOverview(
    cards: 640000,
    loans: 2500000,
    borrowed: 20000,
    nextCardDue: ev(
      'HDFC bill',
      DateTime(2026, 11, 29),
      EventKind.cardDue,
      640000,
    ),
    nextStatement: ev(
      'HDFC statement',
      DateTime(2026, 12, 14),
      EventKind.statement,
      0,
    ),
    nextEmi: ev('Fridge EMI 3', DateTime(2026, 12, 5), EventKind.emi, 500000),
    overdue: [
      ev(
        'Fridge EMI 2 with a long name',
        DateTime(2026, 11, 5),
        EventKind.emi,
        500000,
      ),
    ],
  );

  @override
  List<NetWorthPoint> get trend => const [
    NetWorthPoint('2026-09', 100, 50, 50),
    NetWorthPoint('2026-10', 300, 50, 250),
    NetWorthPoint('2026-11', 400, 50, 350),
  ];

  @override
  ({int allocated, int unallocated, int dueBeforePayday}) cyclePlan({
    DateTime? today,
  }) => (allocated: 1234500, unallocated: 9876500, dueBeforePayday: 1550000);

  @override
  Future<List<Insight>> insights({
    required DateTime from,
    required DateTime to,
    DateTime? previousStart,
    required String period,
    DateTime? now,
  }) async => const [
    Insight(
      'overdue',
      InsightTone.alert,
      '1 payment overdue',
      '₹5,000 in total. Fridge EMI 2 was due 5 Nov.',
    ),
    Insight(
      'pace-up',
      InsightTone.warning,
      'Spending is up 20% on last month',
      '₹12,000 so far vs ₹10,000 by this point last month.',
    ),
    Insight(
      'saved',
      InsightTone.good,
      '₹3,000 moved to savings this month',
      'Into savings, emergency and investment accounts. Not spending.',
    ),
  ];
}
