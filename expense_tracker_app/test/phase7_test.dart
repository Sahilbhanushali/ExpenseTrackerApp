import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:expense_tracker_app/core/finance/allocation.dart';
import 'package:expense_tracker_app/core/finance/budgets.dart';
import 'package:expense_tracker_app/core/finance/cards.dart';
import 'package:expense_tracker_app/core/theme/app_theme.dart';
import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/account.dart';
import 'package:expense_tracker_app/data/models/credit_card.dart';
import 'package:expense_tracker_app/data/models/recurring_bill.dart';
import 'package:expense_tracker_app/data/repositories/account_repository.dart';
import 'package:expense_tracker_app/data/repositories/allocation_repository.dart';
import 'package:expense_tracker_app/features/accounts/accounts_controller.dart';
import 'package:expense_tracker_app/features/allocation/allocation_controller.dart';
import 'package:expense_tracker_app/features/allocation/allocation_needs.dart';
import 'package:expense_tracker_app/features/allocation/allocation_screen.dart';
import 'package:expense_tracker_app/features/cards/cards_controller.dart';

import 'helpers/sqflite_ffi_setup.dart';

DateTime d(int m, int day, [int y = 2026]) => DateTime(y, m, day);

AllocationNeed need(
  String key,
  AllocBucket b,
  int required, {
  DateTime? due,
  bool revolving = false,
}) => AllocationNeed(
  key: key,
  bucket: b,
  label: key,
  required: required,
  reason: '',
  dueDate: due,
  revolving: revolving,
);

AccountBalance acc(
  int id,
  String name,
  int balance, {
  Set<AccountRole> roles = const {AccountRole.daily},
  AccountType type = AccountType.cash,
  int hold = 0,
}) => AccountBalance(
  account: MoneyAccount(
    id: id,
    name: name,
    createdAt: 'x',
    roles: roles,
    type: type,
    holdPaise: hold,
  ),
  balance: balance,
);

AllocationSnapshot snap({
  List<AccountBalance>? accounts,
  List<BudgetUsage> budgets = const [],
  List<CardSummary> cards = const [],
  List<RecurringBill> bills = const [],
  AllocationSettings settings = const AllocationSettings(),
}) => AllocationSnapshot(
  today: d(11, 20),
  horizon: d(12, 15),
  currency: '₹',
  accounts:
      accounts ??
      [
        acc(
          1,
          'Salary',
          2100000,
          roles: {AccountRole.salary, AccountRole.daily},
        ),
      ],
  budgets: budgets,
  cards: cards,
  loans: const [],
  bills: bills,
  settings: settings,
);

CardSummary card(int due, DateTime dueDate, {int paid = 0}) => CardSummary(
  card: const CreditCard(
    id: 3,
    name: 'HDFC',
    limitPaise: 10000000,
    repaymentAccount: 'Salary',
  ),
  outstanding: due,
  latest: CardStatement(
    id: 7,
    cardId: 3,
    periodStart: d(10, 15),
    periodEnd: d(11, 14),
    generatedOn: d(11, 14),
    dueDate: dueDate,
    figures: StatementFigures(totalDue: due, minimumDue: due ~/ 20),
    paidPaise: paid,
  ),
);

