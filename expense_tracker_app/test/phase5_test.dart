import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/core/finance/accounting.dart';
import 'package:expense_tracker_app/core/finance/cards.dart';
import 'package:expense_tracker_app/core/finance/loans.dart';
import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/credit_card.dart';
import 'package:expense_tracker_app/data/models/loan.dart';
import 'package:expense_tracker_app/data/models/transaction.dart';
import 'package:expense_tracker_app/data/repositories/account_repository.dart';
import 'package:expense_tracker_app/data/repositories/card_repository.dart';
import 'package:expense_tracker_app/data/repositories/loan_repository.dart';
import 'package:expense_tracker_app/data/repositories/transaction_repository.dart';

import 'helpers/sqflite_ffi_setup.dart';

DateTime d(int m, int day, [int y = 2026]) => DateTime(y, m, day);

void main() {
  group('loan maths', () {
    test('reducing-balance EMI and schedule add up exactly', () {
      // ₹1,00,000 at 12% for 12 months → ₹8,884.88.
      expect(emiFor(10000000, 1200, 12), 888488);
      final s = buildSchedule(
        principal: 10000000,
        emi: 888488,
        count: 12,
        firstDue: d(12, 5),
        annualRateBps: 1200,
      );
      expect(s, hasLength(12));
      expect(s.first.interest, 100000); // 1% of the balance
      expect(s.fold<int>(0, (a, i) => a + i.principal), 10000000);
      expect(s.last.dueDate, d(11, 5, 2027));
    });

    test(
      'without a rate every EMI is the stated EMI; last absorbs rounding',
      () {
        final s = buildSchedule(
          principal: 5579200,
          emi: 973739,
          count: 6,
          firstDue: d(8, 17),
          totalInterest: 973739 * 6 - 5579200,
        );
        expect(s.take(5).every((i) => i.amount == 973739), isTrue);
        expect(s.fold<int>(0, (a, i) => a + i.amount), 973739 * 6);
        expect(s.fold<int>(0, (a, i) => a + i.principal), 5579200);
      },
    );

    test('payments go to interest first', () {
      final r = splitPayment(
        amount: 50000,
        interestDue: 20000,
        principalDue: 80000,
      );
      expect((r.interest, r.principal, r.unused), (20000, 30000, 0));
      expect(monthsToClear(10000000, 888488, 1200), 12);
    });
  });

  group('statement maths', () {
    test('the statement’s own arithmetic and its standing', () {
      const f = StatementFigures(
        previousBalance: 400000,
        payments: 400000,
        purchases: 500000,
        emiInstallments: 520000,
        charges: 120000,
        totalDue: 1140000,
        minimumDue: 57000,
      );
      expect(f.computedDue, 1140000);
      expect(f.difference, 0);
      StatementStanding at(DateTime today, int paid) => StatementStanding(
        totalDue: 1140000,
        minimumDue: 57000,
        paid: paid,
        dueDate: d(11, 29),
        today: today,
      );
      expect(at(d(11, 20), 0).state, StatementState.unpaid);
      expect(at(d(11, 20), 57000).state, StatementState.partlyPaid);
      expect(at(d(11, 20), 57000).minimumRemaining, 0);
      expect(at(d(11, 30), 57000).state, StatementState.overdue);
      expect(at(d(11, 30), 57000).revolving, isTrue);
      expect(at(d(11, 30), 1140000).state, StatementState.paid);
    });
  });

  group('cards on the ledger', () {
    setUpAll(initFfiSqflite);
    late AppDatabase app;
    late CardRepository cards;
    late TransactionRepository txns;
    late AccountRepository accounts;
    late int card;

    setUp(() async {
      app = AppDatabase.forTesting();
      cards = CardRepository(app);
      txns = TransactionRepository(app);
      accounts = AccountRepository(app);
      await accounts.add('Salary', 2000000);
      card = await cards.save(
        const CreditCard(name: 'HDFC', last4: '1234', limitPaise: 10000000),
      );
    });

    Future<int> spend(String date, int paise, {String note = 'Shopping'}) =>
        txns.add(
          Transaction(
            date: date,
            category: 'groceries',
            amountPaise: paise,
            note: note,
            type: TxnType.expense,
            createdAt: '${date}T00:00:00.000',
            cardId: card,
          ),
        );

    test('a card purchase is spending on the card, not the bank', () async {
      await spend('2026-11-05', 500000);
      expect((await txns.monthTotal('2026-11')).expense, 500000);
      expect((await cards.outstanding())[card], 500000);
      expect(await accounts.balance('Salary'), 2000000);
      expect(await accounts.unassignedTxnCount(), 0);
    });

    test(
      'scenarios 3, 4 & 6: statement 14 Nov due 29 Nov, paid from salary',
      () async {
        await spend('2026-11-05', 500000);
        final s = await cards.addStatement(
          CardStatement(
            cardId: card,
            periodStart: d(10, 15),
            periodEnd: d(11, 14),
            generatedOn: d(11, 14),
            dueDate: d(11, 29),
            figures: const StatementFigures(
              totalDue: 500000,
              minimumDue: 25000,
            ),
          ),
        );
        var st = (await cards.statements(card)).single;
        expect(st.standing(d(11, 20)).state, StatementState.unpaid);
        expect(st.standing(d(11, 30)).state, StatementState.overdue);

        await cards.pay(
          cardId: card,
          fromAccount: 'Salary',
          amountPaise: 500000,
          date: d(11, 25),
          statementId: s,
        );
        st = (await cards.statements(card)).single;
        expect(st.standing(d(11, 30)).state, StatementState.paid);
        expect(await accounts.balance('Salary'), 1500000);
        expect((await cards.outstanding())[card], 0);
        // Rule 2: paying the bill is not more spending.
        expect((await txns.monthTotal('2026-11')).expense, 500000);
      },
    );

    test('scenario 5: fridge EMI on the card is counted once', () async {
      final fridge = await spend('2026-10-01', 3000000, note: 'Fridge');
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
      await cards.addStatement(
        CardStatement(
          cardId: card,
          periodStart: d(10, 15),
          periodEnd: d(11, 14),
          generatedOn: d(11, 14),
          dueDate: d(11, 29),
          figures: const StatementFigures(
            totalDue: 640000,
            emiInstallments: 520000,
            charges: 120000,
          ),
        ),
        billedEmis: {emi: (principal: null, interest: null)},
        newCharges: 120000,
      );
      // October: the fridge once. November: only interest + GST.
      expect((await txns.monthTotal('2026-10')).expense, 3000000);
      expect((await txns.monthTotal('2026-11')).expense, 120000);
      expect((await cards.outstanding())[card], 3000000 + 120000);
      final e = (await cards.emis(card)).single;
      expect(e.billed, 1);
      expect(e.standing.remainingPayable, 520000 * 5);
      // The bank gave no principal split, so none is invented.
      expect(e.standing.principalOutstanding, isNull);
      await expectLater(
        cards.addEmi(
          CardEmi(
            cardId: card,
            purchaseTxnId: fridge,
            description: 'x',
            purchaseAmount: 1,
            purchaseDate: d(10, 1),
            tenureMonths: 1,
            installment: 1,
          ),
        ),
        throwsA(isA<CardException>()),
      );
    });

    test('a refund on a card purchase goes back to the card', () async {
      final id = await spend('2026-11-05', 500000);
      await txns.addRefund(
        expenseId: id,
        amountPaise: 100000,
        date: '2026-11-08',
      );
      expect((await cards.outstanding())[card], 400000);
      expect(await accounts.balance('Salary'), 2000000);
    });

    test('statements are validated and not duplicated', () async {
      final s = CardStatement(
        cardId: card,
        periodStart: d(10, 15),
        periodEnd: d(11, 14),
        generatedOn: d(11, 14),
        dueDate: d(11, 29),
        figures: const StatementFigures(totalDue: 100, minimumDue: 200),
      );
      await expectLater(cards.addStatement(s), throwsA(isA<CardException>()));
      final ok = CardStatement(
        cardId: card,
        periodStart: s.periodStart,
        periodEnd: s.periodEnd,
        generatedOn: s.generatedOn,
        dueDate: s.dueDate,
        figures: const StatementFigures(totalDue: 100),
      );
      await cards.addStatement(ok);
      await expectLater(cards.addStatement(ok), throwsA(isA<CardException>()));
    });
  });

  group('loans on the ledger', () {
    setUpAll(initFfiSqflite);
    late AppDatabase app;
    late LoanRepository loans;
    late TransactionRepository txns;
    late AccountRepository accounts;

    setUp(() async {
      app = AppDatabase.forTesting();
      loans = LoanRepository(app);
      txns = TransactionRepository(app);
      accounts = AccountRepository(app);
      await accounts.add('Bank', 5000000);
    });

    Future<LoanStanding> only() async => (await loans.standings()).single;

    Loan personal({LoanOpening opening = LoanOpening.existing}) => Loan(
      name: 'Personal',
      principalPaise: 10000000,
      emiPaise: 888488,
      tenureMonths: 12,
      rateBps: 1200,
      startDate: d(12, 5),
      account: 'Bank',
      opening: opening,
    );

    test('opening: existing moves nothing, disbursed is not income', () async {
      await loans.add(personal(opening: LoanOpening.disbursed));
      expect(await accounts.balance('Bank'), 15000000);
      expect((await txns.monthTotal('2026-11')).income, 0);
      expect((await only()).outstandingPrincipal, 10000000);
      expect((await only()).loan.splitEstimated, isFalse);
    });

    test(
      'bought on EMI: the item is one expense, EMIs repay the loan',
      () async {
        await loans.add(
          Loan(
            name: 'Washing machine',
            principalPaise: 3000000,
            emiPaise: 500000,
            tenureMonths: 6,
            startDate: DateTime.now(),
            account: 'Bank',
            opening: LoanOpening.purchase,
            kind: LoanKind.consumer,
          ),
          purchaseCategory: 'other',
        );
        final id = (await only()).loan.id!;
        await loans.payInstallment(id, date: DateTime.now(), account: 'Bank');
        final rows = await txns.queryPage();
        // Purchase only — a no-cost EMI's installment adds no spending.
        expect(rows.where((t) => t.type == TxnType.expense), hasLength(1));
        expect((await only()).outstandingPrincipal, 2500000);
      },
    );

    test('prepayment: finish sooner, or lower the EMI', () async {
      await loans.add(personal());
      final id = (await only()).loan.id!;
      await loans.prepay(
        id,
        amountPaise: 5000000,
        date: d(11, 30),
        account: 'Bank',
      );
      var l = await only();
      expect(l.outstandingPrincipal, 5000000);
      expect(l.due.length, lessThan(12));
      expect(l.loan.emiPaise, 888488);

      await loans.prepay(
        id,
        amountPaise: 1000000,
        date: d(11, 30),
        account: 'Bank',
        mode: PrepayMode.reduceEmi,
      );
      l = await only();
      expect(l.loan.emiPaise, lessThan(888488));
      expect(l.due.fold<int>(0, (a, i) => a + i.principal), 4000000);
      // Prepayments are principal, never spending.
      expect((await txns.monthTotal('2026-11')).expense, 0);
      expect(await accounts.balance('Bank'), 5000000 - 6000000);
    });

    test(
      'foreclosure pays off the rest and records charges as expense',
      () async {
        await loans.add(personal());
        final id = (await only()).loan.id!;
        await loans.payInstallment(id, date: d(12, 5), account: 'Bank');
        await loans.foreclose(
          id,
          date: d(12, 10),
          account: 'Bank',
          chargesPaise: 20000,
        );
        final l = await only();
        expect(l.closed, isTrue);
        expect(l.outstandingPrincipal, 0);
        expect(l.due, isEmpty);
        expect((await txns.monthTotal('2026-12')).expense, 100000 + 20000);
      },
    );

    test('correcting the balance moves no money and is audited', () async {
      await loans.add(personal());
      final id = (await only()).loan.id!;
      await loans.correctOutstanding(id, 9500000, note: 'Lender statement');
      expect((await only()).outstandingPrincipal, 9500000);
      expect(await accounts.balance('Bank'), 5000000);
      final db = await app.database;
      expect(
        await db.query(
          'audit_log',
          where: "entity = 'loan' AND action = 'correct'",
        ),
        hasLength(1),
      );
    });

    test('installments are never generated twice', () async {
      await loans.add(personal());
      await loans.standings();
      await loans.standings();
      expect((await only()).installments, hasLength(12));
    });
  });

  test('net worth subtracts cards and loans', () {
    const nw = NetWorth(
      accounts: 5000000,
      receivables: 0,
      borrowed: 0,
      loans: 2000000,
      cards: 640000,
    );
    expect(nw.total, 2360000);
  });

  test('v15 -> v16 keeps an old loan and builds its schedule once', () async {
    initFfiSqflite();
    final tmp = await Directory.systemTemp.createTemp('spendo_v16');
    addTearDown(() => tmp.delete(recursive: true));
    final path = '${tmp.path}/spendo.db';
    var app = AppDatabase.forTesting(path);
    var db = await app.database;
    for (final t in [
      'credit_cards',
      'card_statements',
      'card_emis',
      'card_statement_emis',
      'loan_installments',
      'loan_events',
    ]) {
      await db.execute('DROP TABLE $t');
    }
    await db.execute('DROP INDEX idx_txns_card');
    await db.execute('ALTER TABLE txns DROP COLUMN card_id');
    for (final c in [
      'kind',
      'lender',
      'rate_bps',
      'status',
      'split_estimated',
      'opening',
    ]) {
      await db.execute('ALTER TABLE loans DROP COLUMN $c');
    }
    await db.insert('loans', {
      'name': 'Fridge',
      'principal': 5579200,
      'interest_amount': 263234,
      'emi_amount': 973739,
      'tenure_months': 6,
      'installments_paid': 2,
      'start_date': '2026-08-17T00:00:00.000',
      'active': 1,
    });
    await db.execute('PRAGMA user_version = 15');
    await app.close();

    app = AppDatabase.forTesting(path);
    final loans = LoanRepository(app);
    final l = (await loans.standings()).single;
    expect(l.installments, hasLength(6));
    expect(l.paidCount, 2);
    final paidPrincipal = l.installments
        .take(2)
        .fold<int>(0, (a, i) => a + i.principal);
    expect(l.outstandingPrincipal, 5579200 - paidPrincipal);
    expect(l.loan.splitEstimated, isTrue);
    await loans.standings();
    expect((await loans.standings()).single.installments, hasLength(6));
    await app.close();
  });
}
