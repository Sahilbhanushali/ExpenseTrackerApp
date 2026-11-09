import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:expense_tracker_app/core/finance/cards.dart';
import 'package:expense_tracker_app/core/theme/app_theme.dart';
import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/account.dart';
import 'package:expense_tracker_app/data/models/credit_card.dart';
import 'package:expense_tracker_app/data/models/loan.dart';
import 'package:expense_tracker_app/data/models/movement.dart';
import 'package:expense_tracker_app/data/models/transaction.dart';
import 'package:expense_tracker_app/data/repositories/account_repository.dart';
import 'package:expense_tracker_app/data/repositories/card_repository.dart';
import 'package:expense_tracker_app/data/repositories/investment_repository.dart';
import 'package:expense_tracker_app/data/repositories/loan_repository.dart';
import 'package:expense_tracker_app/data/repositories/reconciliation_repository.dart';
import 'package:expense_tracker_app/data/repositories/transaction_repository.dart';
import 'package:expense_tracker_app/features/accounts/account_detail_screen.dart';
import 'package:expense_tracker_app/features/accounts/accounts_controller.dart';
import 'package:expense_tracker_app/features/settings/settings_controller.dart';

import 'helpers/sqflite_ffi_setup.dart';

DateTime d(int m, int day, [int y = 2026]) => DateTime(y, m, day);

void main() {
  group('reconciliation', () {
    setUpAll(initFfiSqflite);
    late AppDatabase app;
    late AccountRepository accounts;
    late TransactionRepository txns;
    late ReconciliationRepository recon;

    setUp(() async {
      app = AppDatabase.forTesting();
      accounts = AccountRepository(app);
      txns = TransactionRepository(app);
      recon = ReconciliationRepository(app);
      await accounts.add('Salary', 1000000);
      await accounts.add('Savings', 0, roles: {AccountRole.savings});
    });

    Future<void> spend(String date, int paise) => txns.add(
      Transaction(
        date: date,
        category: 'food',
        amountPaise: paise,
        type: TxnType.expense,
        createdAt: '${date}T00:00:00.000',
        account: 'Salary',
      ),
    );

    test('balance as of a date ignores later entries', () async {
      await spend('2026-11-10', 100000);
      await spend('2026-11-20', 50000);
      expect(await accounts.balanceAsOf('Salary', d(11, 15)), 900000);
      expect(await accounts.balanceAsOf('Salary', d(11, 20)), 850000);
      expect(await accounts.balance('Salary'), 850000);
    });

    test('a matching check is recorded and moves nothing', () async {
      final r = await recon.reconcileAccount(
        'Salary',
        asOf: d(11, 9),
        actualPaise: 1000000,
      );
      expect(r.matched, isTrue);
      expect(r.adjustmentMovementId, isNull);
      expect((await recon.latest())['account:1']!.id, r.id);
    });

    test('a difference is kept as a check until the user adjusts', () async {
      await spend('2026-11-10', 100000);
      final check = await recon.reconcileAccount(
        'Salary',
        asOf: d(11, 15),
        actualPaise: 880000,
      );
      expect(check.difference, -20000);
      expect(check.matched, isFalse);
      expect(await accounts.balance('Salary'), 900000); // nothing assumed

      final adj = await recon.reconcileAccount(
        'Salary',
        asOf: d(11, 15),
        actualPaise: 880000,
        adjust: true,
        note: 'Bank charges',
      );
      expect(adj.matched, isTrue);
      expect(await accounts.balance('Salary'), 880000);
      expect(await accounts.balanceAsOf('Salary', d(11, 15)), 880000);
      // An adjustment is neither income nor spending.
      final month = await txns.monthTotal('2026-11');
      expect((month.income, month.expense), (0, 100000));
      final history = await accounts.transfersFor('Salary');
      expect(history.single.kind, MovementKind.adjustment);
      final db = await app.database;
      expect(
        await db.query('audit_log', where: "entity = 'reconciliation'"),
        hasLength(2),
      );
    });

    test('a card is checked against what the bank says is owed', () async {
      final cards = CardRepository(app);
      final card = await cards.save(
        const CreditCard(
          name: 'HDFC',
          limitPaise: 10000000,
          openingOutstandingPaise: 500000,
        ),
      );
      final r = await recon.reconcileCard(
        card,
        actualOwedPaise: 520000,
        adjust: true,
        note: 'Late fee not logged',
      );
      expect(r.appBalance, 500000);
      expect((await cards.outstanding())[card], 520000);
      expect((await txns.monthTotal('2026-11')).expense, 0);
    });

    test('planned transfers wait; done and cancel behave', () async {
      final id = await accounts.addTransfer(
        Transfer(
          fromAccount: 'Salary',
          toAccount: 'Savings',
          amountPaise: 300000,
          date: '2026-11-11',
          createdAt: 'x',
          status: MovementStatus.planned,
        ),
      );
      expect((await accounts.plannedTransfers()).single.id, id);
      expect(await accounts.balance('Savings'), 0);
      await accounts.setTransferStatus(id, MovementStatus.completed);
      expect(await accounts.plannedTransfers(), isEmpty);
      expect(await accounts.balance('Savings'), 300000);
      await accounts.setTransferStatus(id, MovementStatus.cancelled);
      expect(await accounts.balance('Savings'), 0);
      await expectLater(
        accounts.setTransferStatus(id, MovementStatus.completed),
        throwsStateError,
      );
    });

    test('cancelling a card payment reopens its statement', () async {
      final cards = CardRepository(app);
      final card = await cards.save(
        const CreditCard(name: 'Card', limitPaise: 1000000),
      );
      final s = await cards.addStatement(
        CardStatement(
          cardId: card,
          periodStart: d(10, 15),
          periodEnd: d(11, 14),
          generatedOn: d(11, 14),
          dueDate: d(11, 29),
          figures: const StatementFigures(totalDue: 200000),
        ),
      );
      final pay = await cards.pay(
        cardId: card,
        fromAccount: 'Salary',
        amountPaise: 200000,
        date: d(11, 20),
        statementId: s,
      );
      await accounts.setTransferStatus(pay, MovementStatus.cancelled);
      final st = (await cards.statements(card)).single;
      expect(st.standing(d(11, 21)).remaining, 200000);
      expect(await accounts.balance('Salary'), 1000000);
    });

    test('loan movements can only be undone from the loan', () async {
      final loans = LoanRepository(app);
      final id = await loans.add(
        Loan(
          name: 'Personal',
          principalPaise: 100000,
          emiPaise: 50000,
          tenureMonths: 2,
          startDate: d(12, 1),
          account: 'Salary',
          opening: LoanOpening.disbursed,
        ),
      );
      final m = (await accounts.transfersFor('Salary')).single;
      expect(m.kind, MovementKind.loanOpen);
      await expectLater(
        accounts.setTransferStatus(m.id!, MovementStatus.cancelled),
        throwsStateError,
      );
      expect(id, isPositive);
    });

    test('account type and money on hold are saved', () async {
      final id = await accounts.add(
        'Wallet',
        0,
        bankType: BankType.wallet,
        holdPaise: 5000,
      );
      final a = (await accounts.list()).firstWhere((x) => x.id == id);
      expect((a.bankType, a.holdPaise), (BankType.wallet, 5000));
      await accounts.update(id, holdPaise: 0);
      expect(
        (await accounts.list()).firstWhere((x) => x.id == id).holdPaise,
        0,
      );
    });
  });

  test('v16 -> v17 adds account fields and the checks table', () async {
    initFfiSqflite();
    final tmp = await Directory.systemTemp.createTemp('spendo_v17');
    addTearDown(() => tmp.delete(recursive: true));
    final path = '${tmp.path}/spendo.db';
    var app = AppDatabase.forTesting(path);
    var db = await app.database;
    await db.execute('DROP TABLE reconciliations');
    await db.execute('ALTER TABLE accounts DROP COLUMN bank_type');
    await db.execute('ALTER TABLE accounts DROP COLUMN hold_amount');
    await db.insert('accounts', {
      'name': 'Old',
      'opening_balance': 1234,
      'is_default': 1,
      'created_at': 'x',
      'type': 'cash',
    });
    await db.execute('PRAGMA user_version = 16');
    await app.close();

    app = AppDatabase.forTesting(path);
    final a = (await AccountRepository(app).list()).single;
    expect((a.name, a.holdPaise, a.bankType), ('Old', 0, null));
    final r = await ReconciliationRepository(app)
        .reconcileAccount('Old', asOf: d(11, 9), actualPaise: 1234);
    expect(r.matched, isTrue);
    await app.close();
  });

  group('account detail screen', () {
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

        final controller = AccountsController(
          _Accounts(),
          _Recon(),
          _Investments(),
        );
        await controller.refresh();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => SettingsController()),
              ChangeNotifierProvider.value(value: controller),
            ],
            child: MaterialApp(
              theme: theme(),
              home: const AccountDetailScreen(accountId: 1),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Check against bank'), findsOneWidget);
        expect(find.text('Deposit'), findsOneWidget);
        expect(find.textContaining('off bank'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Waiting at the bank'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Waiting at the bank'), findsOneWidget);
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -2000),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}

