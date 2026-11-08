import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:expense_tracker_app/core/theme/app_theme.dart';
import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/transaction.dart';
import 'package:expense_tracker_app/data/repositories/transaction_repository.dart';
import 'package:expense_tracker_app/features/accounts/accounts_controller.dart';
import 'package:expense_tracker_app/features/dashboard/home_shell.dart';
import 'package:expense_tracker_app/features/expenses/expenses_controller.dart';
import 'package:expense_tracker_app/features/goals/goals_controller.dart';
import 'package:expense_tracker_app/features/lending/lending_controller.dart';
import 'package:expense_tracker_app/features/loans/loans_controller.dart';
import 'package:expense_tracker_app/features/recurring/recurring_controller.dart';
import 'package:expense_tracker_app/features/reminders/reminders_controller.dart';
import 'package:expense_tracker_app/features/settings/settings_controller.dart';
import 'package:expense_tracker_app/features/sms_import/sms_import_controller.dart';
import 'package:expense_tracker_app/features/wishlist/wishlist_controller.dart';

/// Canned ledger data so every screen renders with realistic content,
/// without touching a database.
class _FakeTxnRepo extends TransactionRepository {
  _FakeTxnRepo() : super(AppDatabase.forTesting());

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  final _rows = List.generate(14, (i) {
    final d = DateTime.now().subtract(Duration(days: i ~/ 3));
    return Transaction(
      id: i + 1,
      date: _iso(d),
      category: const ['food', 'travel', 'groceries', 'rent', 'income'][i % 5],
      amountPaise: (i + 1) * 123456,
      note: i.isEven
          ? 'A fairly long merchant name that should ellipsize $i'
          : null,
      type: i % 5 == 4 ? TxnType.income : TxnType.expense,
      createdAt: d.toIso8601String(),
    );
  });

  @override
  Future<List<Transaction>> recent({int limit = 10}) async =>
      _rows.take(limit).toList().reversed.toList();

  @override
  Future<MonthTotal> monthTotal(String month) async =>
      const MonthTotal(expense: 98765432, income: 150000000);

  @override
  Future<Map<String, int>> categoryTotals(String month) async => const {
    'food': 2500000,
    'travel': 1800000,
    'groceries': 1200000,
    'rent': 3500000,
    'luxuries': 400000,
    'a-custom-category-with-a-long-name': 90000,
  };

  @override
  Future<List<MonthPoint>> monthlyTrend(int months) async => List.generate(
    months,
    (i) => MonthPoint(
      month: '2026-${(i + 1).toString().padLeft(2, '0')}',
      income: 100000 * (i + 3),
      expense: 90000 * (i + 2),
    ),
  );

  @override
  Future<List<Transaction>> queryPage({
    int limit = 50,
    int offset = 0,
    TxnType? type,
    String? category,
    DateTime? from,
    DateTime? to,
    String? searchTerm,
  }) async => offset == 0 ? _rows : [];

  @override
  Future<List<String>> distinctCategories() async => ['food', 'travel'];

  @override
  Future<MonthTotal> totalsRange(DateTime from, DateTime to) async =>
      const MonthTotal(expense: 98765432, income: 150000000);

  @override
  Future<Map<String, int>> categoryTotalsRange(DateTime f, DateTime t) =>
      categoryTotals('');

  @override
  Future<Map<String, int>> expenseSeries(
    DateTime from,
    DateTime to, {
    bool monthly = false,
  }) async => {_iso(DateTime.now()): 450000};
}

Widget _app(ExpensesController expenses, ThemeData theme) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SettingsController()),
      ChangeNotifierProvider.value(value: expenses),
      ChangeNotifierProvider(create: (_) => AccountsController()),
      ChangeNotifierProvider(create: (_) => LendingController()),
      ChangeNotifierProvider(create: (_) => RecurringController()),
      ChangeNotifierProvider(create: (_) => LoansController()),
      ChangeNotifierProvider(create: (_) => WishlistController()),
      ChangeNotifierProvider(create: (_) => GoalsController()),
      ChangeNotifierProvider(create: (_) => RemindersController()),
      ChangeNotifierProvider(create: (_) => SmsImportController()),
    ],
    child: MaterialApp(theme: theme, home: const HomeShell()),
  );
}

void main() {
  // Fonts aren't bundled for tests; fall back to the default face.
  GoogleFonts.config.allowRuntimeFetching = false;

  const sizes = {
    'small phone': Size(320, 568),
    'standard phone': Size(390, 844),
    'large phone': Size(430, 932),
    'landscape phone': Size(844, 390),
    'tablet': Size(820, 1180),
  };
  final themes = {'light': AppTheme.light, 'dark': AppTheme.dark};

  for (final MapEntry(key: sizeName, value: size) in sizes.entries) {
    for (final MapEntry(key: themeName, value: theme) in themes.entries) {
      for (final scale in [1.0, 1.5]) {
        testWidgets(
          'every tab lays out without overflow: $sizeName, $themeName, text x$scale',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.reset);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );

            final expenses = ExpensesController(txnRepo: _FakeTxnRepo());
            await expenses.refresh();
            await tester.pumpWidget(_app(expenses, theme()));
            await tester.pump(const Duration(seconds: 1));

            for (final tab in ['Transactions', 'Reports', 'More', 'Home']) {
              await tester.tap(find.byTooltip(tab));
              await tester.pump(const Duration(seconds: 1));
              expect(tester.takeException(), isNull, reason: tab);
            }

            await tester.tap(find.byTooltip('Add transaction'));
            await tester.pump(const Duration(seconds: 1));
            expect(tester.takeException(), isNull, reason: 'add sheet');
          },
        );
      }
    }
  }
}
