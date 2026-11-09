import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:expense_tracker_app/core/finance/cards.dart';
import 'package:expense_tracker_app/core/theme/app_theme.dart';
import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/credit_card.dart';
import 'package:expense_tracker_app/data/models/loan.dart';
import 'package:expense_tracker_app/data/models/transaction.dart';
import 'package:expense_tracker_app/data/repositories/card_repository.dart';
import 'package:expense_tracker_app/data/repositories/loan_repository.dart';
import 'package:expense_tracker_app/features/accounts/accounts_controller.dart';
import 'package:expense_tracker_app/features/cards/cards_controller.dart';
import 'package:expense_tracker_app/features/cards/cards_screen.dart';
import 'package:expense_tracker_app/features/loans/loans_controller.dart';
import 'package:expense_tracker_app/features/loans/loans_screen.dart';
import 'package:expense_tracker_app/features/settings/settings_controller.dart';

class _Cards extends CardRepository {
  _Cards() : super(AppDatabase.forTesting());
  static final _s = CardStatement(
    id: 1,
    cardId: 1,
    periodStart: DateTime(2026, 10, 15),
    periodEnd: DateTime(2026, 11, 14),
    generatedOn: DateTime(2026, 11, 14),
    dueDate: DateTime(2026, 11, 29),
    figures: const StatementFigures(
      totalDue: 1140000,
      minimumDue: 57000,
      purchases: 1,
    ),
    paidPaise: 57000,
  );
  @override
  Future<List<CreditCard>> list() async => const [
    CreditCard(
      id: 1,
      name: 'A very long card name for wrapping',
      bank: 'HDFC Bank',
      last4: '1234',
      limitPaise: 20000000,
    ),
  ];
  @override
  Future<Map<int, int>> outstanding() async => {1: 3120000};
  @override
  Future<List<CardStatement>> statements(int cardId) async => [_s];
  @override
  Future<List<CardEmi>> emis(int cardId) async => [
    CardEmi(
      id: 1,
      cardId: 1,
      description: 'Fridge',
      purchaseAmount: 3000000,
      purchaseDate: DateTime(2026, 10, 1),
      tenureMonths: 6,
      installment: 520000,
      billed: 1,
    ),
  ];
  @override
  Future<List<Transaction>> spending(int cardId, {int limit = 30}) async => [
    const Transaction(
      id: 9,
      date: '2026-11-05',
      category: 'groceries',
      amountPaise: 500000,
      type: TxnType.expense,
      createdAt: 'x',
      cardId: 1,
    ),
  ];
}

class _Loans extends LoanRepository {
  _Loans() : super(AppDatabase.forTesting());
  @override
  Future<List<LoanStanding>> standings() async {
    final loan = Loan(
      id: 1,
      name: 'Car loan with a long name',
      principalPaise: 10000000,
      emiPaise: 888488,
      tenureMonths: 12,
      rateBps: 1200,
      startDate: DateTime(2026, 12, 5),
      kind: LoanKind.vehicle,
      lender: 'HDFC Bank',
    );
    final plan = LoanRepository.planFor(loan);
    return [
      LoanStanding(
        loan: loan,
        installments: [
          for (final (i, p) in plan.indexed)
            LoanInstallment(
              id: i + 1,
              seq: p.seq,
              dueDate: p.dueDate,
              amount: p.amount,
              principal: p.principal,
              interest: p.interest,
              principalPaid: i == 0 ? p.principal : 0,
              interestPaid: i == 0 ? p.interest : 0,
              status: i == 0 ? 'paid' : 'due',
            ),
        ],
        outstandingPrincipal: 9200000,
        interestPaid: 100000,
      ),
    ];
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    for (final screen in ['cards', 'card detail', 'loans', 'loan detail']) {
      testWidgets('$screen lays out at 320px, 1.5× text, $name', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final cards = CardsController(_Cards());
        final loans = LoansController(loanRepo: _Loans());
        await cards.refresh();
        await loans.refresh();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => SettingsController()),
              ChangeNotifierProvider(create: (_) => AccountsController()),
              ChangeNotifierProvider.value(value: cards),
              ChangeNotifierProvider.value(value: loans),
            ],
            child: MaterialApp(
              theme: theme(),
              home: switch (screen) {
                'cards' => const CardsScreen(),
                'card detail' => const CardDetailScreen(cardId: 1),
                'loans' => const LoansScreen(),
                _ => const LoanDetailScreen(loanId: 1),
              },
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -3000),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
