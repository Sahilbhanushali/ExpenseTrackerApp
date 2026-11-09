import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:expense_tracker_app/core/theme/app_theme.dart';
import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/app_config.dart';
import 'package:expense_tracker_app/core/finance/budgets.dart';
import 'package:expense_tracker_app/data/repositories/budget_repository.dart';
import 'package:expense_tracker_app/data/repositories/config_repository.dart';
import 'package:expense_tracker_app/data/repositories/transaction_repository.dart';
import 'package:expense_tracker_app/features/budgets/budget_controller.dart';
import 'package:expense_tracker_app/features/expenses/expenses_controller.dart';
import 'package:expense_tracker_app/features/guardian/guardian_controller.dart';
import 'package:expense_tracker_app/features/guardian/guardian_models.dart';
import 'package:expense_tracker_app/features/guardian/guardian_platform.dart';
import 'package:expense_tracker_app/features/guardian/guardian_screen.dart';
import 'package:expense_tracker_app/features/settings/settings_controller.dart';

class _FakeConfigRepo extends ConfigRepository {
  final AppConfig config;
  _FakeConfigRepo(this.config);
  @override
  Future<AppConfig> load() async => config;
  @override
  Future<void> save(AppConfig config) async {}
}

class _FakeTxnRepo extends TransactionRepository {
  _FakeTxnRepo() : super(AppDatabase.forTesting());

  @override
  Future<MonthTotal> monthTotal(String month) async =>
      const MonthTotal(expense: 2245000, income: 5000000);
  @override
  Future<Map<String, int>> categoryTotals(String month) async => const {
    'food': 600000,
    'travel': 100000,
  };
  @override
  Future<MonthTotal> totalsRange(DateTime from, DateTime to) async =>
      const MonthTotal(expense: 45000);
  @override
  Future<Map<String, int>> categoryTotalsRange(DateTime f, DateTime t) =>
      categoryTotals('');
}

class _FakeBudgetRepo extends BudgetRepository {
  _FakeBudgetRepo() : super(AppDatabase.forTesting());
  @override
  Future<List<Budget>> list() async => const [
    Budget(id: 1, period: BudgetPeriod.month, limitPaise: 2000000),
    Budget(
      id: 2,
      period: BudgetPeriod.month,
      category: 'food',
      limitPaise: 500000,
    ),
    Budget(
      id: 3,
      period: BudgetPeriod.month,
      category: 'travel',
      limitPaise: 300000,
    ),
  ];
}

Future<BudgetController> _budgets() async {
  final b = BudgetController(repo: _FakeBudgetRepo(), txnRepo: _FakeTxnRepo());
  await b.refresh();
  return b;
}

class _FakePlatform extends GuardianPlatform {
  GuardianState state;
  final pushed = <Map<String, dynamic>>[];
  final updates = <Map<String, Object>>[];
  _FakePlatform(this.state);

  @override
  bool get supported => true;
  @override
  Future<GuardianState?> getState() async => state;
  @override
  Future<bool> pushSnapshot(String json) async {
    pushed.add(jsonDecode(json) as Map<String, dynamic>);
    return true;
  }

  @override
  Future<GuardianState?> updateSettings(Map<String, Object> values) async {
    updates.add(values);
    return state;
  }

  @override
  Future<String?> setEnabled(bool enabled) async => 'ok';
}

const _config = AppConfig(
  monthlyBudgetPaise: 2000000,
  budgets: {'food': 500000, 'travel': 300000, 'unused': 0},
);

GuardianState _state({bool usage = true, bool overlay = true}) =>
    GuardianState.fromMap({
      'settings': {
        'enabled': true,
        'apps': ['com.dreamplug.androidapp', 'net.one97.paytm'],
        'cautionPercent': 80,
        'cooldownMinutes': 30,
      },
      'running': true,
      'permissions': {
        'usageAccess': usage,
        'overlay': overlay,
        'notifications': true,
        'batteryUnrestricted': false,
      },
      // Google Pay is left out: an older native build that doesn't know
      // the app yet, which must read as "couldn't check", not "missing".
      'installed': {
        'com.dreamplug.androidapp': true,
        'net.one97.paytm': false,
        'indwin.c3.shareapp': false,
      },
      'stats': {
        'alertsShown': 4,
        'budgetExceeded': 1,
        'opens': {'com.dreamplug.androidapp': 7},
      },
    });

