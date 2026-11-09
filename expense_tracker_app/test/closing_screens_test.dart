import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:expense_tracker_app/core/finance/cycle_closing.dart';
import 'package:expense_tracker_app/core/finance/salary_cycle.dart';
import 'package:expense_tracker_app/core/theme/app_theme.dart';
import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/repositories/cycle_repository.dart';
import 'package:expense_tracker_app/data/repositories/transaction_repository.dart';
import 'package:expense_tracker_app/features/accounts/accounts_controller.dart';
import 'package:expense_tracker_app/features/allocation/allocation_controller.dart';
import 'package:expense_tracker_app/features/cards/cards_controller.dart';
import 'package:expense_tracker_app/features/cycles/cycle_closing_screen.dart';
import 'package:expense_tracker_app/features/cycles/cycle_closing_service.dart';
import 'package:expense_tracker_app/features/cycles/cycle_controller.dart';
import 'package:expense_tracker_app/features/loans/loans_controller.dart';
import 'package:expense_tracker_app/features/settings/settings_controller.dart';

final _closed = CycleCloseSummary(
  start: DateTime(2026, 10, 9),
  end: DateTime(2026, 11, 9),
  salary: 1900000,
  additionalIncome: 0,
  spent: 1500000,
  categories: const {},
  balances: const {'A salary account with a long name': 400000},
  cardsOwed: 300000,
  loansOutstanding: 900000,
  reservedAtClose: 0,
  unpaidObligations: const {'HDFC bill (due 29 Oct)': 100000},
  leftoverAvailable: 400000,
  actions: const [
    LeftoverAction(
      kind: LeftoverKind.savings,
      amountPaise: 300000,
      target: 'Savings',
      label: 'Move to savings · Savings',
    ),
  ],
  closedAt: DateTime(2026, 11, 10),
);

class _Cycles extends CycleRepository {
  _Cycles() : super(AppDatabase.forTesting());
  @override
  Future<List<CycleRecord>> list() async => [
    CycleRecord(
      id: 1,
      start: DateTime(2026, 10, 9),
      closedAt: DateTime(2026, 11, 10),
      summaryJson: _closed.encode(),
    ),
    CycleRecord(id: 2, start: DateTime(2026, 11, 10)),
    CycleRecord(id: 3, start: DateTime(2026, 12, 12)),
  ];
  @override
  Future<SalaryProfile> profile() async => const SalaryProfile();
  @override
  Future<CycleIncome> incomeFor(CycleRange cycle, DateTime today) async =>
      const CycleIncome(salary: 1900000, additional: 0);
}

class _Txns extends TransactionRepository {
  _Txns() : super(AppDatabase.forTesting());
  @override
  Future<MonthTotal> totalsRange(DateTime from, DateTime to) async =>
      const MonthTotal(expense: 1500000);
  @override
  Future<Map<String, int>> categoryTotalsRange(DateTime f, DateTime t) async =>
      const {};
}

class _Service extends CycleClosingService {
  @override
  Future<ClosingPreview> preview(
    CycleRange c, {
    required int unallocatedNow,
    required int reserved,
    DateTime? today,
    String currency = '₹',
  }) async => ClosingPreview(
    cycle: c,
    income: const CycleIncome(salary: 1900000, additional: 200000),
    spent: 1500000,
    categories: const {},
    balances: const {'A salary account with a long name': 600000, 'Savings': 0},
    cardsOwed: 300000,
    loansOutstanding: 900000,
    reserved: 50000,
    unpaid: const {'A very long credit card name bill (due 29 Nov)': 300000},
    unallocatedNow: 2500000,
  );
}

class _Allocation extends AllocationController {
  @override
  Future<void> refresh() async {}
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    for (final closing in [true, false]) {
      testWidgets(
        '${closing ? 'closing' : 'closed'} screen at 320px, 1.5×, $name',
        (tester) async {
          tester.view.physicalSize = const Size(320, 568);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.5;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final cycles = CycleController(repo: _Cycles(), txnRepo: _Txns());
          await cycles.refresh();
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider(create: (_) => SettingsController()),
                ChangeNotifierProvider.value(value: cycles),
                ChangeNotifierProvider(create: (_) => AccountsController()),
                ChangeNotifierProvider(create: (_) => CardsController()),
                ChangeNotifierProvider(create: (_) => LoansController()),
                ChangeNotifierProvider<AllocationController>(
                  create: (_) => _Allocation(),
                ),
              ],
              child: MaterialApp(
                theme: theme(),
                home: closing
                    ? CycleClosingScreen(cycleId: 2, service: _Service())
                    : const ClosedCycleScreen(cycleId: 1),
              ),
            ),
          );
          await tester.pump(const Duration(seconds: 1));
          if (closing) {
            await tester.scrollUntilVisible(
              find.text('Carry forward to next cycle'),
              300,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.ensureVisible(
              find.text('Carry forward to next cycle'),
            );
            await tester.pump();
            await tester.tap(find.text('Carry forward to next cycle'));
            await tester.pump();
            await tester.scrollUntilVisible(
              find.textContaining('not yet decided'),
              300,
              // The page's own scroller — text fields have one too.
              scrollable: find
                  .descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            expect(find.textContaining('not yet decided'), findsOneWidget);
          } else {
            expect(find.textContaining('Closed 10 Nov'), findsOneWidget);
          }
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -3000),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
