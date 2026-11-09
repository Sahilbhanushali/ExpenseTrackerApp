import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:expense_tracker_app/core/finance/calendar_events.dart';
import 'package:expense_tracker_app/core/finance/cards.dart';
import 'package:expense_tracker_app/core/theme/app_theme.dart';
import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/account.dart';
import 'package:expense_tracker_app/data/models/app_config.dart';
import 'package:expense_tracker_app/data/models/credit_card.dart';
import 'package:expense_tracker_app/data/models/loan.dart';
import 'package:expense_tracker_app/data/models/movement.dart';
import 'package:expense_tracker_app/data/models/recurring_bill.dart';
import 'package:expense_tracker_app/data/models/transaction.dart';
import 'package:expense_tracker_app/data/repositories/account_repository.dart';
import 'package:expense_tracker_app/data/repositories/card_repository.dart';
import 'package:expense_tracker_app/data/repositories/config_repository.dart';
import 'package:expense_tracker_app/data/repositories/cycle_repository.dart';
import 'package:expense_tracker_app/data/repositories/income_repository.dart';
import 'package:expense_tracker_app/data/repositories/investment_repository.dart';
import 'package:expense_tracker_app/data/repositories/loan_repository.dart';
import 'package:expense_tracker_app/data/repositories/reconciliation_repository.dart';
import 'package:expense_tracker_app/data/repositories/recurring_repository.dart';
import 'package:expense_tracker_app/data/repositories/transaction_repository.dart';
import 'package:expense_tracker_app/features/accounts/accounts_controller.dart';
import 'package:expense_tracker_app/features/calendar/calendar_controller.dart';
import 'package:expense_tracker_app/features/calendar/calendar_screen.dart';
import 'package:expense_tracker_app/features/cards/cards_controller.dart';
import 'package:expense_tracker_app/features/cycles/cycle_controller.dart';
import 'package:expense_tracker_app/features/income/income_controller.dart';
import 'package:expense_tracker_app/features/loans/loans_controller.dart';
import 'package:expense_tracker_app/features/recurring/recurring_controller.dart';
import 'package:expense_tracker_app/features/settings/settings_controller.dart';

import 'helpers/sqflite_ffi_setup.dart';

DateTime day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: offset));
}

class _Config extends ConfigRepository {
  AppConfig stored = const AppConfig();
  _Config();
  @override
  Future<AppConfig> load() async => stored;
  @override
  Future<void> save(AppConfig config) async => stored = config;
}

FinEvent ev(
  String key,
  DateTime date,
  MoneyFlow flow, {
  int? amount,
  EventKind kind = EventKind.emi,
}) => FinEvent(
  key: key,
  date: date,
  kind: kind,
  title: key,
  amount: amount,
  flow: flow,
);