const _salary = 'Salary account with a long name';

class _Accounts extends AccountRepository {
  _Accounts() : super(AppDatabase.forTesting());
  @override
  Future<List<MoneyAccount>> list() async => const [
    MoneyAccount(
      id: 1,
      name: _salary,
      openingBalancePaise: 1000000,
      createdAt: 'x',
      bankName: 'HDFC Bank',
      last4: '1234',
      roles: {AccountRole.salary, AccountRole.daily},
      bankType: BankType.salary,
      holdPaise: 20000,
      isDefault: true,
    ),
    MoneyAccount(id: 2, name: 'Cash', createdAt: 'x', bankType: BankType.cash),
  ];
  @override
  Future<Map<String, int>> allBalances() async => {
    _salary: 1000000,
    'Cash': 5000,
  };
  @override
  Future<int> unassignedTxnCount() async => 0;
  @override
  Future<List<Transfer>> plannedTransfers() async => const [
    Transfer(
      id: 7,
      fromAccount: _salary,
      toAccount: 'Cash',
      amountPaise: 300000,
      date: '2026-11-11',
      createdAt: 'x',
      status: MovementStatus.planned,
    ),
  ];
}

class _Recon extends ReconciliationRepository {
  _Recon() : super(AppDatabase.forTesting());
  static final _r = Reconciliation(
    id: 1,
    ownerType: 'account',
    ownerId: 1,
    asOf: DateTime(2026, 11, 9),
    appBalance: 1000000,
    actualBalance: 990000,
  );
  @override
  Future<Map<String, Reconciliation>> latest() async => {'account:1': _r};
  @override
  Future<List<Reconciliation>> history(String ownerType, int ownerId) async => [
    _r,
  ];
}

class _Investments extends InvestmentRepository {
  _Investments() : super(AppDatabase.forTesting());
  @override
  Future<Map<String, ({int invested, int current, int count})>>
  totals() async => {};
}