void main() {
  group('allocation engine', () {
    test('funds in priority order and never exceeds what is available', () {
      final plan = allocate(
        available: 1000000,
        needs: [
          need('fun', AllocBucket.discretionary, 300000),
          need('rent', AllocBucket.essentials, 600000),
          need('emi', AllocBucket.obligations, 300000),
        ],
      );
      final by = {for (final l in plan.lines) l.need.key: l};
      expect(by['rent']!.proposed, 600000);
      expect(by['emi']!.proposed, 300000);
      expect(by['fun']!.proposed, 100000);
      expect(by['fun']!.shortfall, 200000);
      expect(plan.proposedTotal, lessThanOrEqualTo(1000000));
      expect(plan.buffer, 0);
      expect(plan.criticalShortfall, 0);
    });

    test('scenario 9: too little money shows a real shortfall', () {
      final plan = allocate(
        available: 500000,
        needs: [
          need('card', AllocBucket.obligations, 800000, due: d(11, 29)),
          need('emi', AllocBucket.obligations, 300000, due: d(12, 5)),
          need('invest', AllocBucket.investing, 200000),
        ],
      );
      expect(plan.proposedTotal, 500000);
      expect(plan.criticalShortfall, 600000);
      expect(plan.unmet.first.need.key, 'card');
      final invest = plan.lines.firstWhere((l) => l.need.key == 'invest');
      expect(invest.proposed, 0);
      expect(invest.skippedBecause, isNotNull);
    });

    test('overdue card debt goes before savings even if ordered later', () {
      final plan = allocate(
        available: 300000,
        order: const [AllocBucket.savings, AllocBucket.obligations],
        needs: [
          need('savings', AllocBucket.savings, 300000),
          need('card', AllocBucket.obligations, 300000, revolving: true),
        ],
      );
      expect(plan.lines.first.need.key, 'card');
      expect(plan.lines.first.proposed, 300000);
    });

    test('a custom order is respected; reservations count', () {
      final plan = allocate(
        available: 100000,
        order: const [AllocBucket.savings, AllocBucket.essentials],
        reservedByKey: const {'food': 50000},
        needs: [
          need('food', AllocBucket.essentials, 80000),
          need('savings', AllocBucket.savings, 60000),
        ],
      );
      final by = {for (final l in plan.lines) l.need.key: l};
      expect(by['savings']!.proposed, 60000);
      expect((by['food']!.reserved, by['food']!.proposed), (50000, 30000));
      expect(plan.buffer, 10000);
    });
  });

  group('needs from real data', () {
    test('scenario 10: savings and emergency money is not spendable twice', () {
      final s = snap(
        accounts: [
          acc(
            1,
            'Salary',
            2100000,
            roles: {AccountRole.salary, AccountRole.daily},
            hold: 100000,
          ),
          acc(2, 'Savings', 5000000, roles: {AccountRole.savings}),
          acc(3, 'Emergency', 3000000, roles: {AccountRole.emergency}),
        ],
        settings: const AllocationSettings(
          emergencyTarget: 5000000,
          emergencyMonthly: 500000,
        ),
      );
      expect(s.liquid, 2000000); // salary account less its hold, nothing else
      final emergency = buildNeeds(s).single;
      expect(emergency.required, 500000); // gap 20,000 capped at 5,000/period
      expect(emergency.destination, 'Emergency');
      expect(emergency.reason, contains('₹30,000'));
    });

    test('only dues before the next salary; overdue card debt revolves', () {
      final soon = buildNeeds(snap(cards: [card(800000, d(11, 29))]));
      expect(soon.single.bucket, AllocBucket.obligations);
      expect(soon.single.revolving, isFalse);
      expect(buildNeeds(snap(cards: [card(800000, d(12, 20))])), isEmpty);
      final late = buildNeeds(snap(cards: [card(800000, d(11, 10))]));
      expect(late.single.revolving, isTrue);
      expect(
        buildNeeds(snap(cards: [card(800000, d(11, 29), paid: 800000)])),
        isEmpty,
      );
    });

    test('bills and budgets: essentials vs discretionary', () {
      final needs = buildNeeds(
        snap(
          bills: const [
            RecurringBill(
              id: 1,
              amountPaise: 99900,
              category: 'bills',
              note: 'Internet',
              dayOfMonth: 25,
            ),
          ],
          budgets: [
            BudgetUsage(
              budget: const Budget(
                id: 1,
                period: BudgetPeriod.month,
                category: 'rent',
                limitPaise: 1000000,
                essential: true,
              ),
              range: PeriodRange(d(11, 1), d(11, 30)),
              spent: 0,
              daysLeft: 10,
            ),
            BudgetUsage(
              budget: const Budget(
                id: 2,
                period: BudgetPeriod.month,
                category: 'food',
                limitPaise: 500000,
              ),
              range: PeriodRange(d(11, 1), d(11, 30)),
              spent: 600000,
              daysLeft: 10,
            ),
          ],
        ),
      );
      expect(needs.map((n) => (n.key, n.bucket)), [
        ('budget:1', AllocBucket.essentials),
        ('bill:1:2026-11', AllocBucket.obligations),
      ]);
      expect(
        nextBillDate(
          const RecurringBill(
            amountPaise: 1,
            category: 'x',
            dayOfMonth: 31,
            lastRunMonth: '2026-11',
          ),
          d(11, 20),
        ),
        d(12, 31),
      );
    });

    test('paying a bill releases what was reserved for it', () {
      final r = effectiveReservations(const [
        AllocationDecision(
          id: 1,
          scope: 's',
          key: 'card:3:stmt:7',
          bucket: AllocBucket.obligations,
          label: 'HDFC',
          amount: 800000,
          status: DecisionStatus.reserved,
        ),
      ], buildNeeds(snap(cards: [card(800000, d(11, 29), paid: 600000)])));
      expect(r.heldBack['card:3:stmt:7'], 200000);
      expect(
        effectiveReservations(const [], buildNeeds(snap())).heldBack,
        isEmpty,
      );
    });
  });

  group('decisions on the ledger', () {
    setUpAll(initFfiSqflite);
    late AppDatabase app;
    late AllocationRepository repo;
    late AccountRepository accounts;
    final saving = need('savings', AllocBucket.savings, 300000);

    setUp(() async {
      app = AppDatabase.forTesting();
      repo = AllocationRepository(app);
      accounts = AccountRepository(app);
      await accounts.add('Salary', 2100000);
      await accounts.add('Savings', 0, roles: {AccountRole.savings});
    });

    test('approving never moves money; transfer done does', () async {
      await repo.reserve(
        'cycle:x',
        saving,
        amount: 300000,
        destination: 'Savings',
        moveFrom: 'Salary',
      );
      expect(await accounts.balance('Salary'), 2100000);
      expect((await accounts.plannedTransfers()).single.amountPaise, 300000);
      final d = (await repo.decisions('cycle:x')).single;
      expect(d.status, DecisionStatus.reserved);
      await expectLater(
        repo.reserve('cycle:x', saving, amount: 1, destination: 'Savings'),
        throwsA(isA<AllocationException>()),
      );
      await repo.markTransferred(d.id);
      expect(await accounts.balance('Savings'), 300000);
      expect(await accounts.balance('Salary'), 1800000);
      await expectLater(
        repo.release(d.id),
        throwsA(isA<AllocationException>()),
      );
    });

    test('release cancels a planned transfer; skip is remembered', () async {
      await repo.reserve(
        'cycle:x',
        saving,
        amount: 300000,
        destination: 'Savings',
        moveFrom: 'Salary',
      );
      await repo.release((await repo.decisions('cycle:x')).single.id);
      expect(await accounts.plannedTransfers(), isEmpty);
      expect(await repo.decisions('cycle:x'), isEmpty);
      await repo.skip('cycle:x', saving);
      expect(
        (await repo.decisions('cycle:x')).single.status,
        DecisionStatus.skipped,
      );
      // Decisions belong to their period.
      expect(await repo.decisions('cycle:y'), isEmpty);
    });

    test('settings keep the order and amounts', () async {
      await repo.saveSettings(
        const AllocationSettings(
          order: [AllocBucket.obligations, AllocBucket.essentials],
          savingsPerCycle: 200000,
        ),
      );
      final s = await repo.settings();
      expect(s.order, [AllocBucket.obligations, AllocBucket.essentials]);
      expect(s.savingsPerCycle, 200000);
      expect(s.investPerCycle, isNull);
    });

    test(
      'scenario 2: extra income gives a new proposal, approvals stay',
      () async {
        final emi = need('emi', AllocBucket.obligations, 1500000);
        await repo.reserve(
          'cycle:x',
          emi,
          amount: 1500000,
          destination: 'Salary',
        );
        final decisions = await repo.decisions('cycle:x');
        final needs = [emi, saving];
        List<AllocationLine> planFor(int liquid) {
          final r = effectiveReservations(decisions, needs);
          final held = r.heldBack.values.fold(0, (a, b) => a + b);
          return allocate(
            available: liquid - held,
            needs: needs,
            reservedByKey: r.funded,
          ).lines;
        }

        final before = planFor(2100000);
        expect(
          before.firstWhere((l) => l.need.key == 'savings').proposed,
          300000,
        );
        // ₹2,000 more arrives: the EMI reservation is untouched, the new money
        // only shows up as unallocated.
        final after = planFor(2300000);
        final e = after.firstWhere((l) => l.need.key == 'emi');
        expect((e.reserved, e.proposed), (1500000, 0));
        expect(
          allocate(
            available: 2300000 - 1500000,
            needs: needs,
            reservedByKey: {'emi': 1500000},
          ).buffer,
          500000,
        );
      },
    );
  });

  test('v17 -> v18 adds the allocation tables', () async {
    initFfiSqflite();
    final tmp = await Directory.systemTemp.createTemp('spendo_v18');
    addTearDown(() => tmp.delete(recursive: true));
    final path = '${tmp.path}/spendo.db';
    var app = AppDatabase.forTesting(path);
    var db = await app.database;
    await db.execute('DROP TABLE allocation_decisions');
    await db.execute('DROP TABLE allocation_settings');
    await db.execute('PRAGMA user_version = 17');
    await app.close();
    app = AppDatabase.forTesting(path);
    final repo = AllocationRepository(app);
    expect((await repo.settings()).order, kDefaultAllocationOrder);
    await repo.skip('m', need('x', AllocBucket.savings, 1));
    expect(await repo.decisions('m'), hasLength(1));
    await app.close();
  });

  group('allocation screen', () {
    setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ]) {
      testWidgets('lays out at 320px, 1.5× text, $name', (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AllocationController>(
                create: (_) => _FakeAllocation(),
              ),
              ChangeNotifierProvider(create: (_) => AccountsController()),
            ],
            child: MaterialApp(theme: theme(), home: const AllocationScreen()),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.scrollUntilVisible(
          find.textContaining('short for'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.textContaining('short for'), findsOneWidget);
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

class _FakeAllocation extends AllocationController {
  final _v = () {
    final s = snap(cards: [card(800000, d(11, 10))]);
    final needs = [
      ...buildNeeds(s),
      need('Groceries and a long label', AllocBucket.essentials, 400000),
      need('invest', AllocBucket.investing, 200000),
    ];
    return AllocationView(
      snapshot: s,
      plan: allocate(available: 900000, needs: needs),
      decisions: const [],
      reserved: 0,
      scope: 's',
      skipped: [need('Holiday', AllocBucket.savings, 100000)],
    );
  }();
  @override
  AllocationView? get view => _v;
  @override
  Future<void> refresh() async {}
}