void main() {
  group('calendar maths', () {
    test('day of month clamps and rolls to next month', () {
      expect(nextDayOfMonth(31, DateTime(2026, 2, 10)), DateTime(2026, 2, 28));
      expect(nextDayOfMonth(5, DateTime(2026, 2, 10)), DateTime(2026, 3, 5));
      expect(nextDayOfMonth(10, DateTime(2026, 2, 10)), DateTime(2026, 2, 10));
    });

    test('a window keeps overdue dues, drops the rest outside it', () {
      final today = DateTime(2026, 11, 20);
      final all = [
        ev('late', DateTime(2026, 11, 10), MoneyFlow.outgoing, amount: 100),
        ev('past-info', DateTime(2026, 11, 10), MoneyFlow.incoming, amount: 5),
        ev('soon', DateTime(2026, 11, 22), MoneyFlow.outgoing, amount: 200),
        ev('in', DateTime(2026, 11, 25), MoneyFlow.incoming, amount: 1000),
        ev('later', DateTime(2026, 12, 30), MoneyFlow.outgoing, amount: 9),
      ];
      final w = eventsBetween(all, today, DateTime(2026, 11, 26), today);
      expect(w.map((e) => e.key), ['late', 'soon', 'in']);
      expect(windowTotals(w), (outgoing: 300, incoming: 1000));
    });

    test('reminders: stable ids, n days ahead, none once passed', () {
      expect(reminderId('emi:1:2'), reminderId('emi:1:2'));
      expect(reminderId('emi:1:2'), inInclusiveRange(500000, 599999));
      final e = ev('x', DateTime(2026, 11, 22), MoneyFlow.outgoing);
      expect(
        reminderTime(e, 1, DateTime(2026, 11, 20, 12)),
        DateTime(2026, 11, 21, 9),
      );
      expect(reminderTime(e, 3, DateTime(2026, 11, 20, 12)), isNull);
      final info = ev(
        't',
        DateTime(2026, 11, 22),
        MoneyFlow.info,
        kind: EventKind.transfer,
      );
      expect(reminderTime(info, 1, DateTime(2026, 11, 20)), isNull);
    });
  });

  group('calendar from real data', () {
    setUpAll(initFfiSqflite);

    test('every source shows up once, with one reminder per obligation', () async {
      final app = AppDatabase.forTesting();
      final txns = TransactionRepository(app);
      final accountsRepo = AccountRepository(app);
      await accountsRepo.add(
        'Salary',
        5000000,
        roles: {AccountRole.salary, AccountRole.daily},
      );
      await accountsRepo.add('Savings', 0, roles: {AccountRole.savings});
      final cycles = CycleRepository(app);
      await cycles.recordSalary(
        amountPaise: 1900000,
        date: day(-10),
        account: 'Salary',
        today: day(0),
      );
      await IncomeRepository(app).addExpected(
        ExpectedIncome(
          source: IncomeSource.freelance,
          amountPaise: 300000,
          expectedDate: day(5),
          note: 'Invoice',
        ),
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
      final cards = CardRepository(app);
      final card = await cards.save(
        CreditCard(
          name: 'HDFC',
          limitPaise: 10000000,
          statementDay: day(8).day,
        ),
      );
      await cards.addStatement(
        CardStatement(
          cardId: card,
          periodStart: day(-40),
          periodEnd: day(-10),
          generatedOn: day(-10),
          dueDate: day(4),
          figures: const StatementFigures(totalDue: 640000, minimumDue: 32000),
        ),
      );
      final recurringRepo = RecurringRepository(app);
      await recurringRepo.add(
        RecurringBill(
          amountPaise: 99900,
          category: 'bills',
          note: 'Internet',
          dayOfMonth: day(2).day,
        ),
      );
      await accountsRepo.addTransfer(
        Transfer(
          fromAccount: 'Salary',
          toAccount: 'Savings',
          amountPaise: 200000,
          date:
              '${day(1).year}-${day(1).month.toString().padLeft(2, '0')}-${day(1).day.toString().padLeft(2, '0')}',
          createdAt: 'x',
          status: MovementStatus.planned,
        ),
      );

      final settings = SettingsController(_Config());
      await settings.init();
      final cycleCtrl = CycleController(repo: cycles, txnRepo: txns);
      final income = IncomeController(IncomeRepository(app));
      final loanCtrl = LoansController(loanRepo: loans, txnRepo: txns);
      final cardCtrl = CardsController(cards, ReconciliationRepository(app));
      final recurring = RecurringController(
        recurringRepo: recurringRepo,
        txnRepo: txns,
        accountRepo: accountsRepo,
      );
      final accounts = AccountsController(
        accountsRepo,
        ReconciliationRepository(app),
        InvestmentRepository(app),
      );
      await Future.wait([
        cycleCtrl.refresh(),
        income.refresh(),
        loanCtrl.refresh(),
        cardCtrl.refresh(),
        recurring.refresh(),
        accounts.refresh(),
      ]);
      final calendar = CalendarController(scheduleReminders: false)
        ..attach(
          cycles: cycleCtrl,
          income: income,
          loans: loanCtrl,
          cards: cardCtrl,
          recurring: recurring,
          accounts: accounts,
          settings: settings,
        );
      await calendar.refresh();

      final kinds = calendar.events.map((e) => e.kind).toSet();
      expect(
        kinds,
        containsAll(
          EventKind.values.toSet().difference({EventKind.billIncome}),
        ),
      );
      expect(
        calendar.events.map((e) => e.key).toSet().length,
        calendar.events.length,
      );

      // The first EMI was due 3 days ago: it leads the next-7-days view.
      final week = calendar.upcoming(7);
      expect(week.first.kind, EventKind.emi);
      expect(week.first.overdue(day(0)), isTrue);

      final plan = calendar.reminderPlan(DateTime.now());
      expect(plan.map((r) => r.id).toSet().length, plan.length);
      // Recurring bills keep their own reminder; overdue items get none.
      final billId = reminderId(
        calendar.events.firstWhere((e) => e.kind == EventKind.bill).key,
      );
      expect(plan.any((r) => r.id == billId), isFalse);

      await settings.setReminders(on: false);
      expect(calendar.reminderPlan(DateTime.now()), isEmpty);
    });
  });

  group('calendar screen', () {
    setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ]) {
      testWidgets('lays out at 320px, 1.5×, $name', (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => SettingsController()),
              ChangeNotifierProvider<CalendarController>(
                create: (_) => _FakeCalendar(),
              ),
            ],
            child: MaterialApp(theme: theme(), home: const CalendarScreen()),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Overdue'), findsOneWidget);
        await tester.tap(find.text('30 days'));
        await tester.pump();
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -3000),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}

class _FakeCalendar extends CalendarController {
  _FakeCalendar() : super(scheduleReminders: false);
  @override
  List<FinEvent> get events => [
    FinEvent(
      key: 'a',
      date: day(-2),
      kind: EventKind.emi,
      title: 'Fridge EMI 1 with a long name',
      amount: 500000,
      flow: MoneyFlow.outgoing,
      detail: 'From Salary',
    ),
    FinEvent(
      key: 'b',
      date: day(0),
      kind: EventKind.cardDue,
      title: 'HDFC bill',
      amount: 640000,
      flow: MoneyFlow.outgoing,
      detail: 'Minimum ₹320. Paying less than the total charges interest.',
    ),
    FinEvent(
      key: 'c',
      date: day(3),
      kind: EventKind.salary,
      title: 'Salary expected',
      amount: 1900000,
      flow: MoneyFlow.incoming,
      detail: 'Between 7 Dec and 15 Dec.',
    ),
    FinEvent(
      key: 'd',
      date: day(9),
      kind: EventKind.statement,
      title: 'HDFC statement',
      flow: MoneyFlow.info,
    ),
    FinEvent(
      key: 'e',
      date: day(20),
      kind: EventKind.transfer,
      title: 'Salary → Savings',
      amount: 200000,
      flow: MoneyFlow.info,
    ),
  ];
}