void main() {
  group('guardianLevel', () {
    test('matches the app budget rules', () {
      expect(guardianLevel(0, 0, 80), GuardianLevel.none);
      expect(guardianLevel(1599, 2000, 80), GuardianLevel.none);
      expect(guardianLevel(1600, 2000, 80), GuardianLevel.caution);
      expect(guardianLevel(2000, 2000, 80), GuardianLevel.reached);
      expect(guardianLevel(2001, 2000, 80), GuardianLevel.exceeded);
      expect(guardianLevel(1800, 2000, 95), GuardianLevel.none);
    });
  });

  group('BudgetSnapshot', () {
    final snap = BudgetSnapshot(
      computedAt: DateTime(2026, 11, 21, 14),
      currency: '₹',
      budget: 2000000,
      spent: 1500000,
      todaySpent: 100000,
      categories: const [
        CategorySpend('food', 500000, 600000),
        CategorySpend('travel', 300000, 100000),
      ],
    );

    test('serialises the month and day the figures belong to', () {
      final json = snap.toJson();
      expect(json['month'], '2026-11');
      expect(json['day'], '2026-11-21');
      expect(json['spent'], 1500000);
    });

    test('daily limit spreads what was left this morning over days left', () {
      // ₹20,000 − (₹15,000 − ₹1,000 today) = ₹6,000 over 10 days left.
      expect(snap.dailyLimit, 60000);
      expect(snap.percent, 75);
      expect(snap.overCategories.map((c) => c.name), ['food']);
    });
  });

  testWidgets('sync pushes figures computed from the ledger and budgets', (
    tester,
  ) async {
    final settings = SettingsController(_FakeConfigRepo(_config));
    await settings.init();
    final expenses = ExpensesController(txnRepo: _FakeTxnRepo());
    final platform = _FakePlatform(_state());
    final guardian = GuardianController(platform);

    await guardian.attach(expenses, settings, await _budgets());

    final pushed = platform.pushed.single;
    expect(pushed['budget'], 2000000);
    expect(pushed['spent'], 2245000);
    expect(pushed['todaySpent'], 45000);
    expect(pushed['currency'], '₹');
    // Zero caps are left out; spending comes from this month's totals.
    expect(pushed['categories'], [
      {'name': 'food', 'cap': 500000, 'spent': 600000},
      {'name': 'travel', 'cap': 300000, 'spent': 100000},
    ]);
    expect(guardian.handlesBudgetNotifications, isTrue);
    guardian.dispose();
  });

  group('GuardianScreen', () {
    setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

    Future<_FakePlatform> pump(
      WidgetTester tester, {
      required Size size,
      double scale = 1,
      GuardianState? state,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final settings = SettingsController(_FakeConfigRepo(_config));
      await settings.init();
      final expenses = ExpensesController(txnRepo: _FakeTxnRepo());
      final platform = _FakePlatform(state ?? _state());
      final guardian = GuardianController(platform);
      await guardian.attach(expenses, settings, await _budgets());
      addTearDown(guardian.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: expenses),
            ChangeNotifierProvider.value(value: guardian),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: const GuardianScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      return platform;
    }

    for (final (name, size, scale) in [
      ('small phone, large text', const Size(320, 568), 1.5),
      ('standard phone', const Size(390, 844), 1.0),
      ('tablet', const Size(820, 1180), 1.0),
    ]) {
      testWidgets('lays out on a $name', (tester) async {
        await pump(tester, size: size, scale: scale);
        expect(find.text('Monitoring'), findsOneWidget);
        expect(find.text('Over by ₹2,450'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('How to stop'),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('How to stop'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('missing permissions explain instead of enabling', (
      tester,
    ) async {
      final state = GuardianState.fromMap({
        'settings': {'enabled': false},
        'permissions': {'usageAccess': false, 'overlay': true},
      });
      await pump(tester, size: const Size(390, 844), state: state);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(find.text('Two permissions needed'), findsOneWidget);
    });

    testWidgets('an uninstalled, unselected app cannot be ticked', (
      tester,
    ) async {
      final platform = await pump(tester, size: const Size(390, 844));
      // slice: not installed and not selected.
      final bhim = find.ancestor(
        of: find.text('slice'),
        matching: find.byType(Row),
      );
      final toggle = tester.widget<Switch>(
        find.descendant(of: bhim.first, matching: find.byType(Switch)),
      );
      expect(toggle.onChanged, isNull);
      expect(platform.updates, isEmpty);
      expect(find.textContaining('Couldn’t check'), findsOneWidget);
    });
  });
}
